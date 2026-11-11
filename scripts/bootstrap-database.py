#!/usr/bin/env python3
"""Create the lab application DB login through a short-lived EKS Job.

Uses AWS CLI and kubectl, not boto3. Credentials stay in memory/API stdin.
Run from any directory. Never prints secret values or raw subprocess errors.
"""
import argparse
import base64
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import time
import urllib.parse

ROOT = Path(__file__).resolve().parents[1]
TERRAFORM = ROOT / "infrastructure/terraform/environments/prod"
FILES = ROOT / "infrastructure/kubernetes/database-bootstrap"


def run(args, payload=None):
    result = subprocess.run(args, input=payload, text=True, capture_output=True)
    if result.returncode:
        # Failed commands could include database URLs/passwords in their stderr.
        raise RuntimeError(f"{args[0]} {args[1]} failed; check SSO, context and resource access.")
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", default="production")
    parser.add_argument("--context", default="order-platform-prod")
    parser.add_argument("--namespace", default="order-platform-prod")
    options = parser.parse_args()
    os.environ["AWS_PROFILE"] = options.profile
    os.environ["AWS_EC2_METADATA_DISABLED"] = "true"
    # This helper deliberately targets the current prod environment only.
    identity = json.loads(run(["aws", "sts", "get-caller-identity"]))
    if identity["Account"] != "792289066018":
        raise RuntimeError("Expected AWS account 792289066018; refusing a different account.")
    cluster = json.loads(run(["aws", "eks", "describe-cluster", "--region", "eu-west-2",
                              "--name", "order-platform-prod"]))["cluster"]
    kube_config = json.loads(run(["kubectl", "--context", options.context, "config", "view",
                                 "--minify", "-o", "json"]))
    if kube_config["clusters"][0]["cluster"]["server"] != cluster["endpoint"]:
        raise RuntimeError("Selected Kubernetes context does not match the current prod cluster.")
    kube = ["kubectl", "--context", options.context, "--namespace", options.namespace]

    def apply(obj):
        run(kube + ["apply", "-f", "-"], json.dumps(obj))

    # Read only the required Terraform outputs, never the entire state.
    def output(name):
        return run(["terraform", f"-chdir={TERRAFORM}", "output", "-raw", name]).strip()

    host = output("rds_address")
    arn = output("rds_master_user_secret_arn")
    secret_result = json.loads(run(["aws", "secretsmanager", "get-secret-value",
                                   "--region", "eu-west-2", "--secret-id", arn]))
    admin = json.loads(secret_result["SecretString"])
    # Download the public AWS certificate bundle. It contains no credentials.
    ca = run(["curl", "--fail", "--silent", "--show-error", "--max-time", "30",
              "https://truststore.pki.rds.amazonaws.com/eu-west-2/eu-west-2-bundle.pem"])
    if "-----BEGIN CERTIFICATE-----" not in ca:
        raise RuntimeError("RDS CA download did not contain certificates.")
    apply({"apiVersion": "v1", "kind": "Namespace", "metadata": {"name": options.namespace}})
    apply({"apiVersion": "v1", "kind": "ConfigMap", "metadata": {"name": "rds-ca"},
           "data": {"bundle.pem": ca}})

    # Preserve the application password on reruns instead of silently rotating it.
    existing = json.loads(run(kube + ["get", "secret", "order-service-secrets",
                                      "--ignore-not-found", "-o", "json"]) or "null")
    if existing:
        data = existing.get("data", {})
        if "APP_PASSWORD" not in data:
            raise RuntimeError("Existing order-service-secrets lacks APP_PASSWORD; refusing to overwrite it.")
        password = base64.b64decode(data["APP_PASSWORD"]).decode()
    else:
        password = secrets.token_urlsafe(36)

    execution = "db-bootstrap-" + secrets.token_hex(4)
    credentials = {
        "PGHOST": host, "PGPORT": "5432", "PGDATABASE": "orders",
        "PGUSER": admin["username"], "PGPASSWORD": admin["password"],
        "PGSSLMODE": "verify-full", "PGSSLROOTCERT": "/etc/rds-ca/bundle.pem",
        "PGCONNECT_TIMEOUT": "10", "APP_PASSWORD": password,
    }
    try:
        # create (not apply) avoids a last-applied annotation containing credentials.
        run(kube + ["create", "-f", "-"], json.dumps({
            "apiVersion": "v1", "kind": "Secret", "metadata": {"name": execution},
            "type": "Opaque", "stringData": credentials,
        }))
        apply({"apiVersion": "v1", "kind": "ConfigMap", "metadata": {"name": execution},
               "data": {"setup.sql": (FILES / "setup.sql").read_text()}})
        run(kube + ["create", "-f", "-"], (FILES / "job.yaml").read_text().replace("__RUN__", execution))
        print(f"Running {execution} in {options.context}/{options.namespace}...", flush=True)
        deadline = time.monotonic() + 300
        while time.monotonic() < deadline:
            job = json.loads(run(kube + ["get", "job", execution, "-o", "json"]))
            conditions = job.get("status", {}).get("conditions", [])
            if any(c["type"] == "Complete" and c["status"] == "True" for c in conditions):
                break
            if any(c["type"] == "Failed" and c["status"] == "True" for c in conditions):
                raise RuntimeError(f"Setup Job failed. Inspect pod events for job {execution}; credentials are not printed.")
            time.sleep(3)
        else:
            raise RuntimeError(f"Timed out waiting for {execution}.")
        params = urllib.parse.urlencode({"sslmode": "verify-full", "sslrootcert": "/etc/rds-ca/bundle.pem"})
        url = f"postgres://ordersapp:{urllib.parse.quote(password, safe='')}@{host}:5432/orders?{params}"
        app_secret = {
            "apiVersion": "v1", "kind": "Secret", "metadata": {"name": "order-service-secrets"},
            "type": "Opaque", "stringData": {"APP_PASSWORD": password, "DATABASE_URL": url},
        }
        if existing:
            # JSON merge patch preserves metadata; no secret-valued annotation.
            run(kube + ["patch", "secret", "order-service-secrets", "--type=merge", "--patch-file=/dev/stdin"],
                json.dumps({"stringData": app_secret["stringData"]}))
        else:
            run(kube + ["create", "-f", "-"], json.dumps(app_secret))
        print("Database login verified; order-service-secrets and rds-ca are ready. No apps deployed.")
    finally:
        # Remove administrator credentials and the Job that used them, even on failure.
        # Failure details remain in generic Job events; retry this command after fixing access.
        for kind in ("job", "secret", "configmap"):
            try:
                run(kube + ["delete", kind, execution, "--ignore-not-found", "--wait=false"])
            except RuntimeError:
                print(f"Cleanup needed: delete {kind}/{execution} in {options.namespace}.", file=sys.stderr)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError) as error:
        # Do not emit traceback/local variables containing credentials.
        print(f"Database setup stopped: {error}", file=sys.stderr)
        sys.exit(1)

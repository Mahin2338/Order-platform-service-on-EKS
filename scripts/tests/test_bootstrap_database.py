"""Exercise orchestration offline: no AWS, Kubernetes or credentials needed."""
import base64
import importlib.util
import io
import json
from pathlib import Path
import unittest
from unittest.mock import patch

MODULE = Path(__file__).resolve().parents[1] / "bootstrap-database.py"
spec = importlib.util.spec_from_file_location("bootstrap", MODULE)
bootstrap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bootstrap)


class BootstrapTests(unittest.TestCase):
    def simulate(self, existing=None, job_failed=False, endpoint="https://prod", jwt_existing=None):
        calls = []
        def fake_run(args, payload=None):
            calls.append((args, payload))
            if args[0] == "curl":
                return "-----BEGIN CERTIFICATE-----\npublic-ca\n"
            if args[:3] == ["aws", "sts", "get-caller-identity"]:
                return json.dumps({"Account": "792289066018"})
            if args[:3] == ["aws", "eks", "describe-cluster"]:
                return json.dumps({"cluster": {"endpoint": "https://prod"}})
            if "config" in args:
                return json.dumps({"clusters": [{"cluster": {"server": endpoint}}]})
            if args[0] == "terraform":
                return "db.example" if args[-1] == "rds_address" else "secret-arn"
            if args[:3] == ["aws", "secretsmanager", "get-secret-value"]:
                return json.dumps({"SecretString": json.dumps({"username": "dbadmin", "password": "admin-private"})})
            if "get" in args and "secret" in args:
                found = jwt_existing if "api-gateway-secrets" in args else existing
                return json.dumps(found) if found is not None else ""
            if "get" in args and "job" in args:
                return json.dumps({"status": {"conditions": [{"type": "Failed" if job_failed else "Complete", "status": "True"}]}})
            return ""
        output = io.StringIO()
        with patch.object(bootstrap, "run", side_effect=fake_run), \
             patch.object(bootstrap.secrets, "token_urlsafe", return_value="generated-private"), \
             patch.object(bootstrap.sys, "argv", [str(MODULE)]), \
             patch.dict(bootstrap.os.environ), patch("sys.stdout", output):
            error = None
            try:
                bootstrap.main()
            except RuntimeError as exc:
                error = exc
        return calls, output.getvalue(), error

    def test_first_run_creates_connection_secret_and_cleans_admin(self):
        calls, output, error = self.simulate()
        self.assertIsNone(error)
        objects = [json.loads(body) for args, body in calls if body and body.startswith('{')]
        app = next(obj for obj in objects if obj.get("metadata", {}).get("name") == "order-service-secrets")
        self.assertIn("sslmode=verify-full", app["stringData"]["DATABASE_URL"])
        self.assertIn("sslrootcert=", app["stringData"]["DATABASE_URL"])
        self.assertNotIn("admin-private", output)
        self.assertNotIn("generated-private", output)
        self.assertEqual(sum("delete" in args for args, _ in calls), 3)

    def test_rerun_preserves_password_and_patches_secret(self):
        password = "existing-private"
        calls, _, error = self.simulate({"data": {"APP_PASSWORD": base64.b64encode(password.encode()).decode()}})
        self.assertIsNone(error)
        patch_body = next(body for args, body in calls if "patch" in args)
        self.assertEqual(json.loads(patch_body)["stringData"]["APP_PASSWORD"], password)

    def test_failed_job_never_publishes_app_secret_and_cleans_admin(self):
        calls, _, error = self.simulate(job_failed=True)
        self.assertIsNotNone(error)
        self.assertFalse(any(body and '"name": "order-service-secrets"' in body for _, body in calls))
        self.assertEqual(sum("delete" in args for args, _ in calls), 3)

    def test_wrong_cluster_stops_before_any_writes(self):
        calls, _, error = self.simulate(endpoint="https://different")
        self.assertIsNotNone(error)
        self.assertFalse(any("apply" in args or "create" in args for args, _ in calls))


    def test_first_run_creates_jwt_without_printing_value(self):
        calls, output, error = self.simulate()
        self.assertIsNone(error)
        created = [json.loads(body) for args, body in calls
                   if "create" in args and body and body.startswith("{")]
        jwt = next(obj for obj in created if obj["metadata"]["name"] == "api-gateway-secrets")
        self.assertTrue(jwt["stringData"]["JWT_SECRET"])
        self.assertNotIn(jwt["stringData"]["JWT_SECRET"], output)
        self.assertFalse(any("generated-private" in arg for args, _ in calls for arg in args))

    def test_existing_jwt_is_not_modified(self):
        calls, output, error = self.simulate(jwt_existing={
            "data": {"JWT_SECRET": base64.b64encode(b"existing-signing-value").decode()}})
        self.assertIsNone(error)
        writes = [body for args, body in calls if "create" in args or "patch" in args]
        self.assertFalse(any(body and '"name": "api-gateway-secrets"' in body for body in writes))
        self.assertNotIn("existing-signing-value", output)

    def test_malformed_existing_jwt_is_not_replaced(self):
        calls, _, error = self.simulate(jwt_existing={"data": {}})
        self.assertIsNotNone(error)
        self.assertFalse(any(body and '"name": "api-gateway-secrets"' in body for _, body in calls))
        self.assertEqual(sum("delete" in args for args, _ in calls), 3)


if __name__ == "__main__":
    unittest.main()

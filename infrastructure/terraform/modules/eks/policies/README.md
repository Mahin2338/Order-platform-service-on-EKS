# Load Balancer Controller policy

`load-balancer-controller-v3.6.2.json` is the unmodified upstream IAM policy:
https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v3.6.2/docs/install/iam_policy.json

Use it with controller v3.6.2; verify the Helm chart appVersion before installation.
Review policy changes when upgrading the controller. It includes upstream optional
integrations (certificate discovery, Cognito, WAF and Shield), not just basic ALB
operations. Some permissions use wildcard resources; tag conditions constrain
several mutations, but this is not a policy scoped exclusively to this cluster.
The role trust is restricted to this cluster's controller service account.

This policy attachment alone does not install the controller or create an ALB.

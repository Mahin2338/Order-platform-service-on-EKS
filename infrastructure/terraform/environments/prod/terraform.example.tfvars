aws_region = "eu-west-2"
# Replace with the intended production account ID, not whichever account is logged in.
prod_account_id = "YOUR_12_DIGIT_ACCOUNT_ID"

vpc_cidr           = "10.0.0.0/16"
availability_zones = ["eu-west-2a", "eu-west-2b", "eu-west-2c"]

# Use the IAM role ARN, including its full path, not an assumed-role session ARN.
eks_operator_role_arn = "arn:aws:iam::YOUR_12_DIGIT_ACCOUNT_ID:role/YOUR_OPERATOR_ROLE"

# Scaffold only — nothing is deployed here yet. CI never targets this
# directory; do not `terragrunt apply`/`plan` here until account 737133467188
# is actually ready to receive resources.
locals {
  environment = "prod"
  region      = "us-east-1"
  account_id  = "737133467188"
}

# Scaffold only — no staging AWS account exists yet. Fill in account_id
# when one is provisioned; CI never targets this directory in the meantime.
locals {
  environment = "staging"
  region      = "us-east-1"
  account_id  = ""
}

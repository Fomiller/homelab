locals {
  units_path = find_in_parent_folders("units")
}

unit "cluster" {
  source                  = "${local.units_path}/talos/global/cluster"
  path                    = "cluster"
  no_dot_terragrunt_stack = true
}

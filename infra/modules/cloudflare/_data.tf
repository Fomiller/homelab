data "aws_kms_key" "fomiller_master" {
  key_id = "alias/fomiller-master"
}

data "cloudflare_zone" "this" {
  filter = {
    name = var.zone_name
  }
}

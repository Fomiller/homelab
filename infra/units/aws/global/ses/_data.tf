data "aws_kms_key" "fomiller_master" {
  key_id = "alias/${var.namespace}-master"
}

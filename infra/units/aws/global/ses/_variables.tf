# The domain SES verifies as a sending identity — same zone
# cloudflare/global/dns manages DNS for.
variable "zone_name" {
  type    = string
  default = "fomiller.com"
}

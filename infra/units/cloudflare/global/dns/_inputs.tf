# From cloudflare/global/tunnels
variable "tunnel_id" {
  type = string
}

# From aws/global/ses
variable "verification_token" {
  type = string
}

variable "dkim_tokens" {
  type = list(string)
}

# authentik access

authentik applications and identity wiring. Two consumers today:

- **Cloudflare Access** (`main.tf`) — OAuth2/OIDC provider Cloudflare Zero Trust
  uses as a sign-in option.
- **AWS IAM Identity Center** (`aws-sso.tf`) — SAML provider plus SCIM
  provisioning, so AWS logins authenticate against authentik.

Users come from `aws/global/secrets` (`var.users`). Nobody is declared here.

## AWS SSO

### How logging in works

1. Open the AWS access portal, `https://d-xxxxxxxxxx.awsapps.com/start`.
2. Identity Center sees an external IdP and redirects to authentik.
3. authentik authenticates (or reuses your session) and posts the assertion
   back.
4. The portal lists the accounts and roles your groups map to.

You do not start in authentik. The AWS tile on the authentik dashboard works,
but it is not the path.

CLI access is the same identity:

```sh
aws configure sso
# start URL: https://d-xxxxxxxxxx.awsapps.com/start
# region:    us-east-1
aws sts get-caller-identity --profile <profile you named>
```

### Who gets what

Two authentik groups, both built from `var.users`:

| group          | who            | AWS access                                |
| -------------- | -------------- | ----------------------------------------- |
| `aws-admins`   | `admin = true` | `AdministratorAccess` on org, dev, prod   |
| `aws-readonly` | everyone       | `ReadOnlyAccess` on org, dev, prod        |

Permission sets and account assignments are not in this repo — they live in
`aws-org`, `infra/modules/aws/org/identity-center`. This side only decides who
is in which group and pushes that over SCIM.

To add someone: add them to `var.users` in
`infra/units/aws/global/secrets/_variables.tf` and apply. They get an authentik
user, a generated password in Secrets Manager, `aws-readonly`, and (if
`admin = true`) `aws-admins`. The next SCIM sync carries it to AWS.

### One-time setup

Identity Center cannot be enabled, pointed at an external IdP, or switched to
automatic provisioning by Terraform — no AWS provider resource covers any of
the three. `sso-admin create-instance` only makes an account instance, which
can't do multi-account assignments, so this is console work in the management
account (`013683865476`, us-east-1).

The wizard wants IdP metadata and hands back the SP details on the same screen,
so it interleaves with applies:

1. Console → IAM Identity Center → enable.
2. Settings → Identity source → Change to **External identity provider**. Copy
   the **IdP SAML ACS URL** and **IdP issuer URL** (the audience). Leave the
   page open.
3. Set `AWS_SSO_ACS_URL`, `AWS_SSO_AUDIENCE` and `AWS_SSO_PORTAL_URL` in Doppler
   (`homelab` / `dev`), then:

   ```sh
   just apply authentik/global/access
   just output authentik/global/access   # aws_sso_saml_metadata
   ```

4. Paste that XML into the open wizard as the IdP metadata. Save.
5. Same settings page → enable **Automatic provisioning**. Copy the SCIM
   endpoint and the access token. The token is shown once.
6. Set `AWS_SSO_SCIM_URL` and `AWS_SSO_SCIM_TOKEN` in Doppler, apply again.
7. authentik → Providers → *AWS Identity Center* → run the sync. Both groups
   and all users should appear under Identity Center → Groups / Users.
8. In `aws-org`, apply `infra/modules/aws/org/identity-center`. It looks the
   groups up by display name, so it fails until step 7 has run.

Until step 3 the AWS resources here are dormant — the variables default to
empty and the `count` gates skip everything.

### Gotchas

- **NameID must equal the SCIM `userName`.** The stock SCIM user mapping sets
  `userName` to the authentik *username*, not the email, so `name_id_mapping`
  points at the Username mapping. Change one and you have to change the other,
  or logins fail after the redirect with no useful error.
- **Rotating the SCIM token** is a console action (Identity Center →
  Provisioning). Put the new value in Doppler and re-apply; nothing detects the
  old one going stale except failing syncs.
- **The IAM users still exist.** `AWSTerraformDEV` / `AWSTERRAFORM` and their
  static keys are what Terraform and CI use. SSO is a human login path, not a
  replacement for those yet.

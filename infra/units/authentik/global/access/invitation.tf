# Invite-only enrollment: binds an Invitation stage as the first stage of
# default-source-enrollment, so a source login (e.g. the Google source in
# google-source.tf) with no matching existing user can't self-enroll without
# a valid invitation token in the URL — continue_flow_without_invitation
# defaults to false, so no token means the flow stops here.
#
# Individual invitations (the actual per-person tokens/links) aren't
# Terraform resources in the goauthentik provider — they're ephemeral,
# created via the authentik UI (Directory > Invitations) or API, same as
# how they'd be created by hand normally.
resource "authentik_stage_invitation" "default" {
  name = "default-invitation"
}

# order = -1 puts this ahead of the stock enrollment flow's stages, which
# all use non-negative orders (0, 10, 20, ...).
resource "authentik_flow_stage_binding" "source_enrollment_invitation" {
  target = data.authentik_flow.source_enrollment.id
  stage  = authentik_stage_invitation.default.id
  order  = -1
}

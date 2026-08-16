# ---------------------------------------------------------------------------
# Bootstrap Secret for the External Secrets Operator's ClusterSecretStore
# ---------------------------------------------------------------------------
# Per ADR-0006, the 1Password service-account token that ESO itself needs to
# authenticate cannot come from ESO (that would be circular). It is delivered
# here via Terraform, outside ArgoCD's reconciliation loop — a deliberate
# exception, not an oversight. Its lifecycle (initial creation, rotation)
# lives in opentofu-infra state.
#
# The homelab-k8s `infra/eso` ClusterSecretStore references this Secret by
# exact name/namespace/key (`external-secrets` / `onepassword-token` /
# `token`). Changing any of those three values here breaks the cross-repo
# contract; if they ever need to move, update both repos in lockstep.
#
# `data_wo` is a write-only attribute (provider v3, OpenTofu >= 1.10): the
# token is sent to the cluster at apply time but is never written to the
# state file or shown in plan output. The value comes from
# ephemeral.onepassword_item.eso_service_account_token (onepassword.tf), a
# true ephemeral resource — fetched fresh each phase, never persisted
# anywhere. Rotation = bump the token in 1Password, then bump
# var.onepassword_service_account_token_revision below, re-apply.
#
# The provider does NOT auto-track a revision counter — it must be set
# explicitly. `data_wo` is only written to the cluster when
# `data_wo_revision >= 1` (create) and only re-pushed when it changes
# (update). Without it the data_wo payload is silently skipped and the
# Secret is created empty.
#
# This used to auto-derive the revision from a SHA-256 hash of the token
# value, so rotation was self-detecting. That trick requires a non-ephemeral
# copy of the token to hash — an ephemeral value stays ephemeral through
# function calls (sha256() included), so it can't feed a plain argument like
# data_wo_revision. Genuinely never letting the token touch state means
# giving up auto-detection: the revision is now a manually-bumped variable.

resource "kubernetes_namespace_v1" "external_secrets" {
  metadata {
    name = "external-secrets"
  }

  # The homelab-k8s ESO Helm chart also targets this namespace (via
  # CreateNamespace=true in the ApplicationSet). Ignore external changes
  # so Terraform creates it once and then yields ownership to the chart /
  # ArgoCD — avoids drift from labels/annotations the chart may add.
  lifecycle {
    ignore_changes = all
  }
}

resource "kubernetes_secret_v1" "onepassword_token" {
  metadata {
    name      = "onepassword-token"
    namespace = kubernetes_namespace_v1.external_secrets.metadata[0].name
  }

  # Must be >= 1 for data_wo to be written; must change for data_wo to be
  # re-pushed on update. Bump manually in variables.tf whenever the
  # 1Password item's token value is rotated — see comment above.
  data_wo_revision = var.onepassword_service_account_token_revision

  data_wo = {
    token = ephemeral.onepassword_item.eso_service_account_token.credential
  }
}

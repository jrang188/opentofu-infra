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
# state file or shown in plan output. Rotation = bump the token in 1Password,
# update .env.tofu, re-apply. The provider tracks a data_wo_revision counter
# so a changed token is pushed on the next apply even though the value is
# not readable back from state.

resource "kubernetes_namespace_v1" "external_secrets" {
  metadata {
    name = "eso"
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

  data_wo = {
    token = var.onepassword_service_account_token
  }
}

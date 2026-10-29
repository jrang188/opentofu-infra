#!/usr/bin/env bash
# shellcheck shell=bash
#
# Usage:  source terraform/hermes-vps/env.sh
#
# Exports TF_ENCRYPTION so OpenTofu encrypts this root's state and plan files.
# Must be sourced (not executed) — it sets an environment variable in your shell.
#
# The passphrase lives in 1Password. State encrypted without it is unreadable,
# and OpenTofu fails closed rather than rewriting state in plaintext, so a
# forgotten `source` is an error, not a silent downgrade.
#
# Not `set -e`: this file runs in the caller's shell and must not change its
# behaviour on an unrelated command failure.

_pass="$(op read 'op://Development/tofu-state/hermes-vps-passphrase')"
if [ -z "$_pass" ]; then
  echo "env.sh: empty passphrase from 1Password — is the op CLI signed in?" >&2
  unset _pass
  return 1 2>/dev/null || exit 1
fi

# Escape the two characters that would break an HCL string literal. Anything
# else (base64, hex, urlsafe) passes through untouched.
_pass_escaped="${_pass//\\/\\\\}"
_pass_escaped="${_pass_escaped//\"/\\\"}"

TF_ENCRYPTION="$(
  printf '%s\n' \
    'key_provider "pbkdf2" "state" {' \
    "  passphrase = \"${_pass_escaped}\"" \
    '}' \
    'method "aes_gcm" "state" {' \
    '  keys = key_provider.pbkdf2.state' \
    '}' \
    'state {' \
    '  method = method.aes_gcm.state' \
    '}' \
    'plan {' \
    '  method = method.aes_gcm.state' \
    '}'
)"
export TF_ENCRYPTION

unset _pass _pass_escaped
echo "TF_ENCRYPTION set — state and plan files for this root are encrypted."

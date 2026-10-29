#!/usr/bin/env bash
# shellcheck shell=bash
#
# Usage:  source terraform/hermes-vps/env.sh
#
# Exports what this root needs but must not read from the repository or through
# a plain data source:
#
#   TF_ENCRYPTION          state/plan encryption (passphrase from 1Password)
#   TF_VAR_ssh_public_key  the public key cloud-init installs for `hermes`
#
# The SSH *public* key is passed as a variable rather than read through the
# onepassword data source, because that data source persists every attribute of
# the item — private key included — into state. A public key is not a secret.
#
# Must be sourced (not executed): it sets environment variables in your shell.
# Not `set -e`: this file runs in the caller's shell and must not change its
# behaviour on an unrelated command failure.

# --- state encryption passphrase ------------------------------------------
_pass="$(op read 'op://Development/tofu-state/hermes-vps-passphrase')"
if [ -z "$_pass" ]; then
  echo "env.sh: empty passphrase from 1Password — is the op CLI signed in?" >&2
  unset _pass
  return 1 2>/dev/null || exit 1
fi

# The passphrase is embedded in an HCL string, so restrict it to an alphabet
# that needs no escaping at all. Refusing is safer than a partial escaper:
# `${`, `%{`, quotes, backslashes and newlines all have meaning in HCL.
case "$_pass" in
  *'${'* | *'%{'* | *'"'* | *'\'* | *'
'*)
    echo "env.sh: passphrase contains characters that cannot be embedded in HCL (\${, %{, quote, backslash, newline). Rotate it to base64/hex." >&2
    unset _pass
    return 1 2>/dev/null || exit 1
    ;;
esac
if [ "${#_pass}" -lt 16 ]; then
  echo "env.sh: passphrase shorter than 16 characters — rotate it." >&2
  unset _pass
  return 1 2>/dev/null || exit 1
fi

TF_ENCRYPTION="$(
  printf '%s\n' \
    'key_provider "pbkdf2" "state" {' \
    "  passphrase = \"${_pass}\"" \
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
unset _pass

# --- SSH public key --------------------------------------------------------
TF_VAR_ssh_public_key="$(op read 'op://Development/ssh-key/public key')"
if [ -z "$TF_VAR_ssh_public_key" ]; then
  echo "env.sh: could not read the SSH public key from 1Password." >&2
  return 1 2>/dev/null || exit 1
fi
export TF_VAR_ssh_public_key

echo "env.sh: TF_ENCRYPTION and TF_VAR_ssh_public_key set."

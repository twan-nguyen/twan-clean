#!/usr/bin/env bash
# One-time setup for .github/workflows/release.yml. It gives GitHub Actions what it needs to
# sign releases and update the Homebrew cask:
#   1. the "Twan Clean Self-Signed" identity, created here unless you pass the .p12 you
#      created it from, and also installed in this Mac's signing keychain so local builds
#      keep the same signature;
#   2. secrets SIGNING_CERT_P12_BASE64 and SIGNING_CERT_PASSWORD on the app repo;
#   3. a new deploy key with write access on the tap repo, whose private half becomes the
#      TAP_DEPLOY_KEY secret and is never kept on disk.
# Usage: scripts/setup-release-secrets.sh [identity.p12]
#        (an existing .p12 needs its password in TWANCLEAN_P12_PASSWORD)
set -euo pipefail

REPO="twan-nguyen/twan-clean"
TAP_REPO="twan-nguyen/homebrew-tap"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEYCHAIN="$HOME/Library/Keychains/twanclean-signing.keychain-db"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
chmod 700 "$workdir"

p12="${1:-}"
if [[ -n "$p12" ]]; then
  p12_password="${TWANCLEAN_P12_PASSWORD:?set TWANCLEAN_P12_PASSWORD to the password of $p12}"
else
  if [[ -e "$KEYCHAIN" ]]; then
    echo "error: $KEYCHAIN already holds an identity; pass the .p12 it was created from" >&2
    exit 1
  fi
  echo "==> Creating the signing identity"
  p12="$workdir/identity.p12"
  p12_password="$(openssl rand -hex 24)"
  TWANCLEAN_P12_PASSWORD="$p12_password" "$REPO_ROOT/scripts/create-signing-identity.sh" "$p12"
fi

if [[ ! -e "$KEYCHAIN" ]]; then
  echo "==> Installing it in this Mac's signing keychain"
  TWANCLEAN_P12_PASSWORD="$p12_password" "$REPO_ROOT/scripts/setup-signing-keychain.sh" "$p12"
fi

echo "==> Saving the signing secrets on $REPO"
base64 -i "$p12" | tr -d '\n' | gh secret set SIGNING_CERT_P12_BASE64 --repo "$REPO"
printf '%s' "$p12_password" | gh secret set SIGNING_CERT_PASSWORD --repo "$REPO"

echo "==> Adding a deploy key to $TAP_REPO"
ssh-keygen -q -t ed25519 -N "" -C "twan-clean release" -f "$workdir/tap_deploy_key"
gh repo deploy-key add "$workdir/tap_deploy_key.pub" --repo "$TAP_REPO" --allow-write --title "twan-clean release"
gh secret set TAP_DEPLOY_KEY --repo "$REPO" < "$workdir/tap_deploy_key"

echo "Done. Push a tag such as v0.1.0 to publish a release."

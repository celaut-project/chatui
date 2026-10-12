#!/usr/bin/env bash
# ─── sign_release.sh ──────────────────────────────────────────────────────
# Signs the unsigned APKs that the release workflow put on a draft release,
# checks them with release_check.sh, and replaces the unsigned assets with
# the signed ones. The release key stays on this machine.
#
#   scripts/sign_release.sh v0.1.0
#
# Run it from a checkout of the tag, so release_check.sh reads the same
# version as the build. The signing values come from .env (see example.env).
# The release stays a draft; the script prints the command that publishes it.
set -euo pipefail

TAG="${1:?usage: sign_release.sh <tag>}"
VERSION="${TAG#v}"
REPO=celaut-project/chatui
VARIANTS=(universal arm64-v8a x86_64)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -f "$REPO_ROOT/.env" ]; then
  set -a; . "$REPO_ROOT/.env"; set +a
fi
: "${ARGUS_KEYSTORE:?ARGUS_KEYSTORE is required (see example.env)}"
: "${ARGUS_KEYSTORE_PASSWORD:?ARGUS_KEYSTORE_PASSWORD is required}"
: "${ARGUS_KEY_ALIAS:?ARGUS_KEY_ALIAS is required}"
export ARGUS_KEYSTORE_PASSWORD
export ARGUS_KEY_PASSWORD="${ARGUS_KEY_PASSWORD:-$ARGUS_KEYSTORE_PASSWORD}"

head_tag="$(git -C "$REPO_ROOT" describe --tags --exact-match 2>/dev/null || true)"
[ "$head_tag" = "$TAG" ] || { echo "Check out $TAG first (HEAD is ${head_tag:-not a tag})."; exit 1; }

build_tools="$(ls -d "${ANDROID_HOME:-$HOME/Android/Sdk}"/build-tools/*/ 2>/dev/null | sort -V | tail -1)"
apksigner="${build_tools}apksigner"
[ -x "$apksigner" ] || apksigner="$(command -v apksigner)" || { echo "apksigner not found"; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir "$work/in" "$work/out"

gh release download "$TAG" --repo "$REPO" --dir "$work/in" \
  --pattern '*-unsigned.apk' --pattern 'SHA256SUMS-unsigned'
(cd "$work/in" && sha256sum --check SHA256SUMS-unsigned)

for v in "${VARIANTS[@]}"; do
  "$apksigner" sign \
    --ks "$ARGUS_KEYSTORE" --ks-key-alias "$ARGUS_KEY_ALIAS" \
    --ks-pass env:ARGUS_KEYSTORE_PASSWORD --key-pass env:ARGUS_KEY_PASSWORD \
    --out "$work/out/chatui-$VERSION-$v.apk" "$work/in/chatui-$VERSION-$v-unsigned.apk"
done
rm -f "$work"/out/*.idsig

"$SCRIPT_DIR/release_check.sh" apks "$work/out"
(cd "$work/out" && sha256sum *.apk > SHA256SUMS)

gh release upload "$TAG" --repo "$REPO" --clobber "$work"/out/*.apk "$work/out/SHA256SUMS"
for v in "${VARIANTS[@]}"; do
  gh release delete-asset "$TAG" "chatui-$VERSION-$v-unsigned.apk" --repo "$REPO" --yes
done
gh release delete-asset "$TAG" SHA256SUMS-unsigned --repo "$REPO" --yes

echo
echo "Signed assets are on the draft $TAG. Publish it with:"
echo "  gh release edit $TAG --repo $REPO --draft=false --prerelease"

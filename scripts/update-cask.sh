#!/bin/zsh
# Actualiza el cask en el tap de Homebrew con una nueva versión.
#
#   scripts/update-cask.sh <versión> <sha256>
#
# En CI usa TAP_TOKEN (un token con permiso de escritura en Crisdotcom/homebrew-tap).
# En local, si TAP_DIR apunta a un clon del tap, edita ese clon (sin hacer push).
set -euo pipefail

VERSION="${1:?versión requerida}"
SHA="${2:?sha256 requerido}"
TAP_REPO="Crisdotcom/homebrew-tap"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -n "${TAP_DIR:-}" ]]; then
    DIR="$TAP_DIR"
    PUSH=0
else
    : "${TAP_TOKEN:?define TAP_TOKEN o TAP_DIR}"
    DIR="$(mktemp -d)"
    git clone --depth 1 "https://x-access-token:${TAP_TOKEN}@github.com/${TAP_REPO}.git" "$DIR"
    PUSH=1
fi

mkdir -p "$DIR/Casks"
CASK="$DIR/Casks/cmddock.rb"
cp "$ROOT/packaging/homebrew/cmddock.rb" "$CASK"
sed -i '' -E "s/^  version \".*\"/  version \"${VERSION}\"/" "$CASK"
sed -i '' -E "s/^  sha256 \".*\"/  sha256 \"${SHA}\"/" "$CASK"
echo "✓ $CASK → $VERSION"

if [[ "$PUSH" == "1" ]]; then
    cd "$DIR"
    git config user.name "github-actions[bot]"
    git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
    git add Casks/cmddock.rb
    git commit -m "cmddock ${VERSION}"
    git push
fi

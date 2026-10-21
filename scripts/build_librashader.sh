#!/bin/bash
# Rebuild the bundled librashader dylib with the TruchiEmu Metal patches.
#
# The bundled runtime is plain upstream librashader plus
# scripts/patches/librashader-mtl-final-scale.patch:
#   1. Final-pass feedback intermediates render into their own FBO extent
#      (identity MVP + Offscreen quad) instead of the host viewport, which
#      otherwise trips Metal "Set Scissor Rect Validation".
#   2. An explicitly scaled final pass reports its declared size in the
#      OutputSize semantic, matching RetroArch's composite-then-upscale path.
#
# Usage:
#   scripts/build_librashader.sh
#
# Override the source checkout with LIBRASHADER_SRC=/path/to/librashader.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIBRASHADER_COMMIT="cde6ad63b034dba0621b6a69d3654a79fe34a058"
SRC_DIR="${LIBRASHADER_SRC:-$REPO_ROOT/build/librashader-src}"
PATCH_FILE="$REPO_ROOT/scripts/patches/librashader-mtl-final-scale.patch"
LIB_DIR="$REPO_ROOT/TruchiEmu/lib"

if [ ! -f "$PATCH_FILE" ]; then
  echo "Patch not found: $PATCH_FILE" >&2
  exit 2
fi

if [ ! -d "$SRC_DIR/.git" ]; then
  echo "Cloning librashader into $SRC_DIR"
  mkdir -p "$(dirname "$SRC_DIR")"
  git clone https://github.com/SnowflakePowered/librashader.git "$SRC_DIR"
fi

echo "Checking out $LIBRASHADER_COMMIT"
git -C "$SRC_DIR" fetch --tags origin
git -C "$SRC_DIR" checkout --force "$LIBRASHADER_COMMIT"
git -C "$SRC_DIR" reset --hard "$LIBRASHADER_COMMIT"

echo "Applying $PATCH_FILE"
git -C "$SRC_DIR" apply "$PATCH_FILE"

echo "Building librashader-capi (release)"
cargo build --release --locked -p librashader-capi --manifest-path "$SRC_DIR/Cargo.toml"

ARTIFACT="$SRC_DIR/target/release/liblibrashader_capi.dylib"
if [ ! -f "$ARTIFACT" ]; then
  echo "Build artifact not found: $ARTIFACT" >&2
  exit 3
fi

for name in liblibrashader_capi.dylib librashader.dylib; do
  dest="$LIB_DIR/$name"
  cp -f "$ARTIFACT" "$dest"
  install_name_tool -id @rpath/librashader.dylib "$dest"
  codesign --force --sign - "$dest"
done

echo "Installed patched librashader into $LIB_DIR"

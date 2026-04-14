#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/pkg"
DIST_DIR="$ROOT_DIR/dist"
PKG_ROOT="$BUILD_DIR/root"
VERSION="${VERSION:-0.1.0}"
PKG_NAME="HermesDataEyesInstaller-${VERSION}.pkg"

rm -rf "$BUILD_DIR"
mkdir -p "$PKG_ROOT/usr/local/hermes-dataeyes-installer" "$PKG_ROOT/usr/local/bin" "$DIST_DIR"

cp "$ROOT_DIR/install.sh" "$PKG_ROOT/usr/local/hermes-dataeyes-installer/install.sh"
mkdir -p "$PKG_ROOT/usr/local/hermes-dataeyes-installer/scripts"
cp "$ROOT_DIR/scripts/configure_dataeyes.py" "$PKG_ROOT/usr/local/hermes-dataeyes-installer/scripts/configure_dataeyes.py"

cat > "$PKG_ROOT/usr/local/bin/hermes-dataeyes-install" <<'EOF'
#!/bin/bash
set -euo pipefail
/bin/bash /usr/local/hermes-dataeyes-installer/install.sh "$@"
EOF

chmod +x \
  "$PKG_ROOT/usr/local/hermes-dataeyes-installer/install.sh" \
  "$PKG_ROOT/usr/local/bin/hermes-dataeyes-install"

pkgbuild \
  --root "$PKG_ROOT" \
  --identifier "ai.hermes.dataeyes.installer" \
  --version "$VERSION" \
  "$DIST_DIR/$PKG_NAME"

echo "已生成: $DIST_DIR/$PKG_NAME"

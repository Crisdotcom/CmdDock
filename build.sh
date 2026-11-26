#!/bin/zsh
# Compila CmdDock y genera CmdDock.app.
#
#   ./build.sh            → build/CmdDock.app
#   ./build.sh install    → además lo copia a /Applications y lo abre
#   ./build.sh zip        → además crea build/CmdDock-<versión>.zip (para releases)
#
# Variables:
#   VERSION=1.2.0         versión (por defecto: último tag git, o 0.0.0-dev)
#   UNIVERSAL=1           binario universal arm64 + x86_64
#   SIGN_IDENTITY="-"     firma ad-hoc (por defecto usa un certificado de desarrollo si
#                         existe, para que el permiso de Accesibilidad sobreviva a recompilar)
set -euo pipefail
cd "$(dirname "$0")"

BUNDLE_ID="io.github.crisdotcom.CmdDock"
VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.0.0-dev}"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

ARCH_FLAGS=()
[[ "${UNIVERSAL:-0}" == "1" ]] && ARCH_FLAGS=(--arch arm64 --arch x86_64)

swift build -c release "${ARCH_FLAGS[@]}"
BIN="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)/CmdDock"

APP="build/CmdDock.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/CmdDock"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>CmdDock</string>
    <key>CFBundleDisplayName</key><string>CmdDock</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>CmdDock</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>MIT License</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>CmdDock envía tus comandos a la terminal que elijas (Warp, Terminal, iTerm2…).</string>
</dict>
</plist>
PLIST

if [[ -f icon/AppIcon.icns ]]; then cp icon/AppIcon.icns "$APP/Contents/Resources/"; fi

xattr -cr "$APP" # codesign rechaza atributos de Finder/iCloud ("detritus not allowed")
if [[ -n "${CI:-}" ]]; then
    IDENTITY="${SIGN_IDENTITY:--}"
else
    IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Developer ID/ {print $2; exit}')}"
fi
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "✓ $APP ($VERSION)"

case "${1:-}" in
    install)
        pkill -x CmdDock 2>/dev/null || true
        rm -rf /Applications/CmdDock.app
        cp -R "$APP" /Applications/
        open /Applications/CmdDock.app
        echo "✓ Instalado en /Applications"
        ;;
    zip)
        ZIP="build/CmdDock-${VERSION}.zip"
        rm -f "$ZIP"
        ditto -c -k --keepParent "$APP" "$ZIP"
        echo "✓ $ZIP"
        shasum -a 256 "$ZIP"
        ;;
esac

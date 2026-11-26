#!/bin/zsh
# Compila CmdDock y genera CmdDock.app. Uso:
#   ./build.sh            → build/CmdDock.app
#   ./build.sh install    → además lo copia a /Applications y lo abre
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/CmdDock"

APP="build/CmdDock.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/CmdDock"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>CmdDock</string>
    <key>CFBundleDisplayName</key><string>CmdDock</string>
    <key>CFBundleIdentifier</key><string>local.cmddock.app</string>
    <key>CFBundleExecutable</key><string>CmdDock</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>CmdDock envía tus comandos a la terminal que elijas (Warp, Terminal, iTerm2…).</string>
</dict>
</plist>
PLIST

# Icono generado a partir del símbolo "terminal"
if [[ -f icon/AppIcon.icns ]]; then cp icon/AppIcon.icns "$APP/Contents/Resources/"; fi

# Firma: usa un certificado de desarrollo si hay uno (así el permiso de
# Accesibilidad sobrevive a las recompilaciones); si no, firma ad-hoc.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Developer ID/ {print $2; exit}')}"
if [[ -n "$IDENTITY" ]]; then
    codesign --force --sign "$IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"
fi
echo "✓ $APP"

if [[ "${1:-}" == "install" ]]; then
    pkill -x CmdDock 2>/dev/null || true
    rm -rf /Applications/CmdDock.app
    cp -R "$APP" /Applications/
    open /Applications/CmdDock.app
    echo "✓ Instalado en /Applications"
fi

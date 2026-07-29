#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$AGENT_DIR/dist"
APP_DIR="$DIST_DIR/Magenta Adobe Agent.app"
ZIP_PATH="$DIST_DIR/Magenta-Adobe-Agent.zip"

mkdir -p "$DIST_DIR"
if [[ -d "$APP_DIR" ]]; then
  mv "$APP_DIR" "$DIST_DIR/Magenta Adobe Agent.previous.$(date +%s).app"
fi
if [[ -f "$ZIP_PATH" ]]; then
  mv "$ZIP_PATH" "$DIST_DIR/Magenta-Adobe-Agent.previous.$(date +%s).zip"
fi

osacompile -o "$APP_DIR" "$SCRIPT_DIR/Configurator.applescript"
cp "$AGENT_DIR/adobe_agent.py" "$APP_DIR/Contents/Resources/adobe_agent.py"
chmod 755 "$APP_DIR/Contents/Resources/adobe_agent.py"

codesign --force --deep --sign - "$APP_DIR"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
echo "$ZIP_PATH"

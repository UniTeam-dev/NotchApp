#!/bin/bash
# Сборка NotchApp.app из SwiftPM-таргета.
#
#   ./scripts/build.sh          — release
#   ./scripts/build.sh debug    — debug
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/dist/NotchApp.app"
CERT_NAME="${NOTCHAPP_CERT:-NotchApp Dev}"

cd "$ROOT"

# Запущенный экземпляр держит бинарь и мешает подписи.
pkill -x NotchApp 2>/dev/null || true

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/NotchApp"
if [ ! -f "$BIN" ]; then
  echo "не нашёл собранный бинарь: $BIN" >&2
  exit 1
fi

echo "==> собираю бандл"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NotchApp"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Подпись стабильной идентичностью.
#
# macOS привязывает TCC-гранты к code identity. У ad-hoc подписи стабильной
# identity нет, поэтому после каждой пересборки разрешения сбрасывались бы.
# Стабильного bundle ID для этого недостаточно.
if security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
  echo "==> подписываю как «$CERT_NAME»"
  codesign --force --options runtime \
    --entitlements "$ROOT/Resources/NotchApp.entitlements" \
    --sign "$CERT_NAME" "$APP"
else
  echo "!! сертификат «$CERT_NAME» не найден — подписываю ad-hoc."
  echo "!! Выданные разрешения будут слетать при каждой пересборке."
  echo "!! Лечится: ./scripts/make-cert.sh"
  codesign --force --sign - "$APP"
fi

codesign -dv --verbose=2 "$APP" 2>&1 | sed 's/^/    /'
echo "==> готово: $APP"

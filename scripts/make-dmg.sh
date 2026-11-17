#!/bin/bash
# Собирает dist/NotchApp.dmg — образ с приложением, ярлыком /Applications
# и запиской для того, кому образ отдают.
#
# Установщика в привычном смысле (.pkg с мастером) у утилиты нет и не нужно:
# приложение самодостаточно, ставится перетаскиванием.
#
# Образ подписывается Developer ID и нотаризуется, если в связке ключей есть
# профиль notarytool (по умолчанию «notchapp», другое имя — NOTCHAPP_NOTARY_PROFILE):
#   xcrun notarytool store-credentials notchapp --team-id <TEAM>
# Без нотаризации Gatekeeper на чужой машине заблокирует запуск.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${ROOT}/dist/NotchApp.app"
DMG="${ROOT}/dist/NotchApp.dmg"
README="${ROOT}/Resources/dmg-readme.txt"

cd "${ROOT}"

# Собираем, если приложения нет или оно старше исходников. Отдать коллеге
# вчерашний бинарь, думая, что отдал сегодняшний, — самая обидная из ошибок:
# она не видна ни в одном логе.
NEEDS_BUILD=0
if [ ! -d "${APP}" ]; then
  NEEDS_BUILD=1
else
  BIN="${APP}/Contents/MacOS/NotchApp"
  if [ -n "$(find Sources Resources Package.swift -newer "${BIN}" 2>/dev/null | head -1)" ]; then
    echo "==> исходники новее собранного приложения — пересобираю"
    NEEDS_BUILD=1
  fi
fi

if [ "${NEEDS_BUILD}" -eq 1 ]; then
  "${ROOT}/scripts/build.sh"
fi

echo "==> подпись приложения"
codesign --verify --deep --strict --verbose=2 "${APP}" 2>&1 | sed 's/^/    /'

STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT

cp -R "${APP}" "${STAGE}/NotchApp.app"
ln -s /Applications "${STAGE}/Applications"
if [ -f "${README}" ]; then
  cp "${README}" "${STAGE}/Прочтите меня.txt"
fi

# Карантин на файлах внутри образа только запутает получателя: его всё равно
# поставит браузер при скачивании, а лишний слой мешает разбираться.
xattr -dr com.apple.quarantine "${STAGE}/NotchApp.app" 2>/dev/null || true

# Для раздачи переподписываем копию Developer ID. dist/NotchApp.app остаётся
# с локальной подписью: смена identity сбросила бы выданные TCC-разрешения.
DIST_CERT="${NOTCHAPP_DIST_CERT:-$(security find-identity -v -p codesigning \
  | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)}"
if [ -n "${DIST_CERT}" ]; then
  echo "==> переподписываю копию как «${DIST_CERT}»"
  codesign --force --options runtime --timestamp \
    --entitlements "${ROOT}/Resources/NotchApp.entitlements" \
    --sign "${DIST_CERT}" "${STAGE}/NotchApp.app"
else
  echo "!! Developer ID не найден — в образе останется локальная подпись."
fi

rm -f "${DMG}"
hdiutil create \
  -volname "NotchApp" \
  -srcfolder "${STAGE}" \
  -ov -format UDZO \
  "${DMG}" >/dev/null

if [ -n "${DIST_CERT}" ]; then
  codesign --force --timestamp --sign "${DIST_CERT}" "${DMG}"

  PROFILE="${NOTCHAPP_NOTARY_PROFILE:-notchapp}"
  echo "==> нотаризация (профиль «${PROFILE}»), обычно несколько минут"
  if xcrun notarytool submit "${DMG}" --keychain-profile "${PROFILE}" --wait 2>&1 \
       | tee /dev/stderr | grep "status: Accepted" >/dev/null; then
    xcrun stapler staple "${DMG}" >/dev/null
  else
    echo "!! образ НЕ нотаризован: нет профиля «${PROFILE}» или Apple отклонила отправку."
    exit 1
  fi
fi

echo "==> готово: ${DMG}  ($(du -h "${DMG}" | cut -f1))"

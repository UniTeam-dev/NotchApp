#!/bin/bash
# Самоподписанный сертификат для подписи NotchApp.
#
# Зачем: macOS привязывает выданные разрешения (Automation, Accessibility)
# к code identity. У ad-hoc подписи стабильной identity нет, поэтому после
# каждой пересборки разрешения сбрасываются. Постоянный Common Name это чинит.
#
# Сертификат создаётся один раз. Не пересоздавайте его без нужды: смена
# Common Name = другое приложение с точки зрения TCC, разрешения придётся
# выдавать заново.
set -euo pipefail

CERT_NAME="${NOTCHAPP_CERT:-NotchApp Dev}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
  echo "Сертификат «$CERT_NAME» уже есть — ничего не делаю."
  exit 0
fi

cat > "$WORK/cert.conf" <<CONF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no

[ dn ]
CN = $CERT_NAME

[ ext ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CONF

echo "==> генерирую ключ и сертификат"
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
  -days 3650 -config "$WORK/cert.conf" >/dev/null 2>&1

openssl pkcs12 -export -legacy \
  -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -out "$WORK/bundle.p12" -passout pass: >/dev/null 2>&1 \
  || openssl pkcs12 -export \
       -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
       -out "$WORK/bundle.p12" -passout pass: >/dev/null 2>&1

echo "==> кладу в связку ключей (может спросить пароль от входа)"
security import "$WORK/bundle.p12" -k ~/Library/Keychains/login.keychain-db \
  -P "" -T /usr/bin/codesign -T /usr/bin/security

echo "==> помечаю как доверенный для подписи кода"
sudo security add-trusted-cert -d -r trustRoot \
  -p codeSign -k /Library/Keychains/System.keychain "$WORK/cert.pem"

echo
echo "Готово. Проверка:"
security find-identity -v -p codesigning | sed 's/^/    /'

#!/usr/bin/env bash
# ExP 89 - Entorno A (administracion de la CA): revisa la CSR recibida y emite servidor.crt.
#
# Uso:      scripts/pki-emitir.sh        (pide la contrasena de ca.key de forma interactiva)
# Opcional: CA_DIR (por defecto ~/ca_root-pki/ca), DOMINIO (por defecto portal.proyecto.test),
#           CA_PASS_FILE solo para automatizar (fichero 600 FUERA del repositorio)
# Requiere solicitudes/servidor.csr en CA_DIR. Se niega a firmar si el SAN no es el nombre autorizado.
set -euo pipefail
umask 077

CA_DIR="${CA_DIR:-$HOME/ca_root-pki/ca}"
DOMINIO="${DOMINIO:-portal.proyecto.test}"
cd "$CA_DIR"

[ -f solicitudes/servidor.csr ] || { echo "ERROR: falta solicitudes/servidor.csr" >&2; exit 1; }

echo "--- Revision de la CSR"
openssl req -in solicitudes/servidor.csr -noout -verify
if ! openssl req -in solicitudes/servidor.csr -noout -text | grep -q "DNS:${DOMINIO}"; then
  echo "ERROR: la CSR no incluye el SAN DNS:${DOMINIO}; no se firma." >&2
  exit 1
fi

cat > servidor.ext <<EOF
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:${DOMINIO}
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
EOF

PASSIN=()
[ -n "${CA_PASS_FILE:-}" ] && PASSIN=(-passin "file:$CA_PASS_FILE")

openssl x509 -req -in solicitudes/servidor.csr -CA ca.crt -CAkey private/ca.key "${PASSIN[@]}" \
  -CAcreateserial -out emitidos/servidor.crt -days 365 -sha256 -extfile servidor.ext
chmod 644 emitidos/servidor.crt

echo "--- Certificado emitido"
openssl x509 -in emitidos/servidor.crt -noout -subject -issuer -dates
openssl verify -CAfile ca.crt emitidos/servidor.crt
echo "Siguiente paso: llevar al servidor (Entorno B) SOLO emitidos/servidor.crt y ca.crt (a ~/mf0489/). Nunca ca.key."

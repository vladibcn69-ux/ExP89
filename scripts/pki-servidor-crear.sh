#!/usr/bin/env bash
# ExP 89 - Entorno B (Ubuntu Server): genera la clave privada TEMPORAL del servidor y su CSR.
#
# Uso:      scripts/pki-servidor-crear.sh
# Opcional: DOMINIO (por defecto portal.proyecto.test), MF_DIR (por defecto ~/mf0489)
# La clave privada (servidor.key) NO sale nunca del servidor; solo se envia servidor.csr a la CA.
set -euo pipefail
umask 077

DOMINIO="${DOMINIO:-portal.proyecto.test}"
MF_DIR="${MF_DIR:-$HOME/mf0489}"

mkdir -p "$MF_DIR"
cd "$MF_DIR"
if [ -e servidor.key ]; then
  echo "ERROR: $MF_DIR/servidor.key ya existe; no se sobrescribe." >&2
  exit 1
fi

openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out servidor.key
chmod 600 servidor.key
openssl pkey -in servidor.key -check -noout                    # comprueba la clave sin mostrarla

openssl req -new -sha256 -key servidor.key -out servidor.csr \
  -subj "/CN=${DOMINIO}" -addext "subjectAltName=DNS:${DOMINIO}"
openssl req -in servidor.csr -noout -verify

echo "--- CSR creada: $MF_DIR/servidor.csr (SAN DNS:${DOMINIO})"
echo "Siguiente paso: enviar SOLO servidor.csr al Entorno A (directorio solicitudes/ de la CA). Nunca la clave."

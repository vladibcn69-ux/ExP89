#!/usr/bin/env bash
# ExP 89 - Entorno B (Ubuntu Server): instala el material PKI en sus rutas definitivas y lo verifica.
#
# Uso:      sudo scripts/pki-instalar.sh
# Requiere en MF_DIR (por defecto ~/mf0489 del usuario que invoca sudo): servidor.crt y ca.crt, y
#           servidor.key si aun no esta instalada. Tras verificar, elimina la copia temporal de la clave.
# Opcional: DOMINIO, MF_DIR, SSL_DIR (por defecto /etc/ssl), OWN_U / OWN_G (propietario, por defecto root)
set -euo pipefail

DOMINIO="${DOMINIO:-portal.proyecto.test}"
SSL_DIR="${SSL_DIR:-/etc/ssl}"
OWN_U="${OWN_U:-root}"; OWN_G="${OWN_G:-root}"
if [ -z "${MF_DIR:-}" ]; then
  REAL_HOME="$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)"
  MF_DIR="$REAL_HOME/mf0489"
fi

[ -f "$MF_DIR/servidor.crt" ] && [ -f "$MF_DIR/ca.crt" ] || { echo "ERROR: faltan servidor.crt y/o ca.crt en $MF_DIR" >&2; exit 1; }

mkdir -p "$SSL_DIR/mf0489" "$SSL_DIR/private" "$SSL_DIR/certs"
if [ -f "$MF_DIR/servidor.key" ]; then
  install -o "$OWN_U" -g "$OWN_G" -m 600 "$MF_DIR/servidor.key" "$SSL_DIR/private/servidor.key"
fi
[ -f "$SSL_DIR/private/servidor.key" ] || { echo "ERROR: no hay servidor.key ni en $MF_DIR ni en $SSL_DIR/private" >&2; exit 1; }
install -o "$OWN_U" -g "$OWN_G" -m 644 "$MF_DIR/servidor.crt" "$SSL_DIR/certs/servidor.crt"
install -o "$OWN_U" -g "$OWN_G" -m 644 "$MF_DIR/ca.crt" "$SSL_DIR/mf0489/ca.crt"

echo "--- Rutas y permisos (la clave no se muestra)"
ls -l "$SSL_DIR/private/servidor.key" "$SSL_DIR/certs/servidor.crt" "$SSL_DIR/mf0489/ca.crt"

echo "--- Verificacion SIN confiar en la CA (debe FALLAR: unable to get local issuer certificate)"
openssl verify -purpose sslserver -verify_hostname "$DOMINIO" "$SSL_DIR/certs/servidor.crt" || true

echo "--- Verificacion con la CA del laboratorio (debe dar OK)"
openssl verify -CAfile "$SSL_DIR/mf0489/ca.crt" -purpose sslserver -verify_hostname "$DOMINIO" "$SSL_DIR/certs/servidor.crt"

echo "--- Nombre incorrecto (debe FALLAR: hostname mismatch)"
if openssl verify -CAfile "$SSL_DIR/mf0489/ca.crt" -purpose sslserver -verify_hostname "servidor-equivocado.test" "$SSL_DIR/certs/servidor.crt" >/dev/null 2>&1; then
  echo "ERROR: el certificado valida un nombre incorrecto" >&2; exit 1
else
  echo "OK: rechazado, como se esperaba"
fi

echo "--- Vigencia"
openssl x509 -in "$SSL_DIR/certs/servidor.crt" -noout -dates
openssl x509 -in "$SSL_DIR/certs/servidor.crt" -noout -checkend 0

echo "--- Correspondencia clave privada / certificado (SHA-256 de la clave publica)"
K="$(openssl pkey -in "$SSL_DIR/private/servidor.key" -pubout -outform DER | openssl dgst -sha256)"
C="$(openssl x509 -in "$SSL_DIR/certs/servidor.crt" -pubkey -noout | openssl pkey -pubin -outform DER | openssl dgst -sha256)"
if [ "$K" = "$C" ]; then echo "OK: coinciden"; else echo "ERROR: la clave y el certificado NO corresponden" >&2; exit 1; fi

if [ -f "$MF_DIR/servidor.key" ]; then
  rm -f "$MF_DIR/servidor.key"
  echo "--- Copia temporal de la clave eliminada de $MF_DIR (se conserva servidor.csr como evidencia)"
fi

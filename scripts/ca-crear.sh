#!/usr/bin/env bash
# ExP 89 - Entorno A (administracion de la CA): crea la CA de laboratorio.
# Genera private/ca.key (RSA 4096, cifrada con AES-256, permisos 600) y ca.crt (autofirmado, 10 anos).
#
# Uso:     scripts/ca-crear.sh        (pide la contrasena de ca.key de forma interactiva)
# Opcional: CA_DIR       directorio de la CA (por defecto ~/ca_root-pki/ca)
#           CA_SUBJ      subject del certificado raiz
#           CA_PASS_FILE solo para automatizar: fichero con la contrasena, permisos 600 y FUERA del repositorio
# Ejecutar SOLO en el Entorno A. ca.key no debe copiarse nunca al servidor ni al repositorio.
set -euo pipefail
umask 077

CA_DIR="${CA_DIR:-$HOME/ca_root-pki/ca}"
CA_SUBJ="${CA_SUBJ:-/C=ES/O=Proyecto ExP89 Lab/CN=ExP89 Lab Root CA}"

mkdir -p "$CA_DIR"/{private,solicitudes,emitidos}
cd "$CA_DIR"
if [ -e private/ca.key ]; then
  echo "ERROR: private/ca.key ya existe en $CA_DIR; no se sobrescribe." >&2
  exit 1
fi

PASS=(); PASSIN=()
if [ -n "${CA_PASS_FILE:-}" ]; then
  PASS=(-pass "file:$CA_PASS_FILE"); PASSIN=(-passin "file:$CA_PASS_FILE")
fi

openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -aes-256-cbc "${PASS[@]}" -out private/ca.key
chmod 600 private/ca.key
openssl pkey -in private/ca.key "${PASSIN[@]}" -check -noout   # comprueba la clave sin mostrarla

openssl req -x509 -new -sha256 -days 3650 -key private/ca.key "${PASSIN[@]}" -out ca.crt \
  -subj "$CA_SUBJ" \
  -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" \
  -addext "subjectKeyIdentifier=hash"
chmod 644 ca.crt

echo "--- Certificado raiz creado en $CA_DIR/ca.crt"
openssl x509 -in ca.crt -noout -subject -issuer -dates
openssl verify -CAfile ca.crt ca.crt

#!/usr/bin/env bash
# ExP 89 - Cliente de pruebas (Entorno A o cualquier equipo con ca.crt): verifica HTTPS y la redireccion.
# Nunca usa curl -k: la confianza se valida siempre con la CA del laboratorio.
#
# Uso:      IP_SERVIDOR=192.168.1.109 CA_CERT=./ca.crt scripts/verificar-https.sh
# Opcional: DOMINIO (por defecto portal.proyecto.test)
# No hace falta tocar /etc/hosts: se usa curl --resolve y openssl s_client -connect IP.
set -uo pipefail

DOMINIO="${DOMINIO:-portal.proyecto.test}"
IP_SERVIDOR="${IP_SERVIDOR:?define IP_SERVIDOR (IP del Ubuntu Server)}"
CA_CERT="${CA_CERT:-./ca.crt}"
[ -f "$CA_CERT" ] || { echo "ERROR: no existe $CA_CERT (solo se necesita el certificado PUBLICO de la CA)" >&2; exit 1; }
FALLOS=0
ok()   { echo "[ OK ] $*"; }
fallo(){ echo "[FALLO] $*"; FALLOS=$((FALLOS+1)); }

echo "== 1. Redireccion HTTP -> HTTPS (host y ruta conservados)"
CAB="$(curl -sI --resolve "${DOMINIO}:80:${IP_SERVIDOR}" "http://${DOMINIO}/prueba?x=1")"
echo "$CAB" | grep -iE "^HTTP|^location"
echo "$CAB" | head -1 | grep -qE " 30[18] " && echo "$CAB" | grep -qi "^location: https://${DOMINIO}/prueba?x=1" \
  && ok "redireccion 301/308 con Location https y ruta conservada" || fallo "redireccion HTTP -> HTTPS"

echo "== 2. HTTPS con curl --cacert (sin -k)"
SALIDA="$(curl -s --cacert "$CA_CERT" --resolve "${DOMINIO}:443:${IP_SERVIDOR}" "https://${DOMINIO}/" -o /dev/null -w "HTTP=%{http_code} verify=%{ssl_verify_result}")"
echo "$SALIDA"
case "$SALIDA" in "HTTP=200 verify=0"|"HTTP=302 verify=0") ok "HTTPS verificado (certificado, nombre y cadena)";; *) fallo "curl --cacert";; esac

echo "== 3. openssl s_client (version TLS, cipher y verificacion)"
R="$(openssl s_client -connect "${IP_SERVIDOR}:443" -servername "$DOMINIO" -CAfile "$CA_CERT" -verify_hostname "$DOMINIO" -verify_return_error -brief </dev/null 2>&1)"
echo "$R" | grep -E "Protocol version|Ciphersuite|Verification|Verified peername"
echo "$R" | grep -q "Verification: OK" && ok "s_client: verificacion correcta" || fallo "s_client"

echo "== 4. Versiones de TLS"
for v in tls1_2 tls1_3; do
  R="$(openssl s_client -connect "${IP_SERVIDOR}:443" -servername "$DOMINIO" -CAfile "$CA_CERT" -"$v" -brief </dev/null 2>&1)"
  echo "$R" | grep -q "Verification: OK" && ok "$v aceptado" || fallo "$v no aceptado"
done
# El cliente se baja a SECLEVEL=0 para que el rechazo sea del SERVIDOR y no una politica local de OpenSSL
for v in tls1 tls1_1; do
  R="$(openssl s_client -connect "${IP_SERVIDOR}:443" -servername "$DOMINIO" -"$v" -cipher 'ALL:@SECLEVEL=0' -brief </dev/null 2>&1)"
  echo "$R" | grep -q "alert protocol version" && ok "$v rechazado por el servidor (alert protocol_version)" || fallo "$v no fue rechazado por el servidor"
done

echo "== 5. Puertos que no deben estar abiertos desde el cliente"
for p in 3306 8080; do (timeout 3 bash -c "</dev/tcp/${IP_SERVIDOR}/$p" 2>/dev/null) && fallo "puerto $p abierto" || ok "puerto $p cerrado"; done

echo
[ "$FALLOS" -eq 0 ] && { echo "RESULTADO: todo correcto"; exit 0; } || { echo "RESULTADO: $FALLOS comprobacion(es) fallida(s)"; exit 1; }

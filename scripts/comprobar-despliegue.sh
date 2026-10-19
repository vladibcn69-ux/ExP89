#!/usr/bin/env bash
# ExP 89 - Entorno B (Ubuntu Server): comprobacion del despliegue. Solo lectura.
#
# Uso:      sudo scripts/comprobar-despliegue.sh        (sudo para ver la clave privada y leer .env)
# Opcional: EXP89_DIR (por defecto ~/exp89 del usuario que invoca sudo)
# No imprime variables de entorno ni el contenido de claves.
set -uo pipefail

if [ -z "${EXP89_DIR:-}" ]; then
  REAL_HOME="$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)"
  EXP89_DIR="$REAL_HOME/exp89"
fi
cd "$EXP89_DIR" || { echo "ERROR: no existe $EXP89_DIR" >&2; exit 1; }
FALLOS=0
ok()   { echo "[ OK ] $*"; }
fallo(){ echo "[FALLO] $*"; FALLOS=$((FALLOS+1)); }

echo "== Contenedores"
docker compose ps
for c in exp89-nginx exp89-wordpress exp89-mariadb; do
  [ "$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)" = "true" ] && ok "$c en ejecucion" || fallo "$c no esta en ejecucion"
done

echo "== Compose y Nginx"
docker compose config --quiet && ok "docker compose config --quiet" || fallo "docker compose config"
docker compose exec -T reverse-proxy nginx -t </dev/null && ok "nginx -t" || fallo "nginx -t"

echo "== Puertos publicados (solo deben escuchar 22, 80 y 443)"
ss -ltn | grep -E "State|:22 |:80 |:443 |:3306|:8080"
ss -ltn | grep -qE ":(3306|8080) " && fallo "3306 u 8080 estan escuchando en el host" || ok "BBDD y 8080 no expuestos"

echo "== Material PKI (rutas y permisos)"
ls -l /etc/ssl/private/servidor.key /etc/ssl/certs/servidor.crt /etc/ssl/mf0489/ca.crt
[ "$(stat -c %a /etc/ssl/private/servidor.key 2>/dev/null)" = "600" ] && ok "servidor.key con permisos 600" || fallo "permisos de servidor.key"
openssl verify -CAfile /etc/ssl/mf0489/ca.crt -purpose sslserver -verify_hostname "${DOMINIO:-portal.proyecto.test}" /etc/ssl/certs/servidor.crt \
  && ok "certificado verificado con la CA del laboratorio" || fallo "verificacion del certificado"
[ -e "$(find / -xdev -name ca.key 2>/dev/null | head -1)" ] && fallo "existe un ca.key en este servidor" || ok "no hay ca.key en el servidor"

echo "== Suricata"
systemctl is-active --quiet suricata && ok "suricata activo" || fallo "suricata no esta activo"

echo
[ "$FALLOS" -eq 0 ] && { echo "RESULTADO: todo correcto"; exit 0; } || { echo "RESULTADO: $FALLOS comprobacion(es) fallida(s)"; exit 1; }

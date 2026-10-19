# ExP 89 · Guía de despliegue (desde cero, sin secretos)

**Autor:** Volodymyr Osebchuk (vladibcn69@gmail.com)
**Objetivo:** que otra persona pueda reproducir `https://portal.proyecto.test` con una CA de laboratorio, Nginx reverse proxy y Docker Compose, y monitorizarlo con Suricata, **sin disponer de ninguna clave privada ni contraseña del autor**: todas las claves y contraseñas se generan de nuevo en cada despliegue.

## 0. Requisitos y variables

| Entorno | Qué es | Requisitos |
|---|---|---|
| **A — CA** | WSL2 Ubuntu u otro Linux que **no** sea la VM que se exportará como CTF | `openssl` ≥ 3, `bash`, `curl`; copia de este repositorio |
| **B — Servidor** | Ubuntu Server (VM) con IP alcanzable desde A | `openssl`, Docker y Docker Compose v2, Suricata (§7), copia de este repositorio |

```bash
export DOMINIO=portal.proyecto.test        # el MISMO nombre en CSR, SAN, certificado, Nginx y pruebas
export IP_SERVIDOR=192.168.1.109           # IP real del Ubuntu Server
git clone https://github.com/vladibcn69-ux/ExP89.git && cd ExP89   # en A y en B
```

**Reglas de oro:** `ca.key` vive solo en A (cifrada, 600) y `servidor.key` solo en B (`/etc/ssl/private`, 600). Entre entornos solo viajan ficheros públicos (`.csr`, `.crt`). El `.env` real y las claves no se versionan (`.gitignore`).

## 1. Entorno A — crear la CA

```bash
scripts/ca-crear.sh      # pide la contraseña de ca.key (elíjala y guárdela fuera del repositorio)
```
Crea `~/ca_root-pki/ca/{private,solicitudes,emitidos}`, `private/ca.key` (RSA 4096, AES-256, 600) y `ca.crt` (autofirmado, `CA:TRUE, pathlen:0`, 10 años) y lo verifica con `openssl verify -CAfile ca.crt ca.crt` (resultado `OK`).

## 2. Entorno B — clave del servidor y CSR

```bash
scripts/pki-servidor-crear.sh      # crea ~/mf0489/servidor.key (RSA 3072, 600) y servidor.csr con SAN DNS:$DOMINIO
scp ~/mf0489/servidor.csr usuario_ca@IP_CA:~/ca_root-pki/ca/solicitudes/    # SOLO la CSR, nunca la clave
```

## 3. Entorno A — revisar y emitir el certificado

```bash
scripts/pki-emitir.sh              # verifica la CSR y el SAN, crea servidor.ext y firma 365 días
scp ~/ca_root-pki/ca/emitidos/servidor.crt ~/ca_root-pki/ca/ca.crt usuario@IP_SERVIDOR:~/mf0489/   # solo certificados públicos
```
El script se niega a firmar si la CSR no incluye el SAN `DNS:$DOMINIO`.

## 4. Entorno B — instalar el material PKI y verificarlo

```bash
sudo scripts/pki-instalar.sh
```
Instala `servidor.key` (600, root) en `/etc/ssl/private/`, `servidor.crt` (644) en `/etc/ssl/certs/` y `ca.crt` (644) en `/etc/ssl/mf0489/`; comprueba (a) fallo sin la CA (`unable to get local issuer certificate`), (b) `OK` con la CA y `-verify_hostname`, (c) fallo con un nombre incorrecto, (d) vigencia y (e) que clave y certificado corresponden; después borra la copia temporal de la clave (se conserva la CSR).

## 5. Entorno B — desplegar la aplicación

```bash
mkdir -p ~/exp89 && cp -r docker-compose.yml nginx scripts .env.example ~/exp89/ && cd ~/exp89
# .env a partir de la plantilla, con contraseñas NUEVAS y aleatorias (no se versiona; permisos 600)
cp .env.example .env && chmod 600 .env
sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=$(openssl rand -hex 20)/; s/^DB_ROOT_PASSWORD=.*/DB_ROOT_PASSWORD=$(openssl rand -hex 24)/; s/^WP_ADMIN_PASSWORD=.*/WP_ADMIN_PASSWORD=$(openssl rand -hex 16)/" .env
docker compose config --quiet            # valida el Compose (no imprime secretos)
docker compose up -d
docker compose ps
docker compose exec reverse-proxy nginx -t
```
Resultado: `exp89-nginx` (80 y 443), `exp89-wordpress` y `exp89-mariadb` (sin puertos publicados); redes `exp89_front` (10.89.1.0/24) y `exp89_back` (10.89.2.0/24, `internal`). Las subredes no deben solaparse con otras del servidor (`docker network ls` / `ip route`); si solapan, cámbielas en `docker-compose.yml`.

**Instalar WordPress:** abra `https://portal.proyecto.test/` y complete el asistente, o hágalo por línea de comandos desde el servidor con `curl --cacert /etc/ssl/mf0489/ca.crt --resolve portal.proyecto.test:443:127.0.0.1 -X POST "https://portal.proyecto.test/wp-admin/install.php?step=2" --data-urlencode ...`. Para usar un navegador, añada `IP_SERVIDOR portal.proyecto.test` al fichero `hosts` del cliente e importe `ca.crt` como autoridad de confianza.

## 6. Verificación

Desde un cliente con `ca.crt` (solo el certificado público):
```bash
IP_SERVIDOR=$IP_SERVIDOR CA_CERT=./ca.crt scripts/verificar-https.sh
```
Comprueba redirección 301 con ruta conservada, HTTPS con `curl --cacert` (sin `-k`), `openssl s_client` (versión, cipher, `Verification: OK`), TLS 1.2/1.3 aceptados, TLS 1.0/1.1 rechazados por el servidor y puertos 3306/8080 cerrados.

En el servidor:
```bash
sudo scripts/comprobar-despliegue.sh
```
Comprueba contenedores, `docker compose config --quiet`, `nginx -t`, puertos escuchando, permisos de `servidor.key`, verificación del certificado, ausencia de `ca.key` y Suricata activo.

## 7. Suricata y monitorización (Entorno B)

```bash
sudo apt install -y suricata && sudo suricata-update
ip -br address                                   # identifique la interfaz (p. ej. enp0s3)
grep -n "interface:" /etc/suricata/suricata.yaml # sustituya eth0 por su interfaz en af-packet y pcap
sudo cp /etc/suricata/suricata.yaml ~/backups_exp89/suricata.yaml.orig    # copia previa (fuera del repositorio)
sudo install -o root -g root -m 644 suricata/local.rules /etc/suricata/rules/local.rules
```
En `/etc/suricata/suricata.yaml`: poner `HOME_NET: "[IP_SERVIDOR]"` y añadir `- /etc/suricata/rules/local.rules` bajo `rule-files:`. Después:
```bash
sudo suricata -T -c /etc/suricata/suricata.yaml    # debe terminar sin errores
sudo systemctl enable --now suricata && sudo systemctl restart suricata
sudo tail -f /var/log/suricata/fast.log            # al hacer una petición HTTPS aparece "MF0489 Conexion HTTPS observada" (SID 4890001)
docker compose logs -f --tail=20 reverse-proxy     # la misma petición, con ruta, estado, TLS y cipher (log_format mf0489)
```
La regla solo registra el inicio de una conexión a 443; un SYN no es un ataque y Suricata no descifra las rutas HTTPS (ver `fase4-auditoria-tls-monitorizacion.md`).

## 8. Recuperación rápida ante problemas

| Síntoma | Comprobación | Solución |
|---|---|---|
| Nginx no arranca / `nginx -t` falla | `docker compose logs --tail=50 reverse-proxy` | Corregir `nginx/default.conf` (rutas internas `/etc/nginx/certs/…`); restaurar la copia de seguridad (abajo) |
| `502 Bad Gateway` | `docker compose ps`; nombre y puerto de `proxy_pass` | WordPress debe estar `Up` en `exp89_front`; `docker compose restart` |
| `bind: address already in use` | `ss -ltnp \| grep -E ":(80\|443) "` | Detener el otro servicio que ocupa 80/443 |
| `unable to get local issuer certificate` | Ruta de `ca.crt` en el cliente | Usar `--cacert ca.crt` / `-CAfile ca.crt` (no instalar la CA si no hace falta) |
| `hostname mismatch` | SAN del certificado y dominio usado | Conectar por `$DOMINIO` (con `--resolve`), no por IP; si el SAN es otro, repetir §2–§4 |
| WordPress en bucle de redirección o recursos `http://` | `X-Forwarded-Proto` en Nginx; `siteurl`/`home` | La imagen oficial interpreta la cabecera; comprobar `WP_HOME`/`WP_SITEURL` en el Compose |
| WordPress no conecta con la BBDD | `docker compose logs mariadb`; `.env` | Variables `DB_*` iguales en ambos servicios; MariaDB `healthy` |
| Certificado caducado | `openssl x509 -in /etc/ssl/certs/servidor.crt -noout -dates` | Repetir §2–§4 (nueva clave y CSR) y `docker compose restart reverse-proxy` |

**Copias de seguridad (siempre fuera del repositorio, p. ej. `~/backups_exp89`):**
```bash
mkdir -p ~/backups_exp89 && chmod 700 ~/backups_exp89
cp -a ~/exp89/nginx/default.conf ~/backups_exp89/default.conf.$(date +%F_%H%M)             # antes de tocar Nginx
docker compose exec -T mariadb sh -c 'mariadb-dump -uroot -p"$MARIADB_ROOT_PASSWORD" --single-transaction wordpress' > ~/backups_exp89/wordpress-$(date +%F_%H%M).sql
# Restaurar la BBDD (primero pruébelo en una base temporal):
docker compose exec -T mariadb sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" wordpress' < ~/backups_exp89/wordpress-<fecha>.sql
# Restaurar la configuración de Nginx y recargar sin cortar el servicio:
cp ~/backups_exp89/default.conf.<fecha> ~/exp89/nginx/default.conf
docker compose exec reverse-proxy nginx -t && docker compose exec reverse-proxy nginx -s reload
```

> **No ejecute `docker compose down -v`**: elimina los volúmenes (`exp89_db_data`, `exp89_wp_data`) y con ellos la base de datos y WordPress. Para parar sin perder datos: `docker compose down`.

## 9. Qué no se debe publicar nunca

`ca.key`, `servidor.key`, cualquier `.pem` con clave privada, `.p12`/`.pfx`, el `.env` real, copias de seguridad (`backups/`, `*.sql`, `*.gz`), exportaciones de la VM y contraseñas. Si una clave privada se publicó por error, añadirla al `.gitignore` **no** basta: hay que sustituir la clave, retirar el secreto del historial y documentar la incidencia. Use certificados y datos exclusivos del laboratorio; no reutilice claves ni contraseñas de servicios reales ni las incluya en la futura máquina CTF.

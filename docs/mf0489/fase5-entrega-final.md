# ExP 89 · Fase 5 — Documentación, reproducibilidad y entrega final

**Autor:** Volodymyr Osebchuk (vladibcn69@gmail.com)
**Módulo:** MF0489 · Semana 3 · Proyecto «Implementación de comunicaciones seguras, PKI y HTTPS»
**Dominio:** `portal.proyecto.test` · **Evidencias:** [`evidencias/fase5/`](evidencias/fase5/)

## 1. Resumen

Se ha publicado una aplicación web (WordPress + MariaDB) por **HTTPS** a través de **Nginx como reverse proxy** en Docker Compose, con un certificado firmado por una **CA de laboratorio propia** (OpenSSL), y se ha auditado y monitorizado con **Suricata** y los registros de Nginx. Esta fase consolida el trabajo para que otra persona pueda entender qué se desplegó, comprobar que funciona, recuperar el servicio ante un problema y repetir todos los pasos **sin disponer de contraseñas ni claves privadas del autor**.

## 2. Mapa de entregables

| Entregable | Ubicación |
|---|---|
| README único (visión general, estructura, despliegue rápido) | `README.md` |
| Guía de despliegue paso a paso desde cero | [`guia-despliegue.md`](guia-despliegue.md) |
| Arquitectura (análisis y diagrama definitivo) | [`fase1-arquitectura.md`](fase1-arquitectura.md), `arquitectura-final.png` (+ fuente `arquitectura-final.dot`) |
| PKI de laboratorio | [`fase2-pki.md`](fase2-pki.md), `pki/` (solo material público) |
| HTTPS con Nginx y Docker | [`fase3-https-docker.md`](fase3-https-docker.md), `docker-compose.yml`, `nginx/default.conf`, `.env.example` |
| Auditoría TLS y monitorización | [`fase4-auditoria-tls-monitorizacion.md`](fase4-auditoria-tls-monitorizacion.md), `suricata/local.rules` |
| Scripts reproducibles (sin secretos) | `scripts/`: `ca-crear.sh`, `pki-servidor-crear.sh`, `pki-emitir.sh`, `pki-instalar.sh`, `comprobar-despliegue.sh`, `verificar-https.sh` |
| Evidencias por fase | `docs/mf0489/evidencias/fase2` … `fase5` |
| Entrega final y último check | este documento |

La estructura del repositorio sigue la orientativa de la actividad (`README.md`, `docker-compose.yml`, `.env.example`, `.gitignore`, `nginx/`, `scripts/`, `suricata/`, `pki/`, `docs/mf0489/`); como añadidos justificados solo hay el fuente del diagrama (`arquitectura-final.dot`) y `.gitattributes` (saltos de línea LF en certificados, scripts y configuración).

## 3. Despliegue real en uso

- **Servidor:** Ubuntu Server 26.04 (VM VirtualBox de MF0488), `192.168.1.109`, interfaz `enp0s3`, Docker 29 y Compose 2.40.
- **Proyecto Compose `exp89`**, en `~/exp89` (`docker compose ls` → `running(3)`): `exp89-nginx` (`nginx:stable-alpine`, 80 y 443), `exp89-wordpress` (`wordpress:6-php8.3-apache`) y `exp89-mariadb` (`mariadb:11.4`), redes `exp89_front` y `exp89_back`, volúmenes `exp89_wp_data` y `exp89_db_data`. Independiente de cualquier despliegue anterior del servidor.
- **PKI instalada:** `/etc/ssl/private/servidor.key` (600), `/etc/ssl/certs/servidor.crt`, `/etc/ssl/mf0489/ca.crt`.
- **Suricata 8.0.3** en `enp0s3`, `HOME_NET: "[192.168.1.109]"`, `local.rules` (SID 4890001).
- **Entorno A (CA):** WSL2 Ubuntu en el host Windows (`~/ca_root-pki/ca/`); fuera de la VM que se exportará como CTF.
- **Copias de seguridad** (fuera del repositorio): `~/backups_exp89` en el servidor.

## 4. Correspondencia con la rúbrica (10 puntos)

| Fase | Criterios | Dónde está la evidencia |
|---|---|---|
| 1 (0,50) | F1.1 Nginx con terminación TLS señalada · F1.2 CA fuera de la VM CTF · F1.3 redes/puertos/Suricata coherentes | `fase1-arquitectura.md`, `arquitectura-final.png` |
| 2 (3,00) | F2.1–F2.6 CA protegida, raíz, CSR/SAN, certificado, verificación, instalación | `fase2-pki.md`, `evidencias/fase2/` |
| 3 (4,00) | F3.1–F3.6 Compose, Nginx/`nginx -t`, redes/puertos, aplicación sin 502, HTTPS sin `-k`, redirección | `fase3-https-docker.md`, `evidencias/fase3/` |
| 4 (2,50) | F4.1–F4.6 línea base, TLS auditado (con ajuste de suites), HTTP vs HTTPS, regla y alerta real, correlación, comprobación final | `fase4-auditoria-tls-monitorizacion.md`, `evidencias/fase4/` |
| 5 | Documentación, reproducibilidad y entrega (esta fase) | este documento, `guia-despliegue.md`, `evidencias/fase5/` |

## 5. Último check (extremo a extremo)

Realizado sobre el despliegue real y sobre un **clon limpio** del repositorio. Salidas completas en [`evidencias/fase5/03_ultimo_check.txt`](evidencias/fase5/03_ultimo_check.txt).

| # | Comprobación | Resultado |
|---|---|---|
| 1 | Diagrama definitivo actualizado | Coincide con `docker-compose.yml`: subredes 10.89.1.0/24 y 10.89.2.0/24 (`internal`), imágenes, nombres de contenedores, 443/80, `enp0s3` y TLS 1.2 con ECDHE + AEAD |
| 2 | Despliegue que realmente se usa | `~/exp89`, proyecto `exp89` con 3 contenedores, redes y volúmenes `exp89_*` |
| 3 | Certificados instalados | `servidor.crt`: `CN=portal.proyecto.test`, emisor ExP89 Lab Root CA, SAN DNS, `CA:FALSE`, `serverAuth`, válido hasta 19/10/2027; `openssl verify … -verify_hostname` → OK; huellas de `ca.crt` y `servidor.crt` idénticas a las copias de `pki/` |
| 4 | Configuración coherente | SHA-256 idénticos entre repositorio y servidor (Compose, `default.conf`, `.env.example`, `local.rules`, certificados y scripts); `nginx -T` efectivo = fichero montado; mismo dominio en SAN, `server_name` y `PORTAL_FQDN`. *El check detectó que el servidor tenía una versión antigua de `verificar-https.sh`; se sincronizó y se repitió la comprobación.* |
| 5 | Procedimiento de recuperación | Documentado en la guía (§8) y **probado**: copia de la BBDD y restauración en una base temporal (8 entradas restauradas = 8 originales) sin tocar la base real (`evidencias/fase5/01_…`) |
| 6 | Reproducibilidad | Clon limpio en carpeta vacía: `docker compose config --quiet` correcto con `.env.example` y con un `.env` generado según la guía, en local y en el servidor; scripts con sintaxis válida y bit ejecutable; cadena PKI completa probada con los scripts en un directorio temporal; todos los ficheros y scripts citados existen; sin enlaces rotos; sin secretos ni referencias a proyectos ajenos (`evidencias/fase5/02_…`) |
| 7 | Claves privadas protegidas | `ca.key` solo en WSL (600, cifrada; no abre sin la contraseña), ausente del servidor y del repositorio; `servidor.key` solo en `/etc/ssl/private` (600, root); ninguna `.key`, `.env` ni `.pcap` en el árbol de trabajo |
| 8 | `.gitignore` | Contiene como mínimo los nueve patrones de la actividad (y algunos más: `*.pcap`, `.ca_pass`); comprobado con `git check-ignore`: `.env`, `**/.env`, `**/*.key`, `**/private/`, `*.p12`, `*.pfx`, `backups/`, `*.sql`, `*.gz`, `*.pcap` y `.ca_pass` quedan ignorados |
| 9 | Qué se ha publicado | Repositorio público con las Fases 1–5 publicadas; autor único `VolodymyrOsebchuk`; sin secretos (sin claves privadas, `.env` real ni contraseñas) |
| 10 | Confianza HTTPS | `curl --cacert` sin `-k` → 200, `ssl_verify_result=0`; `openssl s_client` → `Verification: OK`, `Verified peername: portal.proyecto.test`; TLS 1.2/1.3 aceptados, TLS 1.0/1.1 rechazados por el servidor |
| 11 | Redirección HTTP → HTTPS | 301 con `Location: https://portal.proyecto.test/prueba?x=1` (host y ruta conservados) |
| 12 | Prueba funcional de la aplicación | Portada y `wp-login.php` 200; API REST 200; MariaDB con las entradas de WordPress; BBDD no expuesta |
| 13 | Configuración y monitorización | `nginx -t` correcto; `suricata -T` correcto; Suricata activo y generando alertas SID 4890001; log de Nginx en formato `mf0489` |

## 6. Reproducibilidad

Una persona con una copia del repositorio puede reproducir el despliegue con [`guia-despliegue.md`](guia-despliegue.md):

1. `scripts/ca-crear.sh`, `scripts/pki-servidor-crear.sh`, `scripts/pki-emitir.sh` y `sudo scripts/pki-instalar.sh` recorren la PKI (probados de principio a fin en un directorio temporal con claves desechables; `pki-emitir.sh` se niega a firmar una CSR con un SAN distinto del autorizado).
2. El `.env` se crea desde `.env.example` con contraseñas **nuevas** y aleatorias.
3. `docker compose up -d` y los scripts `comprobar-despliegue.sh` y `verificar-https.sh` verifican el resultado.

Nada de lo publicado contiene secretos: las claves y las contraseñas se generan en cada despliegue.

## 7. Incidencias y lecciones de la fase

- **Script de verificación:** un `grep -q` con `set -o pipefail` daba falsos fallos; se capturó la salida en una variable.

## 8. Limitaciones y mejoras posibles

- **HSTS** no se activa (CA privada y dominio `.test`); en producción, con CA pública, convendría con un `max-age` corto al principio.
- **Contraseña de `ca.key`:** durante el laboratorio se guardó en un fichero de permisos 600 en el Entorno A para automatizar los pasos; en un uso real se pedirá de forma interactiva (`scripts/ca-crear.sh` lo hace por defecto).
- **Tráfico interno** Nginx → WordPress → MariaDB sin cifrar (límite documentado, aislado en redes Docker, la de BBDD con `internal: true`).
- **Una sola MariaDB**, sin réplica (no la exige la rúbrica); la recuperación se basa en copias lógicas (`mariadb-dump`).
- **Suricata** ve metadatos, no el contenido ni las rutas HTTPS; para inspeccionar peticiones hay que hacerlo tras la terminación TLS (registros de Nginx, WAF).
- El repositorio de GitHub es **público**: conviene mantener la disciplina de no versionar secretos y revisar el historial antes de cada publicación.

## 9. Estado de la publicación y tareas pendientes

- Repositorio público con las Fases 1–5 publicadas; autor único; sin secretos.
- Al terminar el proyecto: eliminar las entradas de prueba de WordPress (realizado como último paso, tras el último check; ver `evidencias/fase5/04_limpieza_final.txt`), cambiar las contraseñas usadas durante el laboratorio y retirar la copia de la contraseña de `ca.key` si ya no se necesita la CA.

## 10. Conclusión

El servicio se publica por HTTPS con un certificado verificable contra la CA del laboratorio, solo Nginx está expuesto (80 y 443), la base de datos permanece aislada, TLS está limitado a 1.2/1.3 con suites ECDHE y AEAD, y la actividad se puede observar desde dos puntos complementarios (Suricata en la red y Nginx tras terminar TLS). Todo el despliegue es reproducible a partir del repositorio sin claves ni contraseñas.

# ExP 89 · Fase 4 — Validación de seguridad, TLS y monitorización

**Autor:** Volodymyr Osebchuk (vladibcn69@gmail.com)
**Módulo:** MF0489 · Semana 3
**Dominio:** `portal.proyecto.test` · **Evidencias:** [`evidencias/fase4/`](evidencias/fase4/) (salidas de texto; sin claves ni contraseñas)

Todas las pruebas se hicieron sobre la propia VM y la red de laboratorio, sin escaneos de terceros, sin ataques y sin desactivar la verificación TLS (nunca se usó `curl -k`).

## 1. Objetivo y arquitectura verificada

Auditar lo construido en las fases anteriores: que el servidor presenta el certificado correcto, que acepta solo TLS 1.2 y 1.3, y que se puede **monitorizar** con Suricata y los registros de Nginx aunque el contenido HTTPS vaya cifrado. Arquitectura (ver `arquitectura-final.png`): cliente → Nginx (terminación TLS, 443) → WordPress → MariaDB, con Suricata observando la interfaz `enp0s3` del servidor.

## 2. Máquinas e interfaz monitorizada

| Elemento | Valor |
|---|---|
| Cliente | WSL2 Ubuntu (Entorno A), `172.23.211.123`, **detrás del NAT del host Windows**; solo tiene `ca.crt` |
| Cómo ve el servidor al cliente | `192.168.1.103` (dirección LAN del host Windows) |
| Servidor | Ubuntu Server (VM VirtualBox) `192.168.1.109` |
| Interfaz monitorizada | `enp0s3` (Suricata `af-packet` y `pcap`; confirmada en `suricata.yaml` líneas 660 y 854; `tcpdump -i enp0s3` en las capturas) |
| Zona horaria de los registros | UTC en servidor, Suricata y Nginx; el cliente WSL usa hora local (+02:00) |

## 3. Línea base HTTPS (`01_linea_base_https.txt`)

| Prueba | Resultado real |
|---|---|
| Contenedores y reverse proxy activos | `exp89-nginx`, `exp89-wordpress`, `exp89-mariadb` en `Up` (MariaDB `healthy`); `nginx -t` correcto |
| Puerto 443 accesible desde el cliente | Sí (también 80 y 22; 3306 y 8080 cerrados) |
| Certificado y dominio válidos | `CN=portal.proyecto.test`, emisor `ExP89 Lab Root CA`, SAN coincide |
| Verificación de confianza | `curl --cacert` sin `-k`: HTTP 200, código de salida 0; `openssl s_client`: `Verification: OK`, `Verified peername: portal.proyecto.test` |
| Versión TLS negociada | TLS 1.3 |
| Cipher suite negociada | `TLS_AES_256_GCM_SHA384` (grupo `X25519MLKEM768`) |
| Aplicación funcionando | HTTP 200 |

## 4. Auditoría y ajuste de TLS (`02_auditoria_tls.txt`)

**Configuración activa** (`nginx -T`, no solo el fichero del repositorio): `ssl_protocols TLSv1.2 TLSv1.3;`. Nginx está enlazado con OpenSSL 3.5.8.

| Protocolo | Resultado real | ¿Cumple el requisito? |
|---|---|---|
| TLS 1.1 | **Rechazado por el servidor**: `tlsv1 alert protocol version` (alerta 70) incluso con el cliente en `@SECLEVEL=0`; `nmap` no lo lista | Sí (debe estar deshabilitado) |
| TLS 1.2 | Negociado: `ECDHE-RSA-AES256-GCM-SHA384`, `Verification: OK` | Sí |
| TLS 1.3 | Negociado: `TLS_AES_256_GCM_SHA384`, `Verification: OK` | Sí |

(TLS 1.0 se comporta igual que TLS 1.1.)

**Qué rechaza el servidor y qué limita el cliente.** Con el comando de la guía (`s_client -tls1_1 …`) el cliente falla con `no protocols available`: aquí **el límite es el cliente**, porque OpenSSL 3.5 desactiva TLS 1.0/1.1 por defecto, y esa prueba por sí sola no demuestra nada sobre el servidor. Para contrastarlo se hicieron tres comprobaciones:

1. *Control del cliente:* con un servidor de prueba local (clave desechable, borrada después) el mismo cliente con `-cipher 'ALL:@SECLEVEL=0'` **sí** completa el handshake TLS 1.0 y 1.1. Por tanto, con ese nivel el cliente puede hablar esos protocolos.
2. *Servidor real con ese cliente:* responde con la alerta `protocol_version`: **rechazo del servidor**.
3. *`nmap --script ssl-enum-ciphers`* (pila TLS propia, independiente de OpenSSL), ejecutado desde el host Windows: solo aparecen **TLSv1.2 y TLSv1.3**.

**Valoración de los algoritmos negociados**

1. TLS 1.2 → `ECDHE-RSA-AES256-GCM-SHA384`; TLS 1.3 → `TLS_AES_256_GCM_SHA384`.
2. En TLS 1.2 la suite incluye intercambio de claves (ECDHE), autenticación (RSA), cifrado (AES-256-GCM) y hash; en TLS 1.3 la suite solo define cifrado y hash, y el intercambio de claves va aparte (grupo `X25519MLKEM768`).
3. Protección: ECDHE da *forward secrecy* (comprometer la clave del servidor después no descifra sesiones pasadas); AES-GCM es cifrado autenticado (confidencialidad e integridad).
4. **No es lo mismo:** la suite protege el canal de la sesión; el certificado está firmado por la CA con `sha256WithRSAEncryption`, y en el handshake el servidor demuestra su identidad con su clave RSA (`rsa_pss_rsae_sha256`).
5. TLS 1.1: el servidor aborta la negociación con alerta de versión de protocolo.

### 4.1 Hallazgo y ajuste de TLS aplicado

**Hallazgo (antes).** `nmap` mostró que, en TLS 1.2, Nginx aceptaba **26 suites**, entre ellas suites sin *forward secrecy* (`TLS_RSA_WITH_*`, intercambio de clave RSA estático), modo CBC y ARIA/CAMELLIA, porque no se había restringido `ssl_ciphers`. Cumplía el requisito de protocolos, pero con una superficie criptográfica innecesaria. Con `s_client` (cliente en `@SECLEVEL=0`) se aceptaban, por ejemplo, `AES256-SHA256`, `AES128-SHA`, `ECDHE-RSA-AES128-SHA` y `ECDHE-RSA-CAMELLIA256-SHA384` (`07_tls_antes_ajuste.txt`).

**Ajuste (`nginx/default.conf`).** Copia de seguridad previa de `default.conf` fuera del repositorio (`~/backups_exp89`), validación con `nginx -t` y `nginx -s reload`:

```nginx
ssl_protocols       TLSv1.2 TLSv1.3;
ssl_ciphers         ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
ssl_prefer_server_ciphers off;
```

`ssl_ciphers` solo afecta a TLS 1.2 (las suites de TLS 1.3 no cambian). Con `ssl_prefer_server_ciphers off` decide el cliente entre suites que ya son todas seguras (AEAD con *forward secrecy*); es la recomendación habitual cuando no hay suites débiles. Como el certificado es RSA, en la práctica solo se usan las tres suites `ECDHE-RSA-*`; las `ECDSA` son inocuas.

**Resultado (después, `08_tls_despues_ajuste.txt`).**

| Prueba | Antes | Después |
|---|---|---|
| Suites TLS 1.2 que ofrece el servidor (`nmap`) | 26 (incluye `TLS_RSA_*`, CBC, ARIA, CAMELLIA) | **3**: `ECDHE-RSA-AES128-GCM-SHA256`, `ECDHE-RSA-AES256-GCM-SHA384`, `ECDHE-RSA-CHACHA20-POLY1305` |
| Suites TLS 1.3 (`nmap`) | 3 | 3 (sin cambios) |
| Protocolos | TLS 1.2 y 1.3 | TLS 1.2 y 1.3 (TLS 1.0/1.1 siguen rechazados: alerta `protocol_version`) |
| `AES256-SHA256`, `AES128-SHA`, `ECDHE-RSA-AES128-SHA`, `ECDHE-RSA-AES256-SHA384`, `ECDHE-RSA-CAMELLIA256-SHA384` | Aceptadas | **Rechazadas** (handshake failure) |
| `ECDHE-RSA-AES128-GCM`, `-AES256-GCM`, `-CHACHA20-POLY1305` | Aceptadas | Aceptadas |
| `s_client` TLS 1.2 / TLS 1.3 | `ECDHE-RSA-AES256-GCM-SHA384` / `TLS_AES_256_GCM_SHA384`, `Verification: OK` | Igual, `Verification: OK` |
| Nota global de `nmap` | A | A |

**Tras el ajuste todo sigue funcionando** (`09_comprobacion_tras_ajuste.txt`): `https://…` sin `-k` devuelve 200 con `ssl_verify_result=0`, `http://…` sigue redirigiendo con 301, WordPress (`wp-login.php`) responde 200, MariaDB conserva las entradas, los tres contenedores están activos, `nginx -t` es correcto y Suricata sigue activo registrando alertas (SID 4890001).

**Recomendación no aplicada: HSTS.** Añadir `add_header Strict-Transport-Security "max-age=…; includeSubDomains" always;` haría que los navegadores usen siempre HTTPS. No se activa en este laboratorio porque el certificado es de una CA privada (un error de certificado con HSTS no se puede omitir) y el dominio `.test` es solo de pruebas; en producción, con un certificado de una CA pública, sería recomendable empezar con un `max-age` corto.

**Persistencia de la configuración:** los cambios de Nginx se validaron con `nginx -t` y se aplicaron con `nginx -s reload` (log_format `mf0489`). La configuración vive en `nginx/default.conf`, montada en solo lectura.

## 5. Comparación de visibilidad HTTP y HTTPS (`03_observacion_http_https.txt`)

Captura en el servidor con `tcpdump -i enp0s3 -nn -s 0 -A` (filtros `tcp port 80` y `tcp port 443`) y una petición desde el cliente a `/mf0489-prueba-http` y otra a `/mf0489-prueba-https`.

| Elemento observado desde `enp0s3` | HTTP (80) | HTTPS (443) |
|---|---|---|
| IP origen y destino | 192.168.1.103 → 192.168.1.109 | 192.168.1.103 → 192.168.1.109 |
| Puerto de conexión | 52890 → 80 | 52870 → 443 |
| Método HTTP | **Visible** (`GET`) | No visible (0 ocurrencias) |
| Ruta solicitada | **Visible** (`/mf0489-prueba-http`; también la redirección `Location: https://…`) | **No visible** (0 ocurrencias de la ruta) |
| Versión TLS / metadatos | No aplica | SNI `portal.proyecto.test` visible en el ClientHello; TLS 1.3 y huella JA3 en el evento `tls` de Suricata |
| Contenido HTTP en texto claro | Sí | No: los datos de aplicación aparecen como bytes ilegibles |
| Eventos en Suricata | `http` (método, host, URL, estado 301) y `flow` | `alert` (SID 4890001), `tls` (SNI, versión, JA3) y `flow`; **ningún evento `http`** |

El HTTPS no oculta todo: se siguen viendo IP, puertos, tamaños, tiempos y metadatos del establecimiento (SNI). Con TLS 1.3 el certificado viaja cifrado en el handshake, por lo que Suricata no lo registra en este caso. Una captura ASCII sin URL es una observación útil, pero no una prueba matemática de cifrado por sí sola: se relaciona con la conexión TLS verificada mediante `openssl` y `curl`.

## 6. Regla de Suricata (`suricata/local.rules`, `04_regla_suricata.txt`)

```
alert tcp any any -> $HOME_NET 443 (msg:"MF0489 Conexion HTTPS observada"; flags:S; classtype:not-suspicious; sid:4890001; rev:1;)
```

- **Motivo:** dejar constancia del *inicio* de una conexión (SYN) hacia el puerto 443 del servidor, para poder relacionarla con los registros de Nginx. **No** es un detector de ataques ni de ninguna herramienta concreta, y un SYN a 443 no significa una petición HTTPS válida ni un ataque.
- **SID 4890001:** rango local (≥ 1 000 000), no usado previamente; `rev:1`.
- **`HOME_NET`:** se cambió de `[192.168.0.0/16,10.0.0.0/8,172.16.0.0/12]` a `[192.168.1.109]` (la dirección del servidor), para que `$HOME_NET` sea coherente con el host protegido. Efecto: las reglas del conjunto estándar que dependen de `$HOME_NET` ahora solo consideran como «red protegida» a esa IP.
- **Aplicación:** `local.rules` instalado en `/etc/suricata/rules/local.rules` (root:root 644) y añadido a `rule-files` de `suricata.yaml`; copia de seguridad previa del YAML y de las reglas en `~/backups_exp89/suricata-<fecha>` (fuera del repositorio).
- **Validación:** `suricata -T -c /etc/suricata/suricata.yaml` → configuración cargada correctamente (53 204 reglas, 0 fallidas); aviso informativo «SYN-only … disabling for toclient direction». Servicio reiniciado y activo.
- **Alerta real** (`fast.log` y `eve.json`), por ejemplo:
  `10/19/2026-18:45:58.081196 [**] [1:4890001:1] MF0489 Conexion HTTPS observada [**] [Classification: Not Suspicious Traffic] [Priority: 3] {TCP} 192.168.1.103:52828 -> 192.168.1.109:443`

## 7. Registros de Nginx (`05_correlacion_suricata_nginx.txt`)

Se definió `log_format mf0489` (fecha ISO 8601 con zona, cliente:puerto, petición, estado, protocolo TLS y cipher) y `access_log` dentro de cada bloque `server`. Línea de la prueba controlada:

```
2026-10-19T18:45:58+00:00 client=192.168.1.103:52828 request="GET /mf0489-correlacion-01?exp89_test=1792435555 HTTP/1.1" status=404 tls=TLSv1.3 cipher=TLS_AES_256_GCM_SHA384
```

Estado 404 porque la ruta no existe; no invalida la prueba, porque demuestra que la petición HTTPS llegó a Nginx tras terminar TLS.

## 8. Correlación de la misma prueba entre dos fuentes

Prueba: `curl --cacert ca.crt --resolve … "https://portal.proyecto.test/mf0489-correlacion-01?exp89_test=1792435555"` (ruta y parámetro únicos).

| Campo | Suricata | Nginx |
|---|---|---|
| Fecha y hora (UTC) | 18:45:58.081196 (SYN) | 18:45:58 (fin de la petición, resolución de 1 s) |
| IP del cliente | 192.168.1.103 | 192.168.1.103 |
| Puerto origen | 52828 | 52828 |
| Destino | 192.168.1.109:443 | 443 (contenedor `reverse-proxy`) |
| Acción o evento | SYN hacia 443 / SID 4890001 | `GET /mf0489-correlacion-01?exp89_test=1792435555` |
| Resultado | Alerta de laboratorio (`action: allowed`) | HTTP 404 |
| Información TLS / HTTP | Evento `tls`: SNI, TLS 1.3, JA3 (sin ruta) | `TLSv1.3`, `TLS_AES_256_GCM_SHA384`, método y ruta |

**Por qué es la misma prueba:** coinciden IP de cliente, puerto de origen (52828) y segundo de la marca de tiempo, y el parámetro único `exp89_test` solo aparece en Nginx.

**Diferencias explicadas, sin inventar coincidencias:**
- *NAT del cliente:* el cliente local usó `172.23.211.123:32862`; el servidor lo ve como `192.168.1.103:52828`. El host Windows traduce dirección y puerto, así que el puerto del lado del cliente no coincide con el visto por el servidor.
- *Docker:* el tráfico externo hacia el contenedor pasa por la DNAT de Docker, que conserva IP y puerto del cliente; por eso Nginx ve `192.168.1.103:52828`. Las pruebas hechas desde el propio servidor aparecen como `10.89.1.1` (puerta de enlace del bridge).
- *Reloj:* el reloj del cliente iba unos 2,3 s por detrás del servidor (cliente 18:45:55.80 UTC al iniciar, SYN visto a las 18:45:58.08). Por eso la correlación se ancla en los registros del servidor, que comparten reloj.
- *Resolución y momento:* Suricata marca el SYN con microsegundos; Nginx registra al terminar la petición y con resolución de segundos.
- *Qué ve cada uno:* **la correlación no significa que Suricata haya visto la ruta HTTPS**: el IDS relaciona conexiones y metadatos; Nginx ve la petición HTTP una vez descifrada.

## 9. Evento, alerta e incidente

- **Evento:** una conexión TCP al 443 y una petición recibida por Nginx.
- **Alerta:** se activó la regla 4890001 de Suricata.
- **Incidente:** **no**. La alerta procede de una prueba autorizada del laboratorio, sin impacto ni actividad anómala; una alerta generada durante una comprobación autorizada no debe clasificarse automáticamente como incidente de seguridad. Además, la regla solo registra conexiones y puede producir ruido en redes con mucha actividad.

## 10. Checklist de medidas de seguridad (`06_comprobacion_final.txt`)

| # | Comprobación | Resultado |
|---|---|---|
| 1 | HTTP redirige a HTTPS | 301 con `Location: https://portal.proyecto.test/` |
| 2 | HTTPS verificado con `curl --cacert` sin `-k` | HTTP 200, `ssl_verify_result=0` |
| 3 | DNS coincide con el certificado | `Verified peername: portal.proyecto.test` |
| 4 | Nginx con TLS 1.2/1.3; TLS 1.1 no habilitado | Sí (`nginx -T`, `nmap`, alerta `protocol_version`) |
| 5 | Aplicación y BBDD funcionan y conservan datos | WordPress 200; entradas de prueba en MariaDB |
| 6 | Solo puertos necesarios publicados | 22, 80 y 443; 3306 y 8080 cerrados |
| 7 | Certificados y clave instalados con permisos adecuados; montaje solo lectura | `servidor.key` 600 root; montajes `RW=false` |
| 8 | `ca.key` fuera de Ubuntu Server y sin secretos en GitHub | `ca.key` solo en WSL; búsqueda en el servidor y en el repositorio sin coincidencias |
| 9 | Suricata activo y reglas documentadas | `active`; `local.rules` y `HOME_NET` documentados |

**Incidencias reales y soluciones**
- `nmap` desde Windows con el sondeo por defecto no devolvió resultados útiles (host «0 up»); se resolvió usando `-sT -Pn` (conexión TCP completa).
- Un primer filtro `jq` no mostraba eventos porque usaba `empty` dentro de un objeto y descartaba toda la salida; se reescribió con `del(..|nulls)`.
- Nginx registraba cada petición **dos veces** (formato `main` de `nginx.conf` más `mf0489`) al declarar `access_log` a nivel `http`; se movió a cada bloque `server`, que sustituye al formato por defecto, y se repitió la prueba de correlación.
- El reloj del cliente difiere del servidor unos 2,3 s (ver §8).
- Las capturas `.pcap` quedaron en `/tmp` del servidor y no se versionan; al terminar la fase se eliminaron del servidor.
- Tras el ajuste de TLS (§4.1) se repitió la comprobación final (`09_comprobacion_tras_ajuste.txt`): la aplicación, la BBDD, el redireccionamiento y Suricata siguen operativos.

## 11. Conclusión: ¿cómo monitorizas una aplicación sin poder leer sus peticiones HTTPS desde la interfaz externa?

Desde la interfaz externa solo se observan **metadatos**: IP, puertos, tiempos, tamaños, SNI, versión de TLS y la propia existencia de la conexión (que la regla 4890001 registra). La ruta y el contenido de las peticiones solo existen en claro **después de terminar TLS**, es decir, en Nginx, cuyos registros (con método, ruta, estado, versión TLS y cipher) completan la imagen. Combinando ambas fuentes por IP, puerto de origen y hora, se puede reconstruir qué ocurrió sin descifrar el tráfico en la red. Quien necesite inspeccionar el contenido debe hacerlo en el punto de terminación TLS (registros de Nginx, WAF) o en el propio servidor de aplicación.

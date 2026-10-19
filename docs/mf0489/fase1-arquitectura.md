# ExP 89 · Fase 1 — Análisis de requisitos de seguridad y arquitectura

**Autor:** Volodymyr Osebchuk (vladibcn69@gmail.com)
**Módulo:** MF0489 · Semana 3 · Proyecto «Implementación de comunicaciones seguras, PKI y HTTPS»
**Nombre DNS del proyecto:** `portal.proyecto.test`

## 1. Objetivo

Actualizar la arquitectura del servidor Ubuntu Server (MF0488) para publicar una aplicación web por **HTTPS**, sin modificar todavía los servicios existentes. El estado inicial era: Ubuntu Server con Suricata, SSH y Docker, con una aplicación web servida por HTTP y su base de datos. Se parte de un entorno Docker **nuevo e independiente** (proyecto `exp89`), que no reutiliza contenedores, redes ni volúmenes anteriores.

Diagrama actualizado: ![Arquitectura final](arquitectura-final.png)
Fuente editable (Graphviz): [`arquitectura-final.dot`](arquitectura-final.dot).

## 2. Componentes

| Componente | Ubicación | Función |
|---|---|---|
| CA de laboratorio | **Entorno A** (WSL2 Ubuntu, host Windows) | Emite el certificado del servidor. `ca.key` cifrada con AES-256 (permisos 600), nunca sale del Entorno A. |
| Ubuntu Server | **Entorno B** (VM VirtualBox, 192.168.1.109, `enp0s3`) | Aloja Docker, Suricata y el material PKI del servidor. |
| `exp89-nginx` | Docker, red `exp89_front` | Reverse proxy y **punto de terminación TLS** (443). El 80 solo redirige a HTTPS. |
| `exp89-wordpress` | Docker, redes `exp89_front` y `exp89_back` | Aplicación web. Sin puertos publicados. |
| `exp89-mariadb` | Docker, red `exp89_back` | Base de datos única. Sin puertos publicados. |
| Suricata | Host Ubuntu Server, escucha en `enp0s3` | IDS en modo af-packet. |

La CA queda **fuera de la futura VM CTF** (rúbrica F1.2): vive en WSL2, un entorno distinto del servidor que se exportará.

## 3. Redes y puertos

| Red Docker | Subred | Miembros | Notas |
|---|---|---|---|
| `exp89_front` | 10.89.1.0/24 | `exp89-nginx`, `exp89-wordpress` | Entrada desde el host. |
| `exp89_back` | 10.89.2.0/24 | `exp89-wordpress`, `exp89-mariadb` | `internal: true`: sin salida a Internet ni acceso desde fuera. |

Las subredes se eligieron para **no solapar** con las existentes en el servidor (10.0.1–3.0/24 y 172.17–20.0.0/16).

Puertos publicados en el host: únicamente **443/tcp** (HTTPS) y **80/tcp** (redirección 301 a HTTPS conservando host y ruta). WordPress (80 interno) y MariaDB (3306 interno) no publican ningún puerto. SSH (22) sigue siendo el acceso administrativo.

## 4. Dónde se implementa TLS

- **TLS se termina en Nginx**, en el puerto 443, entre el cliente y el reverse proxy. Nginx presenta `servidor.crt` y usa `servidor.key`.
- El material PKI vive en el **host** (Entorno B) y se monta en el contenedor Nginx en solo lectura:
  - `/etc/ssl/private/servidor.key` (600, root): clave privada, solo en el servidor.
  - `/etc/ssl/certs/servidor.crt` (644): certificado del servidor.
  - `/etc/ssl/mf0489/ca.crt` (644): certificado público de la CA, para validación.
- **Quién gestiona los certificados:** Nginx los usa; la CA (Entorno A) los emite. La CSR viaja de B a A, y `servidor.crt` y `ca.crt` vuelven de A a B. **Nunca** se transfieren `ca.key` ni `servidor.key`.
- Solo las claves públicas y certificados (`ca.crt`, `servidor.crt`, `servidor.csr`, `servidor.ext`) se publican en el repositorio (carpeta `pki/`).

## 5. Tráfico cifrado e interno

| Tramo | Protocolo | Cifrado |
|---|---|---|
| Cliente → Nginx | HTTPS, 443 | **Sí (TLS)** |
| Cliente → Nginx | HTTP, 80 | No; solo devuelve 301 a HTTPS |
| Nginx → WordPress | HTTP, 80 (`exp89_front`) | No: tráfico interno dentro de Docker |
| WordPress → MariaDB | MySQL, 3306 (`exp89_back`) | No: tráfico interno, red `internal` |

Justificación: la seguridad se añade en el borde del servicio. El tráfico interno no sale de los bridges de Docker del propio host y la red `exp89_back` no tiene salida externa. Cifrar también ese tramo sería una mejora futura (defensa en profundidad), pero queda fuera del alcance de este proyecto.

## 6. Qué observa Suricata

Suricata mantiene su ubicación en el host y captura en `enp0s3` (192.168.1.109).

- **Ve:** el tráfico entrante y saliente de `enp0s3`: el handshake TLS al 443 (SNI, certificado, versión y suite de cifrado) y el HTTP en claro del puerto 80 (incluida la redirección), además de escaneos de puertos.
- **No ve:** el contenido HTTP dentro de TLS (peticiones, cabeceras, cuerpos) y el tráfico interno entre contenedores, que circula por los bridges `exp89_*`, no por `enp0s3`.

En la Fase 4 se comprobará esta diferencia comparando HTTP frente a HTTPS.

## 7. Requisitos de seguridad que se derivan

1. HTTPS obligatorio para el acceso externo; HTTP solo para redirigir.
2. `ca.key` exclusivamente en el Entorno A, cifrada y con permisos 600.
3. `servidor.key` exclusivamente en el Entorno B (`/etc/ssl/private`, 600).
4. Sin claves privadas, `.env` real, copias de seguridad ni exportaciones de VM en el repositorio (`.gitignore`).
5. Mínima exposición: solo 80 y 443 publicados; base de datos aislada en red interna.

## 8. Correspondencia con la rúbrica (0,50 puntos)

| Código | Cómo se cumple |
|---|---|
| F1.1 (0,20) | Diagrama con Nginx como entrada HTTPS (443) y terminación TLS señalada. |
| F1.2 (0,15) | CA en el Entorno A (WSL2), fuera de la futura VM CTF; claves y certificados en su ubicación. |
| F1.3 (0,15) | Redes, aplicación, BBDD, puertos y Suricata (`enp0s3`) coherentes con la infraestructura real. |

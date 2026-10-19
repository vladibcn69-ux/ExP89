# ExP 89 - Comunicaciones seguras, PKI y HTTPS (MF0489)

- **Autor:** Volodymyr Osebchuk (vladibcn69@gmail.com)
- **Módulo:** MF0489 · Semana 3 (Ironhack) · Proyecto «Implementación de comunicaciones seguras, PKI y HTTPS»
- **Repositorio:** https://github.com/vladibcn69-ux/ExP89
- **Dominio del proyecto:** `portal.proyecto.test`

Publica una aplicación web (WordPress + MariaDB) por **HTTPS** mediante **Nginx como reverse proxy** en Docker Compose, con un certificado emitido por una **CA de laboratorio propia (OpenSSL)**, y la audita y monitoriza con **Suricata**. Este README es único para todo el proyecto; el detalle por fases está en `docs/mf0489/`.

![Arquitectura final](docs/mf0489/arquitectura-final.png)

## Estado de las fases

| Fase | Contenido | Documento | Estado |
|------|-----------|-----------|--------|
| 1 | Arquitectura y análisis de requisitos | [`fase1-arquitectura.md`](docs/mf0489/fase1-arquitectura.md) | Hecha |
| 2 | PKI con OpenSSL (CA, CSR, certificado, instalación) | [`fase2-pki.md`](docs/mf0489/fase2-pki.md) | Hecha |
| 3 | HTTPS con Nginx reverse proxy y Docker | [`fase3-https-docker.md`](docs/mf0489/fase3-https-docker.md) | Hecha |
| 4 | Auditoría TLS y monitorización con Suricata | [`fase4-auditoria-tls-monitorizacion.md`](docs/mf0489/fase4-auditoria-tls-monitorizacion.md) | Hecha |
| 5 | Documentación, reproducibilidad y entrega final | [`fase5-entrega-final.md`](docs/mf0489/fase5-entrega-final.md), [`guia-despliegue.md`](docs/mf0489/guia-despliegue.md) | Hecha |

## Estructura del repositorio

```
├── README.md                  este documento (único)
├── docker-compose.yml         Nginx + WordPress + MariaDB (proyecto exp89)
├── .env.example               plantilla de variables (sin secretos)
├── .gitignore                 excluye claves, .env, copias de seguridad y volcados
├── nginx/default.conf         reverse proxy: redirección 80→443, TLS 1.2/1.3, proxy_pass
├── suricata/local.rules       regla local de laboratorio (SID 4890001)
├── pki/                       copias PÚBLICAS: ca.crt, servidor.crt, servidor.csr, servidor.ext
├── scripts/                   ca-crear, pki-servidor-crear, pki-emitir, pki-instalar,
│                              comprobar-despliegue, verificar-https (sin secretos)
└── docs/mf0489/               documentación por fases, guía de despliegue, diagrama y evidencias
```

(`docs/mf0489/arquitectura-final.dot` es el código fuente del diagrama; `.gitattributes` fuerza saltos de línea LF en certificados, scripts y configuración.)

## Arquitectura en pocas líneas

- **Entorno A (CA):** WSL2 Ubuntu. `ca.key` cifrada (AES-256, 600) y **nunca** sale de aquí.
- **Entorno B (servidor):** Ubuntu Server `192.168.1.109`. `servidor.key` solo en `/etc/ssl/private` (600); certificado en `/etc/ssl/certs`; `ca.crt` en `/etc/ssl/mf0489`.
- **Nginx** termina TLS (443; TLS 1.2 solo con ECDHE + AES-GCM/ChaCha20, y TLS 1.3); el 80 solo redirige (301). Monta certificados y configuración **en solo lectura**.
- **Redes Docker:** `exp89_front` 10.89.1.0/24 (Nginx + WordPress) y `exp89_back` 10.89.2.0/24, `internal` (WordPress + MariaDB). Solo Nginx publica puertos (80 y 443); la BBDD no se expone.
- **Suricata** observa `enp0s3`: ve metadatos (SNI, versión TLS, conexiones) pero no las rutas HTTPS; los logs de Nginx (`log_format mf0489`) ven las peticiones tras terminar TLS.

## Despliegue y verificación rápidos

Guía completa y sin secretos en [`docs/mf0489/guia-despliegue.md`](docs/mf0489/guia-despliegue.md). Resumen:

```bash
scripts/ca-crear.sh                 # Entorno A: CA de laboratorio
scripts/pki-servidor-crear.sh       # Entorno B: clave del servidor y CSR (enviar solo la CSR a A)
scripts/pki-emitir.sh               # Entorno A: revisar y firmar la CSR (devolver servidor.crt y ca.crt)
sudo scripts/pki-instalar.sh        # Entorno B: instalar en /etc/ssl y verificar
cp .env.example .env                # generar contraseñas propias (el .env real no se versiona)
docker compose config --quiet && docker compose up -d
IP_SERVIDOR=<IP> CA_CERT=./ca.crt scripts/verificar-https.sh   # desde un cliente con ca.crt
```

No ejecutar `docker compose down -v` (borra la base de datos y WordPress).

## Seguridad del repositorio

No se versionan claves privadas (`ca.key`, `servidor.key`), el `.env` real, copias de seguridad, volcados (`*.sql`, `*.gz`) ni exportaciones de VM (ver `.gitignore`). En `pki/` solo hay material público para documentación; Nginx usa los ficheros instalados en `/etc/ssl/` del servidor. Las pruebas usan siempre `curl --cacert` / `openssl s_client -CAfile`, sin `-k`.

# ExP 89 - Comunicaciones seguras, PKI y HTTPS (MF0489)

- **Autor:** Volodymyr Osebchuk (vladibcn69@gmail.com)
- **Modulo:** MF0489 - Semana 3 (Ironhack)
- **Repositorio:** https://github.com/vladibcn69-ux/ExP89
- **Dominio del proyecto:** `portal.proyecto.test`

Este README es unico y se ampliara a medida que avance el proyecto. La documentacion por fases esta en `docs/mf0489/`.

## Estado

| Fase | Contenido | Estado |
|------|-----------|--------|
| 1 | Arquitectura | Hecha (local) |
| 2 | PKI con OpenSSL | Hecha (local) |
| 3 | HTTPS con Nginx y Docker | Pendiente |
| 4 | Auditoria TLS y Suricata | Pendiente |
| 5 | Documentacion y entrega | Pendiente |

## Seguridad del repositorio

No se versionan claves privadas (`ca.key`, `servidor.key`), el `.env` real, copias de seguridad ni exportaciones de VM. Ver `.gitignore`.

## Contenido

- `docs/mf0489/fase1-arquitectura.md` y `arquitectura-final.png`: arquitectura y diagrama.
- `docs/mf0489/fase2-pki.md`: PKI de laboratorio con OpenSSL (CA en WSL2, certificado de `portal.proyecto.test`).
- `docs/mf0489/evidencias/fase2/`: salidas de los comandos (sin claves privadas).
- `pki/`: copias **públicas** (`ca.crt`, `servidor.crt`, `servidor.csr`, `servidor.ext`).

# ExP 89 · Fase 2 — Construcción de una Infraestructura de Clave Pública (PKI)

**Autor:** Volodymyr Osebchuk (vladibcn69@gmail.com)
**Módulo:** MF0489 · Semana 3
**Nombre DNS elegido:** `portal.proyecto.test` (el mismo en la CSR, el SAN, `servidor.ext` y todas las verificaciones)
**Evidencias:** [`evidencias/fase2/`](evidencias/fase2/) (salidas de texto; no contienen claves privadas)

## 1. Arquitectura PKI y separación de los dos entornos

| Entorno | Dónde | Qué contiene | Qué NO contiene |
|---|---|---|---|
| **A — CA** | WSL2 Ubuntu (host Windows), `~/ca_root-pki/ca/` | `private/ca.key` (cifrada), `ca.crt`, `solicitudes/`, `emitidos/`, `servidor.ext` | Nunca `servidor.key` |
| **B — Servidor** | Ubuntu Server (VM MF0488), `192.168.1.109` | `servidor.key`, `servidor.csr`, certificados públicos | Nunca `ca.key` |

El Entorno A no es la VM que se exportará como CTF. Solo viajan entre entornos ficheros públicos: la CSR (B→A) y `servidor.crt` y `ca.crt` (A→B), por `scp`.

Estructura del Entorno A:

```
~/ca_root-pki/ca/
├── private/ca.key          (600)  clave privada de la CA
├── solicitudes/servidor.csr       CSR recibida del servidor
├── emitidos/servidor.crt          certificado firmado
├── ca.crt                         certificado público de la CA
└── servidor.ext                   extensiones del certificado
```

Versión de OpenSSL: **3.5.5** en ambos entornos (WSL2 Ubuntu 26.04.1 y Ubuntu Server 26.04.1).

## 2. Nombre DNS elegido

`portal.proyecto.test`. El sufijo `.test` está reservado para entornos de prueba (RFC 6761). Que el nombre aparezca en el certificado no lo hace resolverse: la resolución (entrada en `hosts` del cliente) se prepara en la Fase 3.

## 3. Algoritmos, tamaños de clave y justificación

| Elemento | Algoritmo | Justificación |
|---|---|---|
| Clave de la CA | RSA 4096, AES-256-CBC, permisos 600 | Es la clave más sensible y de vida larga (10 años); se cifra con contraseña. |
| Certificado raíz | SHA-256, 3650 días | Hash estándar; validez larga habitual para una raíz de laboratorio. |
| Clave del servidor | RSA 3072, sin contraseña, permisos 600 | Nivel de seguridad ≈128 bits; Nginx debe arrancar sin intervención, por lo que la protección depende de los permisos y del acceso a la VM. |
| Certificado del servidor | SHA-256, 365 días | Vida corta: limita el impacto de una exposición. |

## 4. Creación y verificación de la CA (Entorno A)

```bash
umask 077
mkdir -p ~/ca_root-pki/ca/{private,solicitudes,emitidos} && cd ~/ca_root-pki/ca
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -aes-256-cbc -out private/ca.key
chmod 600 private/ca.key
openssl pkey -in private/ca.key -check -noout          # Key is valid (no muestra la clave)
openssl req -x509 -new -sha256 -days 3650 -key private/ca.key -out ca.crt \
  -subj "/C=ES/O=Proyecto ExP89 Lab/CN=ExP89 Lab Root CA" \
  -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" \
  -addext "subjectKeyIdentifier=hash"
openssl verify -CAfile ca.crt ca.crt                   # ca.crt: OK
```

Resultado (ver `evidencias/fase2/02_ca_key.txt` y `03_ca_crt.txt`):

- Clave: RSA 4096 bits, válida, permisos `-rw-------`.
- Subject = Issuer = `C=ES, O=Proyecto ExP89 Lab, CN=ExP89 Lab Root CA`. **Coinciden porque el certificado es autofirmado**: la CA se firma a sí misma y es su propia ancla de confianza.
- Validez: 19/10/2026 – 16/10/2036. Firma `sha256WithRSAEncryption`.
- `Basic Constraints: critical, CA:TRUE, pathlen:0`: es una CA y no puede emitir CA subordinadas, aunque sí firmar certificados de servidor.
- `Key Usage: critical, Certificate Sign, CRL Sign`.
- Huella SHA-256: `41:9C:B6:5D:D7:6A:D1:4F:29:8E:F5:3D:6F:D8:70:DD:B0:8D:0E:6D:87:86:F0:D2:B5:79:E6:84:FB:31:EA:84`.
- `openssl verify -CAfile ca.crt ca.crt` → **OK**. Esto solo indica coherencia interna; no significa que ningún navegador u otro equipo confíe ya en la CA.

## 5. Creación y validación de la CSR (Entorno B)

```bash
umask 077; mkdir -p ~/mf0489; cd ~/mf0489
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out servidor.key && chmod 600 servidor.key
DOMINIO="portal.proyecto.test"
openssl req -new -sha256 -key servidor.key -out servidor.csr \
  -subj "/CN=${DOMINIO}" -addext "subjectAltName=DNS:${DOMINIO}"
openssl req -in servidor.csr -text -noout -verify
```

Resultado (`evidencias/fase2/04_servidor_key_csr.txt`): clave RSA 3072 válida con permisos 600; la CSR indica `Certificate request self-signature verify OK`, `CN=portal.proyecto.test` y SAN `DNS:portal.proyecto.test`, e incluye la clave pública del servidor (3072 bits).

**Por qué no se transfiere la clave privada:** la CSR solo contiene datos públicos (identidad y clave pública) y va firmada con la clave privada, lo que demuestra posesión sin revelarla. Quien tuviera `servidor.key` podría suplantar al servidor, por lo que existe en un único sitio. Solo se envió `servidor.csr` a `solicitudes/` del Entorno A.

## 6. Configuración de `servidor.ext` y emisión del certificado (Entorno A)

```ini
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:portal.proyecto.test
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
```

- `CA:FALSE`: el certificado no puede actuar como CA.
- `serverAuth`: solo vale para autenticar un servidor TLS.
- `subjectKeyIdentifier` / `authorityKeyIdentifier`: identifican la clave del certificado y la de la CA emisora, para construir la cadena.
- El SAN replica exactamente el nombre autorizado en la CSR; la CA no firma si el nombre no está autorizado.

Antes de firmar se revisó la CSR (`-verify` → OK). Firma:

```bash
openssl x509 -req -in solicitudes/servidor.csr -CA ca.crt -CAkey private/ca.key -CAcreateserial \
  -out emitidos/servidor.crt -days 365 -sha256 -extfile servidor.ext
```

Resultado (`evidencias/fase2/05_firma_certificado.txt`): Subject `CN=portal.proyecto.test`; Issuer `C=ES, O=Proyecto ExP89 Lab, CN=ExP89 Lab Root CA`; validez 19/10/2026 – 19/10/2027; `sha256WithRSAEncryption`; `CA:FALSE`; `TLS Web Server Authentication`; SAN `DNS:portal.proyecto.test`; `openssl verify -CAfile ca.crt emitidos/servidor.crt` → OK. `servidor.crt` y `ca.crt` se devolvieron al Entorno B por `scp`; no se transfirió `ca.key` ni su contraseña.

## 7. Instalación y permisos en Ubuntu Server

```bash
sudo mkdir -p /etc/ssl/mf0489
sudo install -o root -g root -m 600 ~/mf0489/servidor.key /etc/ssl/private/servidor.key
sudo install -o root -g root -m 644 ~/mf0489/servidor.crt /etc/ssl/certs/servidor.crt
sudo install -o root -g root -m 644 ~/mf0489/ca.crt       /etc/ssl/mf0489/ca.crt
```

| Fichero | Ruta | Propietario | Permisos |
|---|---|---|---|
| Clave privada | `/etc/ssl/private/servidor.key` | root:root | `-rw-------` (600) |
| Certificado del servidor | `/etc/ssl/certs/servidor.crt` | root:root | `-rw-r--r--` (644) |
| CA pública | `/etc/ssl/mf0489/ca.crt` | root:root | `-rw-r--r--` (644) |

La CA se guarda aparte para validar a mano; **no se ha añadido** al almacén de confianza global del sistema. Tras comprobar la correspondencia clave/certificado se eliminó `~/mf0489/servidor.key`; se conservan `servidor.csr`, `servidor.crt` y `ca.crt` como evidencia.

## 8. Pruebas de confianza correcta e incorrecta

Salidas completas en `evidencias/fase2/06_instalacion_verificacion.txt`.

## 9. Comprobación de clave y certificado

Se comparó el SHA-256 de la clave pública derivada de la clave privada instalada con el de la clave pública del certificado (`openssl pkey -pubout -outform DER | openssl dgst -sha256` frente a `openssl x509 -pubkey -noout | openssl pkey -pubin -outform DER | openssl dgst -sha256`). Los dos resúmenes coinciden: `14c929f4…bca98580`. Nunca se mostró el contenido de la clave.

### Tabla de comprobaciones

| Comprobación | Resultado real | Interpretación |
|---|---|---|
| La CA raíz se verifica con su propio certificado | `ca.crt: OK` | Autofirmado coherente; la raíz es su propia ancla de confianza. |
| Verificación sin confiar en la CA | `error 20 … unable to get local issuer certificate` | El sistema no conoce la CA emisora; **no** indica que el certificado esté mal firmado. |
| Certificado verificado con `-CAfile` | `/etc/ssl/certs/servidor.crt: OK` | Cadena válida hasta la CA del laboratorio, propósito `sslserver` y nombre correctos. |
| SAN coincide con el DNS elegido | `DNS:portal.proyecto.test` | Es el nombre que usarán los clientes. |
| Verificación con DNS incorrecto (`servidor-equivocado.test`) | `error 62 … hostname mismatch` | Firma válida, pero el certificado no identifica a ese servidor. |
| Certificado vigente | `notBefore` 19/10/2026, `notAfter` 19/10/2027; `-checkend 0` vigente | Dentro del periodo de validez. |
| Clave privada y certificado corresponden | Resúmenes SHA-256 idénticos | Mismo par de claves. |

## 10. Problemas encontrados y soluciones aplicadas

- **Contraseñas por línea de comandos.** Para automatizar los pasos, la contraseña de `ca.key` se guarda fuera del repositorio, en un fichero de permisos 600 en el Entorno A, y se usa con `-passin file:`. En un entorno real se pedirá de forma interactiva y se rotará tras el proyecto. Ninguna contraseña figura en comandos versionados, scripts, capturas ni documentos.
- **Entrada de `sudo -S` desde Windows.** PowerShell añade `\r\n` a lo que se canaliza y `sudo` rechazaba la contraseña; se resolvió generando la entrada con `printf '%s\n'` desde Bash.
- **PEM y saltos de línea.** Windows podía convertir saltos de línea en los ficheros de `pki/`; se añadió `.gitattributes` (`eol=lf`) para los certificados, CSR y extensiones.

## Protección de secretos en el repositorio

`.gitignore` excluye `.env`, `**/*.key`, `**/private/`, `*.p12`, `*.pfx`, `backups/`, `*.sql` y `*.gz`. En `pki/` solo hay copias públicas para documentación (`ca.crt`, `servidor.crt`, `servidor.csr`, `servidor.ext`); Nginx usará los ficheros instalados en `/etc/ssl/`, no los del repositorio. Comprobado: ningún fichero del repositorio contiene claves privadas, `ca.key` solo existe en el Entorno A y `servidor.key` solo en `/etc/ssl/private/` del Entorno B.

## Correspondencia con la rúbrica (3,00 puntos)

| Código | Evidencia |
|---|---|
| F2.1 | CA en WSL2, `ca.key` cifrada AES-256, 600, no transferida (`02_ca_key.txt`). |
| F2.2 | `ca.crt` autofirmado, `CA:TRUE, pathlen:0`, `keyCertSign, cRLSign`, SHA-256 (`03_ca_crt.txt`). |
| F2.3 | Clave del servidor y CSR con SAN verificada (`04_servidor_key_csr.txt`). |
| F2.4 | `servidor.crt` con Subject/Issuer, `CA:FALSE`, `serverAuth`, SAN (`05_firma_certificado.txt`). |
| F2.5 | Verificación con y sin CA, nombre incorrecto, vigencia, correspondencia (`06_…txt`). |
| F2.6 | Rutas y permisos en `/etc/ssl/` (`06_…txt`). |

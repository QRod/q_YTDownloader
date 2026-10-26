# q_YTDownloader

Aplicación de escritorio para descargar video y audio mediante yt-dlp y FFmpeg.
Un repositorio, dos implementaciones nativas al entorno de cada plataforma:

| Plataforma | Código | Distribución |
|---|---|---|
| Windows 11 x64 | [windows/](windows/README.md), Electron | ZIP portátil con `.exe` y sus dependencias |
| macOS 13.5+ Apple Silicon | [macos/](macos/README.md), SwiftUI | ZIP con `.app`, yt-dlp, FFmpeg y Node incluidos |

Descarga los ejecutables en **Releases**. Verifica su SHA-256 con `SHA256SUMS`.
Los binarios se publican como archivos adjuntos de la entrega, no dentro del historial Git.
Esta aplicación no se instala ni se ejecuta en el servidor de pruebas de aplicaciones web.

## Instalar

Windows: extrae todo el ZIP y abre `q_YTDownloader.exe`; conserva los demás archivos.
macOS 13.5 o posterior (requerido por el Node incluido): descomprime y arrastra `q_YTDownloader.app` a Applications.
La aplicación macOS se firma de forma ad hoc, sin notarización de Apple; Windows
no tiene firma comercial. Los sistemas pueden pedir aprobación del editor.
No se desactivan las protecciones del sistema desde los scripts de construcción.

## Compilar desde un clon

```sh
git clone https://github.com/QRod/q_YTDownloader.git
cd q_YTDownloader
```

Windows (Python 3.9+, puede empaquetarse desde Windows/macOS/Linux):

```sh
python3 windows/scripts/build_windows.py
# En Windows: py -3 windows/scripts/build_windows.py
```

macOS ARM64 (Command Line Tools de Apple, Python 3 y curl):

```sh
zsh macos/build.sh
```

Las dependencias se descargan con versiones y hashes fijados en los archivos
`dependencies.lock.json` de cada plataforma. No se requieren dependencias de
los directorios originales del equipo de desarrollo. No se incluye historial,
preferencias, cookies ni medios descargados del usuario en las entregas.

## Pruebas

```sh
cd windows
npm test
```

Las pruebas de interfaz opcionales utilizan Playwright (`QYTD_PLAYWRIGHT` permite
indicar una instalación existente). Las pruebas de integración de motores en macOS
requieren preparar primero las dependencias de `macos/`.
Las pruebas nativas de instalación y ejecución en Windows 11 siguen pendientes;
la validación del empaquetado desde macOS no las reemplaza.

## Licencias

El código propio se distribuye bajo MIT: [LICENSE](LICENSE).
Cada componente de terceros mantiene su licencia, incluidas las obligaciones GPL
aplicables a los motores distribuidos. Sus avisos, versiones y enlaces al código
fuente y los archivos de construcción acompañan los paquetes en `Licenses`.
MIT no sustituye las licencias de esos motores.

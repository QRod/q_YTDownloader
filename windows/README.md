# qw_YTD · q_YTDownloader para Windows 11

Versión de escritorio de la aplicación macOS en `../macos`, con interfaz
Electron y motores yt-dlp / FFmpeg. Destino: Windows 11 de 64 bits (Intel/AMD).

## Ejecutar

Extrae `dist/qw_YTD-Windows-11-x64.zip` en una carpeta local de Windows y abre
`q_YTDownloader.exe`. Conserva el resto de archivos junto al ejecutable.
No requiere instalaciones adicionales. No está firmado con un certificado de editor.

## Funcionalidades

- Tema claro con acento gris oscuro y oscuro con naranja; el botón alterna directamente.
- Pegar enlace analiza dentro de la ventana, debajo del botón, sin ventana adicional.
- MP4 hasta la mejor calidad disponible y MP3; cola, progreso, cancelar, reintentar,
  búsqueda, filtros, historial y carpeta de destino configurable.
  Permite abrir la carpeta y quitar las completadas del historial sin borrar archivos.
- TXT UTF-8 con descripción, autor, canal, fechas, estadísticas, etiquetas y capítulos.
- Fecha de publicación opcional en nombre; usa fecha de subida como alternativa.
- Elegir video o lista completa si el enlace contiene el contexto de la lista.
  Una URL de lista directa se trata como colección. Un video sin ese contexto no
  permite descubrir todas las listas a las que pertenece.
- Avanzado permite descargar un canal completo; requiere analizarlo y pulsar Descargar.
- División por capítulos publicados, conservando el archivo completo. Aviso si no hay
  capítulos o no se puede obtener la miniatura. Corte según los límites de FFmpeg.
- Resultados parciales conservados si una colección contiene elementos con error.
- Las opciones se copian a cada tarea al agregarla; cambiarlas no altera tareas en curso.

| Salida | Archivo | Metadatos MP3 |
| --- | --- | --- |
| Video completo | `Canal_Título.mp4` | — |
| Video por capítulos | `Canal_Título_Capítulo.mp4` | — |
| Audio completo | `Título.mp3` | Artista = canal |
| Audio por capítulos | `01_Capítulo.mp3` | Pista, título del capítulo, artista = canal, álbum = video, miniatura incrustada |

Fecha opcional antepone `AAAA-MM-DD_`, o `sin-fecha_` si no hay fechas.
Las colecciones y capítulos usan subcarpetas. Se sanea el nombre para Windows;
los componentes largos se acortan para reducir problemas de longitud de ruta.
Conviene usar un destino corto como `C:\Videos` para colecciones con capítulos.

Historial: `%APPDATA%\q_YTDownloader`. Destino inicial:
`%USERPROFILE%\Downloads\q_YTDownloader` (usa la carpeta Descargas del sistema,
incluidas las ubicaciones redirigidas). Eliminar una entrada no elimina archivos.
Si la app se cierra con tareas activas, se puede reintentar al volver a abrirla.

## Construcción reproducible

`dependencies.lock.json` fija versiones, URLs oficiales y SHA-256. El script descarga,
verifica y ensambla los binarios de Windows; no necesita compilación cruzada.
Requiere Python 3.9+ para el empaquetado, no para ejecutar el resultado.

```sh
python3 scripts/build_windows.py
# En Windows: py -3 scripts/build_windows.py
# En volumen de red: --work-dir /private/tmp/qw-ytd-release
# Con archivos ya descargados: --offline
```

La carpeta de salida debe ser nueva para impedir mezclar versiones anteriores.
El ZIP incluye Electron, yt-dlp, FFmpeg, Node para el motor JavaScript de YouTube,
el procesador de etiquetas de capítulos y las licencias de terceros.
`SHA256SUMS.json` contiene los hashes de todos los archivos del paquete.

La interfaz no tiene acceso directo a Node ni a procesos. Usa un puente IPC limitado,
contexto aislado, sandbox y CSP. Los enlaces se pasan como argumentos sin shell.
La app no ejecuta scripts ni carga páginas externas dentro de su ventana.

## Validación

```sh
npm test
node tests/integration.cjs
node tests/ui-smoke.cjs
```

Las pruebas de integración usan yt-dlp y FFmpeg reales del proyecto macOS contra
un servidor local y metadatos controlados, y verifican nombres, TXT, fecha,
capítulos, etiquetas ID3 y bytes de la ilustración. Las pruebas de interfaz usan
Playwright instalado como dependencia de desarrollo (o ruta en `QYTD_PLAYWRIGHT`). Ver `validation/` para los resultados.
Los cuatro ejecutables del paquete se verifican como PE x64 y contra sus hashes.
La ejecución nativa del paquete y la integración con el Explorador quedan pendientes
de una prueba en Windows 11; esta Mac no ejecuta binarios Windows.
Las pruebas locales no garantizan la disponibilidad de todos los sitios externos.

Fuentes de distribución: [Electron](https://github.com/electron/electron/blob/main/docs/tutorial/application-distribution.md),
[yt-dlp](https://github.com/yt-dlp/yt-dlp), [imageio-ffmpeg](https://github.com/imageio/imageio-ffmpeg),
[Node.js](https://nodejs.org/dist/). Las licencias se incluyen en el paquete.

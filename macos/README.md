# q_YTDownloader

Aplicación local para macOS 13.5 o posterior, Apple Silicon, construida con SwiftUI, yt-dlp y FFmpeg.
Paquete ARM64 con motores incluidos. Arrastra la app a Applications después de descomprimir la entrega.

## Interfaz

- Tema claro: fondo suave y acento gris oscuro.
- Tema oscuro: fondo grafito y acento naranja.
- Botón de tema en la esquina superior derecha: cada clic alterna claro/oscuro sin menú. Se conserva entre sesiones.
- Formato MP4 o MP3, calidad, búsqueda e historial de descargas.

La interfaz utiliza controles nativos de macOS.

## Descargas

Pegar enlace analiza el portapapeles en la ventana principal. El estado, el enlace,
la elección de video/lista y el botón Descargar aparecen debajo del mismo botón.
La entrada manual y la descarga de canales también utilizan esa zona, sin ventanas adicionales.

| Salida | Nombre | Etiquetas MP3 |
| --- | --- | --- |
| MP4 completo | `Canal_Título.mp4` | — |
| MP4 por capítulos | `Canal_Título_Capítulo.mp4` | — |
| MP3 completo | `Título.mp3` | Artista = canal |
| MP3 por capítulos | `01_Capítulo.mp3` | Pista = número de capítulo; título = capítulo; artista = canal; álbum = título del video; ilustración = miniatura del video |

Los capítulos se agrupan en una carpeta con el nombre del video. Si se activa
Fecha en nombre, se antepone `AAAA-MM-DD_`. El canal tiene prioridad sobre el
autor; cuando el sitio no proporciona canal, se usa el autor disponible.
La miniatura se incorpora como ilustración ID3 dentro de cada MP3 por capítulos.
Si no está disponible, el audio y las etiquetas se conservan y la app muestra un aviso.

- **Metadatos .txt:** descripción completa, autor, canal, fechas disponibles, duración, estadísticas, etiquetas, categorías, lista y capítulos. Se guarda un TXT UTF-8 junto a cada video.
- **Fecha en nombre:** prefijo `AAAA-MM-DD`; usa la fecha de publicación (`release_date`) o, si no está disponible, la de subida (`upload_date`). Si ninguna existe, muestra `sin-fecha`.
- **Listas:** los enlaces de YouTube que incluyen `list=` ofrecen video individual o lista completa. Una URL de lista directa selecciona la lista completa. Un video sin contexto de lista no revela todas las listas a las que pertenece.
- **Canales:** Avanzado → Descargar canal. Analizar verifica que el enlace corresponde a una colección; luego puede descargarse todo lo que el sitio haga disponible. No inicia descargas masivas al pegar un video normal.
- **Capítulos:** guarda un archivo por capítulo publicado y conserva el video completo. Si no hay capítulos disponibles, conserva el original y muestra el aviso. El corte usa los límites de FFmpeg y puede ajustarse a fotogramas clave.
- Las listas/canales se organizan en su propia carpeta. Si algunos videos fallan, la descarga se marca **Parcial**, conservando los archivos guardados. Reintentar no duplica el conteo.

El historial y las opciones se guardan en `~/Library/Application Support/q_YTDownloader`.
El destino inicial es `~/Downloads/q_YTDownloader` y puede cambiarse desde la app.

## Compilación

```bash
zsh build.sh
```

La app se genera en `build/q_YTDownloader.app` y el ZIP distribuible en `../dist/q_YTDownloader-macOS-arm64.zip`.
No se instala automáticamente. Se compila con las Command Line Tools disponibles,
sin cambiar la configuración de Xcode ni aceptar sus licencias.

yt-dlp y FFmpeg se incluyen en `Contents/Resources/bin`. Node también se incluye en el paquete; no se reutilizan rutas del equipo de desarrollo.
Los binarios se descargan desde sus distribuidores y se verifican con los hashes fijados en `dependencies.lock.json`.
Los avisos de licencias de terceros se incluyen en `Contents/Resources/Licenses`.

## Validación

Las pruebas ejecutan los motores reales contra un MP4 generado localmente y un
servidor HTTP en 127.0.0.1. Las pruebas de listas y canales usan metadatos de
colecciones controladas con `--load-info-json`; no prueban la extracción actual
de canales públicos de YouTube ni la disponibilidad de videos privados/restringidos.

- `Tests/EngineCheck.swift`: MP4, MP3, validación de enlaces, cancelación en cola, errores, reintentos e historial.
- `Tests/AdvancedCheck.swift`: TXT, fecha, dos capítulos reales, colecciones completas, ausencia de fechas/capítulos, vista previa del enlace y colecciones parciales.
- `Tests/InterfacePreview.swift`: vistas de ambos temas con NSHostingView, usando almacenamiento temporal.
- `Tests/NamingCheck.swift`: los esquemas de nombres y las etiquetas incrustadas de artista, álbum, pista y título; extrae la ilustración de cada MP3 y compara sus bytes con la miniatura original. También verifica el aviso cuando la miniatura no existe.

Los sitios externos pueden cambiar y algunos enlaces requieren autenticación
o no estar disponibles para descarga. Esos errores se muestran en el historial.

Motor y opciones: https://github.com/yt-dlp/yt-dlp#readme
Paquete FFmpeg arm64: https://github.com/imageio/imageio-ffmpeg

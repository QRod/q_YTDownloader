import json
import os
import uuid

from yt_dlp.postprocessor.ffmpeg import FFmpegPostProcessor
from yt_dlp.utils import PostProcessingError

__all__ = ["QChapterMetadataPP"]


class QChapterMetadataPP(FFmpegPostProcessor):
    """Tag split MP3 files after extraction, splitting, and moving finish."""

    def run(self, info):
        if info.get("ext") != "mp3":
            return [], info
        chapters = info.get("chapters") or []
        if not chapters:
            return [], info
        artist = info.get("channel") or info.get("uploader") or "Canal"
        album = info.get("title") or "Video"
        cover = next((image.get("filepath") for image in reversed(info.get("thumbnails") or [])
                      if image.get("filepath") and os.path.isfile(image["filepath"])), None)
        if not cover:
            info["q_chapter_warning"] = "La miniatura no está disponible; los capítulos se guardaron sin ilustración."
            self.report_warning(info["q_chapter_warning"])
            self._downloader.to_stdout("Q_WARNING\t" + json.dumps(info["q_chapter_warning"]))
        for index, chapter in enumerate(chapters, 1):
            filename = chapter.get("filepath")
            if not filename or not os.path.isfile(filename):
                raise PostProcessingError(f"No se encontró el archivo del capítulo {index}")
            title = chapter.get("title") or f"Capítulo {index}"
            temporary = os.path.join(os.path.dirname(filename), f".q-tags-{uuid.uuid4().hex}.mp3")
            inputs = [filename]
            options = ["-map", "0:a:0", "-map_metadata", "0", "-map_chapters", "-1",
                       "-c:a", "copy", "-id3v2_version", "3",
                       "-metadata", f"track={index}", "-metadata", f"title={title}",
                       "-metadata", f"artist={artist}", "-metadata", f"album={album}"]
            if cover:
                inputs.append(cover)
                options += ["-map", "1:v:0", "-c:v", "copy", "-disposition:v:0", "attached_pic",
                            "-metadata:s:v:0", "title=Album cover",
                            "-metadata:s:v:0", "comment=Cover (front)"]
            try:
                self.run_ffmpeg_multiple_files(inputs, temporary, options)
                os.replace(temporary, filename)
            finally:
                if os.path.exists(temporary):
                    os.remove(temporary)
        return [], info

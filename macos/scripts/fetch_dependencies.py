#!/usr/bin/env python3
"""Fetch pinned macOS ARM64 engines; executable bundles never depend on local paths."""
import hashlib
import json
from pathlib import Path
import shutil
import tarfile
import subprocess
import zipfile

ROOT=Path(__file__).resolve().parents[1]
lock=json.loads((ROOT/'dependencies.lock.json').read_text())
cache=ROOT/'Dependencies';cache.mkdir(exist_ok=True)
for name,asset in lock.items():
 target=cache/asset['file']
 digest=lambda path:hashlib.sha256(path.read_bytes()).hexdigest()
 if not target.exists() or digest(target)!=asset['sha256']:
  print('Downloading '+asset['file'],flush=True)
  subprocess.run(['curl','--proto','=https','--tlsv1.2','-fL','--retry','3',asset['url'],'-o',str(target.with_suffix('.partial'))],check=True)
  part=target.with_suffix('.partial')
  if digest(part)!=asset['sha256']:raise SystemExit('Invalid SHA256: '+asset['file'])
  part.replace(target)
 if name=='ytdlp':shutil.copyfile(target,cache/'yt-dlp');(cache/'yt-dlp').chmod(0o755)
 if name=='ffmpeg':
  with zipfile.ZipFile(target) as archive:
   for filename in archive.namelist():
    if filename.endswith('ffmpeg-macos-aarch64-v7.1'):
     (cache/'ffmpeg').write_bytes(archive.read(filename));(cache/'ffmpeg').chmod(0o755)
    if filename.endswith('.dist-info/LICENSE'):(cache/'imageio-LICENSE').write_bytes(archive.read(filename))
 if name=='node':
  with tarfile.open(target) as archive:
   for filename,output in [('node-v24.22.1-darwin-arm64/bin/node','node'),('node-v24.22.1-darwin-arm64/LICENSE','Node-LICENSE')]:
    (cache/output).write_bytes(archive.extractfile(filename).read())
   (cache/'node').chmod(0o755)
print('Dependencies verified')

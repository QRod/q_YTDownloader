#!/usr/bin/env python3
"""Build a self-contained Windows x64 directory and ZIP on macOS/Windows/Linux."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def sha256(filename):
    digest = hashlib.sha256()
    with filename.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def download(asset, cache, offline):
    target = cache / asset['file']
    if target.exists() and sha256(target) == asset['sha256']:
        return target
    if offline:
        raise RuntimeError(f"Falta un archivo verificado en cache: {target.name}")
    print(f"Descargando {target.name}", flush=True)
    request = urllib.request.Request(asset['url'], headers={'User-Agent': 'qw-YTD-build/1.0'})
    temporary = target.with_suffix(target.suffix + '.partial')
    with urllib.request.urlopen(request, timeout=120) as response, temporary.open('wb') as output:
        shutil.copyfileobj(response, output)
    if sha256(temporary) != asset['sha256']:
        temporary.unlink()
        raise RuntimeError(f"SHA-256 incorrecto: {target.name}")
    temporary.replace(target)
    return target


def extract(archive, target):
    with zipfile.ZipFile(archive) as source:
        for member in source.infolist():
            name = member.filename
            if '__MACOSX' in name or any(part.startswith('._') for part in Path(name).parts):
                continue
            destination = (target / name).resolve()
            if not destination.is_relative_to(target.resolve()):
                raise RuntimeError('Ruta no válida en el ZIP')
            source.extract(member, target)


def pe_x64(filename):
    with filename.open('rb') as binary:
        if binary.read(2) != b'MZ':
            raise RuntimeError(f'No es un ejecutable Windows: {filename}')
        binary.seek(0x3c)
        binary.seek(struct.unpack('<I', binary.read(4))[0])
        if binary.read(4) != b'PE\0\0' or struct.unpack('<H', binary.read(2))[0] != 0x8664:
            raise RuntimeError(f'Arquitectura Windows x64 incorrecta: {filename}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--offline', action='store_true')
    parser.add_argument('--work-dir', type=Path, help='Directorio local de trabajo, útil en volúmenes de red')
    parser.add_argument('--cache-dir', type=Path, help='Existing verified download cache')
    args = parser.parse_args()
    lock = json.loads((ROOT / 'dependencies.lock.json').read_text())
    cache = args.cache_dir.resolve() if args.cache_dir else ROOT / 'cache'
    cache.mkdir(exist_ok=True)
    assets = {key: download(value, cache, args.offline) for key, value in lock.items()}
    work = args.work_dir.resolve() if args.work_dir else ROOT / 'dist'
    work.mkdir(parents=True, exist_ok=True)
    app = work / 'qw_YTD-Windows-11-x64'
    if app.exists():
        raise RuntimeError(f'El directorio de salida ya existe: {app}. Usa otro --work-dir para reconstruir.')
    app.mkdir()
    extract(assets['electron'], app)
    (app / 'electron.exe').rename(app / 'q_YTDownloader.exe')
    source = app / 'resources' / 'app'
    source.mkdir(parents=True, exist_ok=True)
    for folder in ['src', 'ui', 'Plugins']:
        shutil.copytree(ROOT / folder, source / folder, ignore=shutil.ignore_patterns('._*', '__pycache__', '*.pyc'))
    shutil.copy2(ROOT / 'package.json', source / 'package.json')
    shutil.copy2(ROOT.parent / 'LICENSE', source / 'LICENSE')
    bin_dir = source / 'bin'
    bin_dir.mkdir()
    shutil.copy2(assets['ytdlp'], bin_dir / 'yt-dlp.exe')
    licenses = app / 'Licenses'
    licenses.mkdir()
    with zipfile.ZipFile(assets['ffmpeg']) as wheel:
        exe = next(n for n in wheel.namelist() if n.endswith('.exe') and '/binaries/' in n)
        with wheel.open(exe) as binary, (bin_dir / 'ffmpeg.exe').open('wb') as output:
            shutil.copyfileobj(binary, output)
        for name in wheel.namelist():
            if '.dist-info/' in name and name.endswith(('LICENSE','METADATA')):
                (licenses / ('imageio-ffmpeg-' + Path(name).name + '.txt')).write_bytes(wheel.read(name))
    with zipfile.ZipFile(assets['node']) as node:
        for name in node.namelist():
            if name.endswith('/node.exe'):
                with node.open(name) as binary, (bin_dir / 'node.exe').open('wb') as output:
                    shutil.copyfileobj(binary, output)
            if name.endswith('/LICENSE'):
                (licenses / 'Node-LICENSE.txt').write_bytes(node.read(name))
    for exe in [app / 'q_YTDownloader.exe', *bin_dir.glob('*.exe')]:
        pe_x64(exe)
    for item in (ROOT / 'Licenses').iterdir():
        if item.is_file() and not item.name.startswith('._'):
            shutil.copy2(item, licenses / item.name)
    shutil.copy2(ROOT / 'LEEME-WINDOWS.txt', app / 'LEEME.txt')
    shutil.copy2(ROOT / 'dependencies.lock.json', licenses / 'dependencies.lock.json')
    manifest = {str(p.relative_to(app)).replace(os.sep, '/'): sha256(p) for p in sorted(app.rglob('*')) if p.is_file()}
    (app / 'SHA256SUMS.json').write_text(json.dumps(manifest, indent=2), encoding='utf8')
    archive = work / (app.name + '.zip')
    with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as output:
        for filename in sorted(app.rglob('*')):
            if filename.is_file():
                output.write(filename, filename.relative_to(work))
    (work / (archive.name + '.sha256')).write_text(f'{sha256(archive)}  {archive.name}\n')
    if work != ROOT / 'dist':
        dist = ROOT / 'dist'
        dist.mkdir(exist_ok=True)
        shutil.copy2(archive, dist / archive.name)
        shutil.copy2(work / (archive.name + '.sha256'), dist / (archive.name + '.sha256'))
    print(f'Paquete generado: {ROOT / "dist" / archive.name}', flush=True)
    print('Verificados los cuatro ejecutables PE x64 y los SHA-256 de las dependencias.', flush=True)


if __name__ == '__main__':
    main()

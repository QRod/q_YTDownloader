#!/bin/zsh
set -euo pipefail
source_root="${0:A:h}"
[[ $(uname -m) == arm64 ]] || { print -u2 'This release targets macOS Apple Silicon (ARM64).'; exit 1; }
if [[ -z "${DEVELOPER_DIR:-}" && -x /Library/Developer/CommandLineTools/usr/bin/swiftc ]]; then export DEVELOPER_DIR=/Library/Developer/CommandLineTools; fi
python3 "$source_root/scripts/fetch_dependencies.py"
build_root="${1:-$source_root/build}"
app_path="$build_root/q_YTDownloader.app"
[[ ! -e "$app_path" ]] || { print -u2 'Output already exists; select a new build directory.'; exit 1; }
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources/bin" "$app_path/Contents/Resources/Licenses"
swiftc -O -parse-as-library -target arm64-apple-macos13.0 -module-cache-path "${TMPDIR:-/tmp}/q-ytd-swift-cache" \
 "$source_root/Sources/DownloadConfiguration.swift" "$source_root/Sources/DownloadStore.swift" "$source_root/Sources/QDownloaderApp.swift" \
 -o "$app_path/Contents/MacOS/VideoDownloader"
for name in yt-dlp ffmpeg node; do install -m 755 "$source_root/Dependencies/$name" "$app_path/Contents/Resources/bin/$name"; done
cp "$source_root/Dependencies/imageio-LICENSE" "$source_root/Dependencies/Node-LICENSE" "$app_path/Contents/Resources/Licenses/"
cp "$source_root/Licenses/"* "$app_path/Contents/Resources/Licenses/"
cp "$source_root/../LICENSE" "$app_path/Contents/Resources/Licenses/q_YTDownloader-LICENSE"
cp "$source_root/dependencies.lock.json" "$app_path/Contents/Resources/Licenses/"
cp "$source_root/Info.plist" "$app_path/Contents/Info.plist"
mkdir -p "$app_path/Contents/Resources/Plugins/q_chapter_metadata"
cp -R "$source_root/Plugins/yt_dlp_plugins" "$app_path/Contents/Resources/Plugins/q_chapter_metadata/"
find "$app_path" -name '._*' -delete
find "$app_path" -name '__pycache__' -type d -exec /bin/rm -rf {} +
codesign --force --deep --sign - "$app_path"
mkdir -p "$source_root/../dist"
archive="$source_root/../dist/q_YTDownloader-macOS-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$archive"
(cd "${archive:h}" && shasum -a 256 "${archive:t}" > "${archive:t}.sha256")
print -r -- "$archive"

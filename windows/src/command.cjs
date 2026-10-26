'use strict';
const path = require('node:path');

function validURL(value) {
  if (typeof value !== 'string' || value.length > 8192) throw new Error('Pega un enlace HTTP o HTTPS válido.');
  let url;
  try { url = new URL(value.trim()); } catch { throw new Error('El enlace no es válido.'); }
  if (!['https:', 'http:'].includes(url.protocol) || url.username || url.password) throw new Error('Usa un enlace HTTP o HTTPS sin credenciales.');
  return url.href;
}
function playlistURL(value) {
  const url = new URL(validURL(value));
  if (!(url.hostname === 'youtube.com' || url.hostname.endsWith('.youtube.com') || url.hostname === 'youtu.be')) return null;
  const list = url.searchParams.get('list');
  return list ? `https://www.youtube.com/playlist?${new URLSearchParams({list})}` : null;
}
function isChannel(value) {
  const url = new URL(validURL(value));
  return /^(\/@|\/channel\/|\/c\/|\/user\/)/i.test(url.pathname);
}
const metadataTemplate = '%(.{id,title,description,webpage_url,upload_date,release_date,uploader,channel,channel_id,channel_url,duration,view_count,like_count,tags,categories,chapters,filepath,playlist,playlist_index,playlist_count})j';
function argumentsFor(item, tools) {
  const o = item.options;
  const args = ['--ignore-config', '--windows-filenames', '--newline', '--no-colors', '--progress',
    '--progress-template', 'download:Q_PROGRESS\t%(progress._percent_str)s\t%(progress._speed_str)s\t%(progress._eta_str)s',
    '--print', 'before_dl:Q_TITLE\t%(.{title,playlist_index,playlist_count})j',
    '--print', 'after_move:Q_META\t' + metadataTemplate,
    '--no-simulate', '--ffmpeg-location', tools.ffmpeg, '--paths', item.destination,
    '--js-runtimes', 'node:' + tools.node];
  args.push(...(o.scope === 'video' ? ['--no-playlist'] : ['--yes-playlist', '--lazy-playlist']));
  const date = o.publicationDate ? '%(release_date>%Y-%m-%d,upload_date>%Y-%m-%d|sin-fecha)s_' : '';
  const collection = o.scope === 'video' ? '' : '%(playlist_title,channel,uploader|Colección).70B/';
  const channel = '%(channel,uploader|Canal).50B';
  const title = '%(title).120B';
  const name = date + (item.format === 'video' ? channel + '_' : '') + title;
  args.push('--output', collection + name + '.%(ext)s');
  if (o.splitChapters) {
    // Shorter components leave room for the directory, UTF-8 names, and Windows paths.
    const chapter = item.format === 'video' ? date + channel + '_%(title).75B_%(section_title).55B' : date + '%(section_number)02d_%(section_title).120B';
    args.push('--split-chapters', '--output', 'chapter:' + collection + name + '/' + chapter + '.%(ext)s');
  }
  if (item.format === 'audio') {
    args.push('-f', 'bestaudio/best', '--extract-audio', '--audio-format', 'mp3', '--parse-metadata', '%(channel,uploader|Canal)s:%(meta_artist)s', '--embed-metadata');
    if (o.splitChapters) args.push('--parse-metadata', '%(title)s:%(meta_album)s', '--write-thumbnail', '--convert-thumbnails', 'jpg',
      '--no-plugin-dirs', '--plugin-dirs', tools.plugins, '--use-postprocessor', 'QChapterMetadata:when=after_move');
  } else {
    const height = ['2160', '1440', '1080', '720', '480'].includes(item.quality) ? `[height<=${item.quality}]` : '';
    args.push('-f', `bv*${height}+ba/b${height}`, '--merge-output-format', 'mp4', '--remux-video', 'mp4');
  }
  args.push('--', validURL(item.url));
  return args;
}
function metadataText(value) {
  const fields = [['Título','title'],['ID','id'],['Enlace','webpage_url'],['Autor','uploader'],['Canal','channel'],['ID de canal','channel_id'],['Canal URL','channel_url'],['Fecha de publicación','release_date'],['Fecha de subida','upload_date'],['Duración (s)','duration'],['Visualizaciones','view_count'],['Me gusta','like_count'],['Etiquetas','tags'],['Categorías','categories'],['Lista','playlist'],['Posición en lista','playlist_index']];
  const text = v => v == null ? 'No disponible' : Array.isArray(v) ? v.join(', ') : String(v);
  const time = n => `${Math.floor((n || 0) / 60).toString().padStart(2,'0')}:${Math.floor((n || 0) % 60).toString().padStart(2,'0')}`;
  return fields.map(([label,key]) => `${label}: ${text(value[key])}`).join('\r\n') + '\r\n\r\nDescripción\r\n───────────\r\n' + text(value.description)
    + '\r\n\r\nCapítulos\r\n─────────\r\n' + (value.chapters?.length ? value.chapters.map(c => `${time(c.start_time)} – ${time(c.end_time)} · ${c.title}`).join('\r\n') : 'No disponibles') + '\r\n';
}
function previewFrom(info, url, channelMode = false) {
  const collection = info._type === 'playlist' || Array.isArray(info.entries);
  if (channelMode && !collection && !isChannel(url)) throw new Error('Pega la dirección de un canal para descargarlo completo.');
  return {url, title: info.title || info.fulltitle || 'Sin título', author: info.channel || info.uploader || '',
    date: info.release_date || info.upload_date || '', playlistURL: playlistURL(url),
    collection, channelMode, count: info.playlist_count || info.n_entries || null,
    chapters: Array.isArray(info.chapters) ? info.chapters : []};
}
module.exports = {validURL, playlistURL, isChannel, argumentsFor, metadataText, previewFrom};

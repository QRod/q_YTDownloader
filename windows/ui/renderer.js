'use strict';
const api = window.downloader;
const $ = id => document.getElementById(id);
let state, preview, tab = 'all', busy = false;
const labels = {queued:'En cola',downloading:'Descargando',completed:'Completado',partial:'Parcial',failed:'Error',cancelled:'Cancelado',interrupted:'Interrumpido'};
function notice(error) { $('notice').textContent = error?.message || String(error); $('notice').hidden = false; }
function status(message,error = false) { $('analysis-status').textContent = message; $('analysis-status').classList.toggle('error',error); }
function element(tag, className, content) { const node = document.createElement(tag); if (className) node.className = className; if (content != null) node.textContent = content; return node; }
function action(text, callback) { const button = element('button','',text); button.addEventListener('click',() => Promise.resolve().then(callback).catch(notice)); return button; }
function render(next) {
  state = next; document.documentElement.dataset.theme = state.theme;
  $('theme').textContent = state.theme === 'dark' ? '☀' : '◐';
  $('theme').setAttribute('aria-label',state.theme === 'dark' ? 'Cambiar a tema claro' : 'Cambiar a tema oscuro');
  $('format').value = state.format; $('quality').value = state.quality; $('quality-label').hidden = state.format === 'audio';
  for (const key of ['metadata','publicationDate','splitChapters']) $(key).checked = Boolean(state.options[key]);
  $('destination').textContent = state.destination; $('folder').title = state.destination;
  if (state.notice) notice(state.notice);
  renderItems();
}
function renderItems() {
  if (!state) return;
  const term = $('search').value.toLocaleLowerCase();
  const items = state.items.filter(i => (tab === 'all' || (tab === 'active' ? ['queued','downloading'].includes(i.status) : i.status === 'completed')) && `${i.title} ${i.url}`.toLocaleLowerCase().includes(term));
  $('downloads').replaceChildren(); $('empty').hidden = items.length > 0;
  $('empty').querySelector('p').textContent = state.items.length ? 'No hay descargas en esta vista' : 'Agrega un enlace para comenzar';
  for (const item of items) {
    const row = element('article','download'); row.append(element('div','file-icon',item.format === 'audio' ? 'MP3' : 'MP4'));
    const body = element('div','download-content'); body.append(element('p','download-title',item.title));
    const meta = element('div','download-meta'); meta.append(element('span','',labels[item.status] || item.status));
    if (item.status === 'downloading') {
      meta.append(element('span','',`${Math.round(item.progress*100)}%`));
      if (item.speed) meta.append(element('span','',item.speed)); if (item.eta && item.eta !== 'NA') meta.append(element('span','',`Restante ${item.eta}`));
    }
    if (item.options.scope !== 'video') meta.append(element('span','',`${item.completedCount || 0} guardados${item.collectionCount ? ` / ${item.collectionCount}` : ''}`));
    if (item.options.splitChapters) meta.append(element('span','','Capítulos'));
    body.append(meta);
    if (item.status === 'downloading') { const progress = element('progress'); progress.max = 1; progress.value = item.progress; progress.setAttribute('aria-label','Progreso de descarga'); body.append(progress); }
    if (item.error) body.append(element('p','download-error',item.error));
    if (item.warning) body.append(element('p','download-warning',item.warning));
    row.append(body); const actions = element('div','actions');
    if (['queued','downloading'].includes(item.status)) actions.append(action('Cancelar',() => api.cancel(item.id)));
    else {
      if (item.filePaths?.length) actions.append(action('Mostrar',() => api.reveal(item.id)));
      if (item.status !== 'completed') actions.append(action('Reintentar',() => api.retry(item.id)));
      actions.append(action('Quitar',() => api.remove(item.id)));
    }
    row.append(actions); $('downloads').append(row);
  }
  const active = state.items.filter(i => ['queued','downloading'].includes(i.status)).length;
  $('summary').textContent = active ? `${active} en curso` : `${state.items.length} descargas`;
}
function invalidate() { preview = null; $('preview').hidden = true; status(''); }
async function analyze() {
  if (busy) return;
  invalidate(); busy = true;
  for (const id of ['analyze','paste','url','channel-mode','advanced','close-analysis']) $(id).disabled = true;
  status('Analizando enlace…');
  try {
    preview = await api.inspect($('url').value,$('channel-mode').checked);
    $('preview-title').textContent = preview.title;
    $('preview-detail').textContent = [preview.author,preview.date?.replace(/^(\d{4})(\d{2})(\d{2})$/,'$1-$2-$3'),preview.count ? `${preview.count} videos` : ''].filter(Boolean).join(' · ');
    $('scope').replaceChildren();
    if (!preview.collection) $('scope').append(new Option('Solo este video','video'));
    if (preview.playlistURL || preview.collection) $('scope').append(new Option(preview.channelMode ? 'Canal completo' : 'Lista completa',preview.channelMode ? 'channel' : 'playlist'));
    if (preview.collection) $('scope').value = preview.channelMode ? 'channel' : 'playlist';
    $('chapter-count').textContent = preview.chapters.length ? `${preview.chapters.length} capítulos` : '';
    $('preview').hidden = false; status('Listo para descargar');
  } catch (error) { status(error.message || String(error),true); }
  finally { busy = false; for (const id of ['analyze','paste','url','channel-mode','advanced','close-analysis']) $(id).disabled = false; }
}
$('theme').addEventListener('click',() => api.preferences({theme: state.theme === 'dark' ? 'light' : 'dark'}).catch(notice));
$('paste').addEventListener('click',async () => { try { $('analysis').hidden = false; $('url').value = (await api.clipboard()).trim(); invalidate(); if ($('url').value) await analyze(); else { status('Pega o escribe un enlace.'); $('url').focus(); } } catch (error) { notice(error); } });
$('advanced').addEventListener('click',() => { const open = $('channel-label').hidden; $('channel-label').hidden = !open; $('analysis').hidden = false; $('advanced').setAttribute('aria-expanded',String(open)); if (!open && $('channel-mode').checked) { $('channel-mode').checked = false; invalidate(); } $('url').focus(); });
$('analyze').addEventListener('click',analyze);
$('close-analysis').addEventListener('click',() => { invalidate(); $('analysis').hidden = true; });
$('url').addEventListener('input',invalidate); $('url').addEventListener('keydown',event => { if (event.key === 'Enter') analyze(); }); $('channel-mode').addEventListener('change',invalidate);
$('download').addEventListener('click',async () => {
  if (!preview) return;
  $('download').disabled = true;
  try { const scope = $('scope').value; await api.add({url: scope === 'playlist' && preview.playlistURL ? preview.playlistURL : preview.url, scope, title: preview.title}); invalidate(); $('analysis').hidden = true; $('url').value = ''; }
  catch (error) { status(error.message,true); } finally { $('download').disabled = false; }
});
for (const key of ['format','quality']) $(key).addEventListener('change',() => api.preferences({[key]:$(key).value}).catch(notice));
for (const key of ['metadata','publicationDate','splitChapters']) $(key).addEventListener('change',() => api.preferences({options:{[key]:$(key).checked}}).catch(notice));
$('folder').addEventListener('click',() => api.folder().catch(notice));
$('open-folder').addEventListener('click',() => api.openFolder().catch(notice));
$('clear-completed').addEventListener('click',() => api.clearCompleted().catch(notice));
$('search').addEventListener('input',renderItems);
for (const button of document.querySelectorAll('[data-tab]')) button.addEventListener('click',() => { tab = button.dataset.tab; for (const b of document.querySelectorAll('[data-tab]')) b.classList.toggle('selected',b === button); renderItems(); });
api.onChange(render);
api.state().then(render).catch(notice);

'use strict';
const fs = require('node:fs');
const path = require('node:path');
const {spawn} = require('node:child_process');
const {EventEmitter} = require('node:events');
const {StringDecoder} = require('node:string_decoder');
const {randomUUID} = require('node:crypto');
const {argumentsFor, validURL, metadataText, previewFrom, isChannel} = require('./command.cjs');

function stopProcess(child) {
  if (!child || child.exitCode !== null) return;
  if (process.platform === 'win32') {
    // Kill only the process tree owned by this task, including FFmpeg.
    const killer = spawn(path.join(process.env.SystemRoot || 'C:\\Windows', 'System32', 'taskkill.exe'), ['/PID', String(child.pid), '/T', '/F'], {windowsHide: true, stdio: 'ignore'});
    killer.on('error', () => child.kill());
  } else {
    try { process.kill(-child.pid, 'SIGTERM'); } catch { child.kill(); }
  }
}
function spawnOptions() { return {windowsHide: true, shell: false, detached: process.platform !== 'win32', stdio: ['ignore','pipe','pipe']}; }

class Engine extends EventEmitter {
  constructor({storage, destination, tools, spawnChild = spawn}) {
    super(); this.storage = storage; this.tools = tools; this.spawnChild = spawnChild; this.active = null; this.probe = null;
    this.state = {theme: 'light', format: 'video', quality: 'best', destination,
      options: {metadata: false, publicationDate: false, splitChapters: false}, items: []};
    fs.mkdirSync(storage, {recursive: true});
    const history = path.join(storage, 'history.json');
    try {
      if (fs.existsSync(history)) {
        const saved = JSON.parse(fs.readFileSync(history, 'utf8'));
        this.state = {...this.state, ...saved, items: Array.isArray(saved.items) ? saved.items : []};
      }
    } catch {
      const backup = history + '.corrupt-' + Date.now();
      if (fs.existsSync(history)) fs.copyFileSync(history, backup);
      this.state.notice = 'No se pudo leer el historial anterior; se conservó una copia de respaldo.';
    }
    for (const item of this.state.items) if (['queued','downloading'].includes(item.status)) {
      item.status = 'interrupted'; item.error = 'La sesión anterior se cerró. Puedes reintentar para continuar.';
    }
    this.save();
  }
  snapshot() { return structuredClone(this.state); }
  save() {
    const filename = path.join(this.storage, 'history.json'), temporary = filename + '.tmp';
    fs.writeFileSync(temporary, JSON.stringify(this.state, null, 2));
    fs.renameSync(temporary, filename);
  }
  changed(persist = true) { if (persist) this.save(); this.emit('change', this.snapshot()); }
  preferences(value) {
    if (['light','dark'].includes(value.theme)) this.state.theme = value.theme;
    if (['video','audio'].includes(value.format)) this.state.format = value.format;
    if (['best','2160','1440','1080','720','480'].includes(value.quality)) this.state.quality = value.quality;
    if (value.options) for (const key of ['metadata','publicationDate','splitChapters']) if (typeof value.options[key] === 'boolean') this.state.options[key] = value.options[key];
    this.changed(); return this.snapshot();
  }
  setDestination(destination) { this.state.destination = destination; this.changed(); }
  add({url, scope = 'video', title}) {
    url = validURL(url);
    if (!['video','playlist','channel'].includes(scope)) throw new Error('Tipo de descarga no válido.');
    const item = {id: randomUUID(), url, title: typeof title === 'string' ? title.slice(0,500) : url, format: this.state.format, quality: this.state.quality,
      destination: this.state.destination, options: {...this.state.options, scope}, status: 'queued', progress: 0, speed: '', eta: '', filePaths: [], metadataPaths: [], completedCount: 0, created: new Date().toISOString()};
    this.state.items.unshift(item); this.changed(); this.pump(); return item.id;
  }
  item(id) { const item = this.state.items.find(i => i.id === id); if (!item) throw new Error('Descarga no encontrada.'); return item; }
  pump() {
    if (this.active || this.closing) return;
    const item = [...this.state.items].reverse().find(i => i.status === 'queued');
    if (!item) return;
    const job = {id: item.id, child: null, diagnostic: '', cancelled: false, metadataError: null};
    this.active = job; item.status = 'downloading'; item.error = null; item.warning = null;
    try {
      fs.mkdirSync(item.destination, {recursive: true});
      job.child = this.spawnChild(this.tools.ytdlp, argumentsFor(item, this.tools), spawnOptions());
      const decoder = new StringDecoder('utf8'); let pending = '';
      job.child.stdout.on('data', chunk => {
        pending += decoder.write(chunk);
        let end;
        while ((end = pending.indexOf('\n')) >= 0) {
          this.consume(item, pending.slice(0,end).trim(), job); pending = pending.slice(end+1);
        }
        if (pending.length > 8_000_000) { job.metadataError = 'La salida del motor excedió el límite.'; stopProcess(job.child); }
      });
      job.child.stderr.on('data', chunk => { job.diagnostic = (job.diagnostic + chunk.toString('utf8')).slice(-12000); });
      job.child.on('error', error => { job.diagnostic = error.message; });
      job.child.on('close', code => {
        pending += decoder.end(); if (pending.trim()) this.consume(item, pending.trim(), job);
        this.finish(item, job, code);
      });
      this.changed();
    } catch (error) { job.diagnostic = error.message; this.finish(item, job, -1); }
  }
  consume(item, line, job) {
    try {
      if (line.startsWith('Q_PROGRESS\t')) {
        const [,percent,speed,eta] = line.split('\t');
        const amount = parseFloat(percent);
        if (Number.isFinite(amount)) item.progress = Math.min(1,Math.max(0,amount/100));
        item.speed = (speed || '').trim(); item.eta = (eta || '').trim(); this.changed(false);
      } else if (line.startsWith('Q_TITLE\t')) {
        const value = JSON.parse(line.slice(8)); item.title = value.title || item.title;
        item.collectionIndex = value.playlist_index; item.collectionCount = value.playlist_count; item.progress = 0; this.changed();
      } else if (line.startsWith('Q_WARNING\t')) {
        item.warning = JSON.parse(line.slice(10)); this.changed();
      } else if (line.startsWith('Q_META\t')) {
        const value = JSON.parse(line.slice(7));
        if (typeof value.filepath !== 'string') throw new Error('El motor no devolvió la ruta del archivo.');
        const chapters = (value.chapters || []).map(c => c.filepath).filter(p => typeof p === 'string' && fs.existsSync(p));
        const known = item.filePaths.includes(value.filepath);
        item.filePath = value.filepath;
        for (const filename of [value.filepath,...chapters]) if (!item.filePaths.includes(filename)) item.filePaths.push(filename);
        if (!known) item.completedCount++;
        if (item.options.splitChapters && !chapters.length) item.warning = 'Este video no tiene capítulos disponibles para dividir.';
        if (item.options.metadata) {
          const filename = value.filepath.replace(/\.[^.\\/]+$/, '') + '.txt';
          fs.writeFileSync(filename, metadataText(value), 'utf8');
          if (!item.metadataPaths.includes(filename)) item.metadataPaths.push(filename);
        }
        this.changed();
      } else job.diagnostic = (job.diagnostic + '\n' + line).slice(-12000);
    } catch (error) { job.metadataError = 'No se pudieron procesar los metadatos: ' + error.message; }
  }
  finish(item, job, code) {
    if (this.active !== job) return;
    const exists = item.filePaths.some(p => fs.existsSync(p));
    if (job.cancelled) item.status = 'cancelled';
    else if (code === 0 && exists && !job.metadataError) { item.status = 'completed'; item.progress = 1; }
    else { item.status = exists ? 'partial' : 'failed'; item.error = job.metadataError || job.diagnostic.trim().slice(-2500) || 'No se generó ningún archivo.'; }
    item.speed = ''; item.eta = ''; this.active = null; this.changed(); this.pump();
  }
  cancel(id) {
    const item = this.item(id);
    if (item.status === 'queued') { item.status = 'cancelled'; this.changed(); }
    else if (this.active?.id === id) { this.active.cancelled = true; stopProcess(this.active.child); }
  }
  retry(id) {
    const item = this.item(id);
    if (['queued','downloading'].includes(item.status)) return;
    item.status = 'queued'; item.error = null; item.warning = null; item.progress = 0;
    this.changed(); this.pump();
  }
  remove(id) {
    const item = this.item(id);
    if (['queued','downloading'].includes(item.status)) throw new Error('Cancela la descarga antes de quitarla del historial.');
    this.state.items = this.state.items.filter(i => i.id !== id); this.changed();
  }
  clearCompleted() {
    this.state.items = this.state.items.filter(i => i.status !== 'completed'); this.changed();
  }
  async inspect(value, channelMode = false) {
    const url = validURL(value);
    if (this.probe) throw new Error('Ya se está analizando un enlace.');
    const directCollection = isChannel(url) || /\/playlist\/?$/i.test(new URL(url).pathname) || channelMode;
    const args = ['--ignore-config','--no-warnings','--skip-download','--dump-single-json','--js-runtimes','node:' + this.tools.node];
    args.push(...(directCollection ? ['--flat-playlist','--playlist-items','1'] : ['--no-playlist']));
    args.push('--',url);
    return new Promise((resolve,reject) => {
      let child;
      try { child = this.spawnChild(this.tools.ytdlp,args,spawnOptions()); } catch (error) { reject(error); return; }
      this.probe = child;
      const chunks = []; let bytes = 0, diagnostic = '', limitError = null;
      const timer = setTimeout(() => { limitError = 'El análisis tardó demasiado. Puedes volver a intentarlo.'; stopProcess(child); },90000);
      child.stdout.on('data', chunk => { bytes += chunk.length; if (bytes > 8_000_000) { limitError = 'La respuesta del sitio es demasiado grande.'; stopProcess(child); } else chunks.push(chunk); });
      child.stderr.on('data', chunk => { diagnostic = (diagnostic + chunk.toString('utf8')).slice(-2000); });
      child.on('error', error => { diagnostic = error.message; });
      child.on('close', code => {
        clearTimeout(timer); if (this.probe === child) this.probe = null;
        if (limitError || code !== 0) return reject(new Error(limitError || diagnostic || 'No se pudo analizar el enlace.'));
        try { resolve(previewFrom(JSON.parse(Buffer.concat(chunks).toString('utf8')),url,channelMode)); } catch (error) { reject(error); }
      });
    });
  }
  shutdown() { this.closing = true; if (this.active) this.cancel(this.active.id); stopProcess(this.probe); this.save(); }
}
module.exports = {Engine, stopProcess};

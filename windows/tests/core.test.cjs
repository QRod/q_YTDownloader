'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {PassThrough} = require('node:stream');
const {EventEmitter} = require('node:events');
const {validURL,playlistURL,argumentsFor,metadataText,previewFrom} = require('../src/command.cjs');
const {Engine} = require('../src/engine.cjs');
const tools = {ytdlp:'yt-dlp.exe',ffmpeg:'C:\\App Dir\\ffmpeg.exe',node:'C:\\App Dir\\node.exe',plugins:'C:\\App Dir\\Plugins'};
function temporary(t) { const root = fs.mkdtempSync(path.join(os.tmpdir(),'qw-unit-')); t.after(() => fs.rmSync(root,{recursive:true,force:true})); return root; }
function setup(t) {
  const root = temporary(t), children = [];
  const engine = new Engine({storage:path.join(root,'history'),destination:path.join(root,'downloads'),tools,
    spawnChild(exe,args,options) { const child = new EventEmitter(); child.stdout = new PassThrough(); child.stderr = new PassThrough(); children.push({child,exe,args,options}); return child; }});
  return {root,engine,children};
}
test('Rejects command-like/file/credential links; URL remains a single non-shell argument', () => {
  for (const url of ['file:///C:/secret','javascript:alert(1)','--exec=bad','https://u:p@example.org/','nonsense']) assert.throws(() => validURL(url));
  assert.equal(validURL(' https://example.com/a?q=hello&x=1 '),'https://example.com/a?q=hello&x=1');
});
test('YouTube playlist context is recognized only on YouTube hosts', () => {
  assert.equal(playlistURL('https://www.youtube.com/watch?v=abc&list=PL123'),'https://www.youtube.com/playlist?list=PL123');
  assert.equal(playlistURL('https://youtu.be/abc?list=PL123'),'https://www.youtube.com/playlist?list=PL123');
  assert.equal(playlistURL('https://youtube.com.evil.example/watch?list=PL123'),null);
});
test('Commands preserve the requested output and metadata conventions', () => {
  for (const format of ['audio','video']) for (const splitChapters of [false,true]) {
    const args = argumentsFor({url:'https://example.org/video?a=1&b=2',destination:'C:\\Vídeos',format,quality:'1080',options:{scope:'video',splitChapters}},tools);
    assert.equal(args.at(-2),'--'); assert.equal(args.at(-1),'https://example.org/video?a=1&b=2');
    assert.ok(args.includes('--windows-filenames')); assert.ok(args.includes('--no-playlist'));
    const template = args[args.indexOf('--output')+1];
    assert.equal(template.includes('channel'),format === 'video');
    if (splitChapters && format === 'audio') { assert.ok(args.some(a => a.includes('%(section_number)02d_'))); assert.ok(args.includes('QChapterMetadata:when=after_move')); }
    if (format === 'audio') assert.ok(args.includes('%(channel,uploader|Canal)s:%(meta_artist)s'));
  }
});
test('TXT preserves descriptions and chapters; collections do not invent counts', () => {
  const text = metadataText({title:'Prueba',description:'Línea ñ\nOtra línea',chapters:[{title:'Introducción',start_time:0,end_time:65}]});
  assert.ok(text.includes('Línea ñ\nOtra línea')); assert.ok(text.includes('00:00 – 01:05 · Introducción'));
  const preview = previewFrom({_type:'playlist',title:'Lista',entries:[{}]},'https://www.youtube.com/playlist?list=PL1');
  assert.equal(preview.collection,true); assert.equal(preview.count,null);
  assert.throws(() => previewFrom({title:'Video'},'https://example.org/video',true));
});
test('Queue runs serially, captures preferences per task, and cancels queued jobs', t => {
  const {engine,children} = setup(t);
  const first = engine.add({url:'https://example.org/a'});
  engine.preferences({format:'audio',options:{splitChapters:true}});
  const second = engine.add({url:'https://example.org/b'});
  assert.equal(children.length,1); assert.equal(engine.item(first).format,'video'); assert.equal(engine.item(second).format,'audio');
  assert.equal(children[0].options.shell,false); assert.equal(children[0].options.windowsHide,true);
  engine.cancel(second); children[0].child.emit('close',1);
  assert.equal(engine.item(second).status,'cancelled'); assert.equal(children.length,1);
});
test('Partial downloads and retries preserve files and avoid duplicate completed counts', t => {
  const {engine,children,root} = setup(t), output = path.join(root,'saved.mp4'); fs.writeFileSync(output,'saved');
  const id = engine.add({url:'https://example.org/a',scope:'playlist'});
  const data = 'Q_META\t' + JSON.stringify({title:'A',filepath:output}) + '\n';
  children[0].child.stdout.emit('data',Buffer.from(data)); children[0].child.emit('close',1);
  assert.equal(engine.item(id).status,'partial'); assert.equal(engine.item(id).completedCount,1);
  engine.retry(id); children[1].child.stdout.emit('data',Buffer.from(data)); children[1].child.emit('close',0);
  assert.equal(engine.item(id).status,'completed'); assert.equal(engine.item(id).completedCount,1);
  engine.remove(id); assert.ok(fs.existsSync(output));
});
test('UTF-8 split across chunks, chapter warnings and persistent history survive reload', t => {
  const {engine,children,root} = setup(t);
  const id = engine.add({url:'https://example.org/a'});
  const line = Buffer.from('Q_TITLE\t' + JSON.stringify({title:'Introducción ñ'}) + '\n');
  const cut = line.indexOf(Buffer.from('ó'))+1;
  children[0].child.stdout.emit('data',line.subarray(0,cut)); children[0].child.stdout.emit('data',line.subarray(cut));
  assert.equal(engine.item(id).title,'Introducción ñ');
  children[0].child.stdout.emit('data',Buffer.from('Q_WARNING\t"Sin miniatura"\n'));
  const restored = new Engine({storage:path.join(root,'history'),destination:root,tools});
  assert.equal(restored.item(id).status,'interrupted'); assert.equal(restored.item(id).warning,'Sin miniatura');
});
test('No successful status when output is absent or metadata processing fails', t => {
  const {engine,children} = setup(t), id = engine.add({url:'https://example.org/a'});
  children[0].child.stdout.emit('data',Buffer.from('Q_META\t{}\n')); children[0].child.emit('close',0);
  assert.equal(engine.item(id).status,'failed'); assert.match(engine.item(id).error,/metadatos/);
});
test('Clearing completed history preserves active tasks and downloaded files', t => {
  const {engine,children,root} = setup(t), output = path.join(root,'kept.mp4'); fs.writeFileSync(output,'video');
  const completed = engine.add({url:'https://example.org/a'});
  children[0].child.stdout.emit('data',Buffer.from('Q_META\t' + JSON.stringify({filepath:output}) + '\n'));
  children[0].child.emit('close',0);
  const active = engine.add({url:'https://example.org/b'});
  engine.clearCompleted();
  assert.ok(!engine.state.items.some(i => i.id === completed)); assert.equal(engine.item(active).status,'downloading'); assert.ok(fs.existsSync(output));
});
test('Inspection uses bounded flat collection analysis and rejects a second probe', async t => {
  const {engine,children} = setup(t);
  const promise = engine.inspect('https://www.youtube.com/@channel',true);
  await assert.rejects(engine.inspect('https://example.com/second'),/analizando/);
  assert.ok(children[0].args.includes('--flat-playlist')); assert.ok(children[0].args.includes('--playlist-items'));
  children[0].child.stdout.emit('data',Buffer.from(JSON.stringify({_type:'playlist',title:'Canal',playlist_count:12,entries:[{}]})));
  children[0].child.emit('close',0);
  const preview = await promise; assert.equal(preview.count,12); assert.equal(preview.channelMode,true);
});

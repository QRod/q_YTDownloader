'use strict';
// Exercise production Engine and the copied plugin with real native tools and local media.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const http = require('node:http');
const {spawn,spawnSync} = require('node:child_process');
const assert = require('node:assert/strict');
const {Engine} = require('../src/engine.cjs');
const root = path.resolve(__dirname,'..');
const work = fs.mkdtempSync(path.join(os.tmpdir(),'qw-integration-'));
const ffmpeg = path.join(work,'ffmpeg'), ytdlp = path.join(work,'yt-dlp');
fs.copyFileSync(path.join(root,'../macos/Dependencies/yt-dlp'),ytdlp);
fs.copyFileSync(path.join(root,'../macos/Dependencies/ffmpeg'),ffmpeg);
fs.chmodSync(ffmpeg,0o755); fs.chmodSync(ytdlp,0o755);
function ff(args,encoding = 'utf8') {
  const result = spawnSync(ffmpeg,['-hide_banner','-loglevel','error',...args],{encoding,maxBuffer:10_000_000});
  assert.equal(result.status,0,result.stderr?.toString()); return result.stdout;
}
ff(['-f','lavfi','-i','color=c=gray:s=320x180:r=25:d=2','-f','lavfi','-i','sine=frequency=440:duration=2','-c:v','libx264','-c:a','aac','-shortest',path.join(work,'sample.mp4')]);
ff(['-f','lavfi','-i','color=c=orange:s=320x180','-frames:v','1','-update','1',path.join(work,'thumbnail.jpg')]);
const sample = fs.readFileSync(path.join(work,'sample.mp4')), thumbnail = fs.readFileSync(path.join(work,'thumbnail.jpg'));
const server = http.createServer((req,res) => {
  const data = req.url === '/sample.mp4' ? sample : req.url === '/thumbnail.jpg' ? thumbnail : null;
  if (!data) { res.writeHead(404); return res.end(); }
  res.writeHead(200,{'Content-Type':req.url.endsWith('.mp4') ? 'video/mp4' : 'image/jpeg','Content-Length':data.length}); res.end(data);
});
async function wait(engine,id) {
  const deadline = Date.now()+150000;
  while (['queued','downloading'].includes(engine.item(id).status)) {
    if (Date.now()>deadline) { engine.shutdown(); throw new Error('Timeout '+id); }
    await new Promise(r => setTimeout(r,100));
  }
  return engine.item(id);
}
async function main() {
  await new Promise(r => server.listen(0,'127.0.0.1',r));
  const base = `http://127.0.0.1:${server.address().port}`;
  function fixture(id = 'test',title = 'Video de prueba') { return {_type:'video',id,title,channel:'Canal de prueba',uploader:'Autor diferente',description:'Descripción de prueba\nSegunda línea ñ.',upload_date:'20261001',release_date:'20261002',extractor:'generic',extractor_key:'Generic',webpage_url:base+'/sample.mp4',duration:2,
    thumbnail:base+'/thumbnail.jpg',thumbnails:[{url:base+'/thumbnail.jpg',id:'0',ext:'jpg'}],chapters:[{title:'Introducción',start_time:0,end_time:1},{title:'Final',start_time:1,end_time:2}],
    formats:[{url:base+'/sample.mp4',format_id:'http',ext:'mp4',height:180,vcodec:'h264',acodec:'aac'}]}; }
  async function run(key,info,preferences,scope = 'video') {
    const folder = path.join(work,key), json = path.join(work,key+'.json'); fs.writeFileSync(json,JSON.stringify(info));
    const engine = new Engine({storage:path.join(folder,'history'),destination:path.join(folder,'downloads'),tools:{ytdlp,ffmpeg,node:process.execPath,plugins:path.join(root,'Plugins')},
      spawnChild(exe,args,options) { const end = args.lastIndexOf('--'); return spawn(exe,[...args.slice(0,end),'--no-clean-info-json','--load-info-json',json],options); }});
    engine.preferences(preferences);
    const id = engine.add({url:base+'/sample.mp4',scope});
    const item = await wait(engine,id);
    assert.equal(item.status,'completed',key+': '+item.error);
    return {item,engine};
  }
  const fullVideo = await run('video',fixture(),{format:'video'});
  assert.equal(path.basename(fullVideo.item.filePath),'Canal de prueba_Video de prueba.mp4');
  console.log('PASS full MP4 filename');
  const chapters = await run('video-chapters',fixture(),{format:'video',options:{splitChapters:true,metadata:true,publicationDate:true}});
  assert.equal(chapters.item.filePaths.length,3); assert.match(chapters.item.filePath,/2026-10-02_Canal de prueba_Video de prueba.mp4$/);
  assert.ok(chapters.item.filePaths.some(p => p.endsWith('2026-10-02_Canal de prueba_Video de prueba_Introducción.mp4')));
  const text = fs.readFileSync(chapters.item.metadataPaths[0],'utf8'); assert.ok(text.includes('Segunda línea ñ.')); assert.ok(text.includes('Introducción'));
  console.log('PASS chapter MP4 filenames, publication date and UTF-8 TXT metadata');
  const fullAudio = await run('audio',fixture(),{format:'audio'});
  assert.equal(path.basename(fullAudio.item.filePath),'Video de prueba.mp3');
  assert.match(ff(['-i',fullAudio.item.filePath,'-f','ffmetadata','-']),/artist=Canal de prueba/);
  console.log('PASS full MP3 filename and channel artist');
  for (const missingCover of [false,true]) {
    const info = fixture(); if (missingCover) { delete info.thumbnail; delete info.thumbnails; }
    const {item} = await run(missingCover ? 'audio-no-cover':'audio-chapters',info,{format:'audio',options:{splitChapters:true}});
    assert.equal(item.filePaths.length,3);
    for (const [index,title] of ['Introducción','Final'].entries()) {
      const file = item.filePaths.find(p => path.basename(p) === `0${index+1}_${title}.mp3`); assert.ok(file);
      const tags = ff(['-i',file,'-f','ffmetadata','-']);
      for (const tag of [`track=${index+1}\n`,`title=${title}\n`,'artist=Canal de prueba\n','album=Video de prueba\n']) assert.ok(tags.includes(tag),tags);
      if (!missingCover) assert.deepEqual(ff(['-i',file,'-map','0:v:0','-c:v','copy','-frames:v','1','-f','image2pipe','-'],null),thumbnail);
    }
    if (missingCover) assert.match(item.warning,/miniatura/);
    console.log('PASS MP3 chapters: filenames, track/title/artist/album, '+(missingCover?'missing-thumbnail warning':'exact embedded thumbnail bytes'));
  }
  const collection = {_type:'playlist',id:'list',title:'Lista de prueba',extractor:'generic',extractor_key:'Generic',entries:[fixture('one','Primero'),fixture('two','Segundo')]};
  for (const scope of ['playlist','channel']) {
    const {item} = await run(scope,collection,{format:'video',options:{metadata:true}},scope);
    assert.equal(item.completedCount,2); assert.equal(item.metadataPaths.length,2); assert.ok(item.filePaths.every(p => p.includes('Lista de prueba')));
    console.log('PASS complete '+scope+', separate TXT files and collection directory');
  }
  const noChapters = fixture(); delete noChapters.chapters; delete noChapters.release_date; delete noChapters.upload_date;
  const {item} = await run('no-chapters',noChapters,{format:'video',options:{splitChapters:true,publicationDate:true}});
  assert.match(item.warning,/capítulos/); assert.match(path.basename(item.filePath),/^sin-fecha_/);
  console.log('PASS missing date and missing chapter handling');
  const live = new Engine({storage:path.join(work,'probe'),destination:work,tools:{ytdlp,ffmpeg,node:process.execPath}});
  const preview = await live.inspect(base+'/sample.mp4'); assert.equal(preview.collection,false); assert.ok(preview.title);
  await assert.rejects(live.inspect(base+'/sample.mp4',true),/canal/);
  console.log('PASS real local link analysis and invalid channel rejection');
  console.log('INTEGRATION PASSED; outputs: '+work);
}
main().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => server.close());

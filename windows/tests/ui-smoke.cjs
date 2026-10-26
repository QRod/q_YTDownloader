'use strict';
const {chromium} = require(process.env.QYTD_PLAYWRIGHT || 'playwright-core');
const path = require('node:path');
const fs = require('node:fs');
const assert = require('node:assert/strict');
const {pathToFileURL} = require('node:url');
async function main() {
  const browser = await chromium.launch({headless:true,channel:'chrome'});
  try {
    const page = await browser.newPage({viewport:{width:1080,height:780}});
    const errors = []; page.on('pageerror',e => errors.push(e.message));
    await page.addInitScript(() => {
      let listener;
      let state = {theme:'light',format:'video',quality:'best',destination:'C:\\Users\\Prueba\\Downloads\\q_YTDownloader',options:{metadata:false,publicationDate:false,splitChapters:false},items:[]};
      window.testCalls = [];
      window.downloader = {
        state:async () => structuredClone(state), onChange:fn => listener=fn,
        preferences:async value => { state={...state,...value,options:{...state.options,...value.options}}; listener(structuredClone(state)); },
        clipboard:async () => 'https://www.youtube.com/watch?v=sample&list=PL1',
        inspect:async (url,channelMode) => { window.testCalls.push({method:'inspect',url,channelMode}); return {url,title:'Video de prueba',author:'Canal de prueba',date:'20261002',playlistURL:'https://www.youtube.com/playlist?list=PL1',collection:channelMode,channelMode,count:12,chapters:[{title:'Introducción'},{title:'Final'}]}; },
        add:async value => { window.testCalls.push({method:'add',...value}); state.items.unshift({id:'1',title:'Video de prueba',url:value.url,format:state.format,status:'queued',options:{...state.options,scope:value.scope},filePaths:[]}); listener(structuredClone(state)); },
        cancel:async id => { state.items[0].status='cancelled';listener(structuredClone(state)); },
        retry:async () => {},remove:async () => {},folder:async () => {},reveal:async () => {},
        openFolder:async () => window.testCalls.push({method:'openFolder'}),
        clearCompleted:async () => { window.testCalls.push({method:'clearCompleted'}); state.items=state.items.filter(i => i.status!=='completed');listener(structuredClone(state)); }
      };
    });
    await page.goto(pathToFileURL(path.resolve(__dirname,'../ui/index.html')).href);
    await page.waitForFunction(() => document.querySelector('#destination').textContent.length > 0);
    assert.equal(await page.locator('dialog').count(),0);
    await page.locator('#theme').click(); assert.equal(await page.locator('html').getAttribute('data-theme'),'dark');
    await page.locator('#theme').click(); assert.equal(await page.locator('html').getAttribute('data-theme'),'light');
    await page.locator('#paste').click(); await page.locator('#preview').waitFor({state:'visible'});
    assert.match(await page.locator('#analysis-status').textContent(),/Listo/);
    assert.equal(await page.locator('#scope option').count(),2);
    await page.selectOption('#scope','playlist'); await page.selectOption('#format','audio');
    await page.locator('#metadata').check(); await page.locator('#splitChapters').check();
    await page.locator('#download').click(); await page.locator('.download').waitFor();
    const calls = await page.evaluate(() => window.testCalls);
    assert.ok(calls.some(c => c.method === 'add' && c.scope === 'playlist' && c.url.includes('/playlist?')));
    assert.equal(await page.locator('.file-icon').textContent(),'MP3');
    await page.getByRole('button',{name:'Cancelar',exact:true}).click();
    assert.match(await page.locator('.download-meta').textContent(),/Cancelado/);
    await page.locator('#advanced').click(); await page.locator('#channel-mode').check();
    await page.locator('#url').fill('https://www.youtube.com/@Canal'); await page.locator('#analyze').click();
    await page.waitForFunction(() => document.querySelector('#scope').value === 'channel');
    await page.locator('#search').fill('no-coincide'); assert.equal(await page.locator('.download').count(),0);
    await page.locator('#search').fill('');
    await page.locator('#open-folder').click(); await page.locator('#clear-completed').click();
    const extra = await page.evaluate(() => window.testCalls);
    assert.ok(extra.some(c => c.method === 'openFolder')); assert.ok(extra.some(c => c.method === 'clearCompleted'));
    const out = path.resolve(__dirname,'../validation'); fs.mkdirSync(out,{recursive:true});
    await page.screenshot({path:path.join(out,'windows-light.png'),fullPage:true});
    await page.locator('#theme').click(); await page.screenshot({path:path.join(out,'windows-dark.png'),fullPage:true});
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth > innerWidth); assert.equal(overflow,false);
    assert.deepEqual(errors,[]);
    await page.locator('#close-analysis').click(); assert.equal(await page.locator('#analysis').isVisible(),false);
    await page.setViewportSize({width:780,height:580});
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth),false);
    console.log('UI PASSED: direct theme toggle, inline paste analysis, playlist/channel selection, preferences, queue cancellation, search, folder/history actions, minimum window width and both theme screenshots');
  } finally { await browser.close(); }
}
main().catch(error => { console.error(error); process.exitCode=1; });

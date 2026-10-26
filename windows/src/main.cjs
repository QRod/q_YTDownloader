'use strict';
const {app, BrowserWindow, ipcMain, dialog, shell, clipboard} = require('electron');
const path = require('node:path');
const fs = require('node:fs');
const {Engine} = require('./engine.cjs');
app.setName('q_YTDownloader');
app.setAppUserModelId('local.q.ytdownloader.windows');
app.setPath('userData', path.join(app.getPath('appData'), 'q_YTDownloader'));
const hasLock = app.requestSingleInstanceLock();
if (!hasLock) app.quit();
let window, engine;
app.on('second-instance', () => { if (window) { if (window.isMinimized()) window.restore(); window.show(); window.focus(); } });
app.whenReady().then(() => {
  if (!hasLock) return;
  const root = app.getAppPath();
  const bin = path.join(root,'bin');
  engine = new Engine({storage: app.getPath('userData'), destination: path.join(app.getPath('downloads'),'q_YTDownloader'),
    tools: {ytdlp: path.join(bin,'yt-dlp.exe'), ffmpeg: path.join(bin,'ffmpeg.exe'), node: path.join(bin,'node.exe'), plugins: path.join(root,'Plugins')}});
  window = new BrowserWindow({width: 1080, height: 780, minWidth: 780, minHeight: 580, title: 'q_YTDownloader', backgroundColor: engine.state.theme === 'dark' ? '#18191c' : '#f5f5f3',
    autoHideMenuBar: true, webPreferences: {preload: path.join(__dirname,'preload.cjs'), nodeIntegration: false, contextIsolation: true, sandbox: true}});
  window.setMenu(null);
  window.webContents.setWindowOpenHandler(() => ({action: 'deny'}));
  window.webContents.on('will-navigate', event => event.preventDefault());
  const handle = (name, fn) => ipcMain.handle(name, async (event,...args) => {
    if (event.sender !== window.webContents || event.senderFrame !== window.webContents.mainFrame) throw new Error('Solicitud no válida.');
    return fn(...args);
  });
  handle('state', () => engine.snapshot());
  handle('preferences', value => engine.preferences(value || {}));
  handle('clipboard', () => clipboard.readText());
  handle('inspect', (url, channel) => engine.inspect(url, channel === true));
  handle('add', value => engine.add(value));
  for (const action of ['cancel','retry','remove']) handle(action, id => engine[action](id));
  handle('clear-completed', () => engine.clearCompleted());
  handle('open-folder', async () => {
    fs.mkdirSync(engine.state.destination, {recursive:true});
    const error = await shell.openPath(engine.state.destination);
    if (error) throw new Error(error);
  });
  handle('folder', async () => {
    const selection = await dialog.showOpenDialog(window, {title: 'Carpeta de descargas', defaultPath: engine.state.destination, properties: ['openDirectory','createDirectory']});
    if (!selection.canceled && selection.filePaths[0]) engine.setDestination(selection.filePaths[0]);
    return engine.snapshot();
  });
  handle('reveal', id => {
    const item = engine.item(id);
    const filename = [item.filePath,...item.filePaths].find(p => p && fs.existsSync(p));
    if (!filename) throw new Error('El archivo ya no está en su ubicación original.');
    shell.showItemInFolder(filename);
  });
  engine.on('change', state => { if (!window.isDestroyed()) window.webContents.send('state-changed',state); });
  window.loadFile(path.join(root,'ui','index.html'));
  window.on('close', event => {
    if (engine.active || engine.state.items.some(i => i.status === 'queued')) {
      const choice = dialog.showMessageBoxSync(window, {type: 'question', buttons: ['Seguir descargando','Cerrar y detener'], defaultId: 0, cancelId: 0,
        title: 'Descargas en curso', message: 'Hay descargas en curso. ¿Quieres cerrar y detenerlas?'});
      if (choice === 0) { event.preventDefault(); return; }
    }
    engine.shutdown();
  });
});
app.on('window-all-closed', () => app.quit());

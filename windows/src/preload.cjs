'use strict';
const {contextBridge, ipcRenderer} = require('electron');
const call = name => (...args) => ipcRenderer.invoke(name,...args);
contextBridge.exposeInMainWorld('downloader', {
  state: call('state'), preferences: call('preferences'), clipboard: call('clipboard'), inspect: call('inspect'),
  add: call('add'), cancel: call('cancel'), retry: call('retry'), remove: call('remove'), folder: call('folder'), reveal: call('reveal'),
  clearCompleted: call('clear-completed'), openFolder: call('open-folder'),
  onChange: callback => { const listener = (_,state) => callback(state); ipcRenderer.on('state-changed',listener); return () => ipcRenderer.removeListener('state-changed',listener); }
});

import {contextBridge,ipcRenderer} from 'electron';
import type {DesktopBridge} from './bridge';
const bridge:DesktopBridge={
  state:()=>ipcRenderer.invoke('state'),
  preview:source=>ipcRenderer.invoke('preview',source),
  queue:(source,newBatch)=>ipcRenderer.invoke('queue',source,newBatch),
  stop:()=>ipcRenderer.invoke('stop'),
  variant:(id,change)=>ipcRenderer.invoke('variant',id,change),
  recipe:id=>ipcRenderer.invoke('recipe',id),
  image:(id,thumbnail)=>ipcRenderer.invoke('image',id,thumbnail),
  copyRecipe:id=>ipcRenderer.invoke('copy-recipe',id),
  openPrompt:()=>ipcRenderer.invoke('open-prompt'),
  savePrompt:(source,saveAs)=>ipcRenderer.invoke('save-prompt',source,saveAs),
  openBatch:()=>ipcRenderer.invoke('open-batch'),
  configureRenderer:()=>ipcRenderer.invoke('configure-renderer'),
  useSynthetic:()=>ipcRenderer.invoke('use-synthetic'),
  chooseOutput:()=>ipcRenderer.invoke('choose-output'),
  onState:callback=>{const listener=(_event:Electron.IpcRendererEvent,state:Parameters<typeof callback>[0])=>callback(state);ipcRenderer.on('state',listener);return()=>ipcRenderer.removeListener('state',listener);},
  onCommand:callback=>{const listener=(_event:Electron.IpcRendererEvent,command:string)=>callback(command);ipcRenderer.on('command',listener);return()=>ipcRenderer.removeListener('command',listener);}
};
contextBridge.exposeInMainWorld('storyBatch',bridge);

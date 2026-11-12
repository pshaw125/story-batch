import {contextBridge,ipcRenderer} from 'electron';
import type {DesktopBridge} from './bridge';
const bridge:DesktopBridge={
  state:()=>ipcRenderer.invoke('state'),
  preview:source=>ipcRenderer.invoke('preview',source),
  queue:(source,newBatch)=>ipcRenderer.invoke('queue',source,newBatch),
  skip:id=>ipcRenderer.invoke('skip',id),stopAfter:()=>ipcRenderer.invoke('stop-after'),reorder:(id,direction)=>ipcRenderer.invoke('reorder',id,direction),cancelQueued:id=>ipcRenderer.invoke('cancel-queued',id),
  collect:(source,kind)=>ipcRenderer.invoke('collect',source,kind),selection:(id,kind)=>ipcRenderer.invoke('selection',id,kind),favorite:id=>ipcRenderer.invoke('favorite',id),refreshFavorites:()=>ipcRenderer.invoke('refresh-favorites'),openFavoriteSource:id=>ipcRenderer.invoke('open-favorite-source',id),
  draft:()=>ipcRenderer.invoke('draft'),saveDraft:snapshot=>ipcRenderer.invoke('save-draft',snapshot),
  stop:()=>ipcRenderer.invoke('stop'),
  variant:(id,change,shortlist=false)=>ipcRenderer.invoke('variant',id,change,shortlist),
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

import { contextBridge, ipcRenderer } from 'electron';
import type { DesktopBridge } from './bridge';
const bridge: DesktopBridge = {
  preview: source => ipcRenderer.invoke('preview', source),
  runFake: source => ipcRenderer.invoke('run-fake', source),
  cancelFake: () => ipcRenderer.invoke('cancel-fake'),
  probe: () => ipcRenderer.invoke('host-probe')
};
contextBridge.exposeInMainWorld('storyBatch', bridge);

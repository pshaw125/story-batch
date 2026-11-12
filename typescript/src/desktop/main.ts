import {app,BrowserWindow,clipboard,dialog,ipcMain,Menu,nativeImage,session} from 'electron';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {mkdtempSync,rmSync} from 'node:fs';
import {access,readFile,writeFile,mkdir} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {DesktopSession} from '../node/desktop-session';
import {configuredRuntime,syntheticRuntime} from '../node/runtime';
import {MetapromptFiles} from '../node/metaprompt-files';
import {hostProbe} from '../node/host-probe';
import type {VariantChange} from '../core/desktop';
const nativeSmoke=process.argv.includes('--native-ui-smoke');
const probeMode=process.argv.includes('--host-probe')||nativeSmoke;
app.setName('Story Batch');
const probeDirectory=probeMode?mkdtempSync(join(tmpdir(),'story-batch-ui-probe-')):null;
app.setPath('userData',probeDirectory??join(app.getPath('appData'),'story-batch-typescript'));
app.commandLine.appendSwitch('disable-background-networking');
let window:BrowserWindow|null=null,desktop:DesktopSession|null=null;
const documents=new MetapromptFiles();
let readyToQuit=false;
const page=pathToFileURL(join(__dirname,'index.html')).href;
interface Settings {configPath?:string;outputRoot:string;synthetic?:boolean}
let settings:Settings={outputRoot:join(app.getPath('userData'),'Batches')};
const settingsFile=join(app.getPath('userData'),'settings.json');
function source(value:unknown):string {if(typeof value!=='string'||Buffer.byteLength(value)>2_000_000)throw new Error('Metaprompt must be text up to 2 MB.');return value;}
function id(value:unknown):string {if(typeof value!=='string'||!value||value.length>200)throw new Error('Invalid image identity.');return value;}
async function saveSettings():Promise<void>{await mkdir(app.getPath('userData'),{recursive:true});await writeFile(settingsFile,JSON.stringify(settings,null,2)+'\n');}
function command(value:string):void {window?.webContents.send('command',value);}
app.whenReady().then(async()=>{
  if(!probeMode){
    try{const saved=JSON.parse(await readFile(settingsFile,'utf8'));if(typeof saved.outputRoot!=='string'||saved.configPath!==undefined&&typeof saved.configPath!=='string'||saved.synthetic!==undefined&&typeof saved.synthetic!=='boolean')throw new Error('Invalid application settings.');settings=saved;}
    catch(error){if((error as NodeJS.ErrnoException).code!=='ENOENT')dialog.showErrorBox('Settings could not be read',String(error));}
  }
  if(nativeSmoke){if(!process.env.STORYBATCH_CONFIG||!process.env.STORYBATCH_NATIVE_OUTPUT)throw new Error('Native UI smoke requires STORYBATCH_CONFIG and STORYBATCH_NATIVE_OUTPUT.');settings.outputRoot=process.env.STORYBATCH_NATIVE_OUTPUT;}
  desktop=new DesktopSession(settings.outputRoot);
  let startupError:string|null=null;
  if(probeMode&&!nativeSmoke||settings.synthetic)await desktop.setRuntime(syntheticRuntime(probeMode?15:100));
  else{
    let config=settings.configPath??process.env.STORYBATCH_CONFIG;
    if(!config){const candidate=join(app.getAppPath(),'renderer.local.json');try{await access(candidate);config=candidate;}catch{/* No implicit renderer selection. */}}
    if(config){try{await desktop.setRuntime(await configuredRuntime(config,join(settings.outputRoot,'.attempts')));settings.configPath=config;}catch(error){startupError=String(error);}}
  }
  session.defaultSession.setPermissionRequestHandler((_web,_permission,callback)=>callback(false));
  session.defaultSession.webRequest.onBeforeRequest((details,callback)=>{
    const url=new URL(details.url);callback({cancel:!(url.protocol==='data:'&&details.resourceType==='image')&&!(url.protocol==='file:'&&details.url.startsWith(pathToFileURL(__dirname+'/').href))});
  });
  window=new BrowserWindow({width:1400,height:960,minWidth:850,minHeight:620,show:!probeMode,title:'Story Batch',
    webPreferences:{preload:join(__dirname,'preload.js'),sandbox:true,contextIsolation:true,nodeIntegration:false}});
  window.on('close',event=>{if(desktop?.state().busy){event.preventDefault();void desktop.stop().then(()=>window?.close()).catch(error=>dialog.showErrorBox('Renderer cancellation is unresolved',String(error)));}});
  window.webContents.setWindowOpenHandler(()=>({action:'deny'}));window.webContents.on('will-navigate',event=>event.preventDefault());
  desktop.subscribe(state=>{if(window&&!window.isDestroyed())window.webContents.send('state',state);});
  const handle=(name:string,action:(...args:unknown[])=>unknown)=>ipcMain.handle(name,(event,...args:unknown[])=>{
    if(event.sender!==window?.webContents||event.senderFrame!==window.webContents.mainFrame||event.senderFrame.url!==page)throw new Error('Untrusted IPC sender.');
    return action(...args);
  });
  handle('state',()=>desktop!.state());
  handle('preview',text=>desktop!.preview(source(text)));
  handle('queue',(text,newBatch)=>{if(typeof newBatch!=='boolean')throw new Error('Invalid batch mode.');return desktop!.queue(source(text),newBatch);});
  handle('stop',()=>desktop!.stop());
  handle('variant',(image,change)=>{if(!change||typeof change!=='object'||Object.keys(change).length!==1)throw new Error('Choose one variant adjustment.');return desktop!.queueVariant(id(image),change as VariantChange);});
  handle('recipe',image=>desktop!.recipe(id(image)));
  handle('copy-recipe',image=>clipboard.writeText(JSON.stringify(desktop!.recipe(id(image)),null,2)));
  handle('image',async(image,thumbnail)=>{
    if(typeof thumbnail!=='boolean')throw new Error('Invalid image size request.');
    const bytes=await desktop!.image(id(image));
    if(!thumbnail)return 'data:image/png;base64,'+Buffer.from(bytes).toString('base64');
    const decoded=nativeImage.createFromBuffer(Buffer.from(bytes));if(decoded.isEmpty())throw new Error('Image cannot be decoded.');
    const size=decoded.getSize(),scale=Math.min(1,360/Math.max(size.width,size.height));
    return decoded.resize({width:Math.max(1,Math.round(size.width*scale)),height:Math.max(1,Math.round(size.height*scale))}).toDataURL();
  });
  handle('open-prompt',async()=>{
    const selected=await dialog.showOpenDialog(window!,{title:'Open metaprompt',properties:['openFile'],filters:[{name:'Metaprompt',extensions:['txt','md']},{name:'All files',extensions:['*']}]});
    if(selected.canceled)return null;const path=selected.filePaths[0];return documents.open(path);
  });
  handle('save-prompt',async(text,saveAs)=>{
    const value=source(text);if(typeof saveAs!=='boolean')throw new Error('Invalid save mode.');
    let path=documents.path;
    if(!path||saveAs){const selected=await dialog.showSaveDialog(window!,{title:'Save metaprompt',defaultPath:path??'metaprompt.txt',filters:[{name:'Metaprompt',extensions:['txt']}]});if(selected.canceled||!selected.filePath)return null;path=selected.filePath;}
    return documents.save(value,path);
  });
  handle('open-batch',async()=>{
    const selected=await dialog.showOpenDialog(window!,{title:'Open Story Batch folder',properties:['openDirectory']});
    return selected.canceled?null:desktop!.load(selected.filePaths[0]);
  });
  handle('configure-renderer',async()=>{
    const selected=await dialog.showOpenDialog(window!,{title:'Choose renderer configuration',properties:['openFile'],filters:[{name:'Renderer configuration',extensions:['json']}]});if(selected.canceled)return null;
    const path=selected.filePaths[0],runtime=await configuredRuntime(path,join(settings.outputRoot,'.attempts'));
    await desktop!.setRuntime(runtime);settings.configPath=path;settings.synthetic=false;await saveSettings();return desktop!.state();
  });
  handle('use-synthetic',async()=>{await desktop!.setRuntime(syntheticRuntime());settings.synthetic=true;await saveSettings();return desktop!.state();});
  handle('choose-output',async()=>{
    const selected=await dialog.showOpenDialog(window!,{title:'Choose output folder',properties:['openDirectory','createDirectory']});if(selected.canceled)return null;
    if(desktop!.state().busy)throw new Error('Stop the active batch before changing output folder.');
    const folder=selected.filePaths[0];
    // Recreate native runtime with the new artifact root before committing settings.
    const runtime=settings.synthetic?syntheticRuntime():settings.configPath?await configuredRuntime(settings.configPath,join(folder,'.attempts')):null;
    await desktop!.setOutputRoot(folder);if(runtime)await desktop!.setRuntime(runtime);settings.outputRoot=folder;await saveSettings();return desktop!.state();
  });
  Menu.setApplicationMenu(Menu.buildFromTemplate([
    ...(process.platform==='darwin'?[{role:'appMenu' as const}]:[]),
    {label:'File',submenu:[{label:'Open Metaprompt…',accelerator:'CmdOrCtrl+O',click:()=>command('open')},{label:'Save',accelerator:'CmdOrCtrl+S',click:()=>command('save')},{label:'Save As…',accelerator:'CmdOrCtrl+Shift+S',click:()=>command('save-as')},{type:'separator' as const},{role:'close' as const}]},
    {label:'Edit',submenu:[{role:'undo'},{role:'redo'},{type:'separator'},{role:'cut'},{role:'copy'},{role:'paste'},{role:'selectAll'}]},
    {role:'windowMenu'}
  ]));
  window.webContents.on('render-process-gone',(_event,details)=>{if(probeMode){console.error(details);app.exit(1);}});
  await window.loadFile(join(__dirname,'index.html'));
  if(startupError)window.webContents.send('command','error:'+startupError);
  if(probeMode){
    const checks=nativeSmoke?await (await import('./probe-native')).runNativeDesktopProbe(window,desktop):await (await import('./probe')).runDesktopProbe(window,desktop,probeDirectory!);console.log(JSON.stringify({ok:true,checks,host:await hostProbe()}));
    await desktop.stop();readyToQuit=true;app.quit();
  }
}).catch(error=>{console.error(error);app.exit(1);});
if(probeMode)setTimeout(()=>{console.error('Desktop probe timed out.');void (desktop?.stop()??Promise.resolve()).finally(()=>app.exit(1));},nativeSmoke?180000:60000).unref();
app.on('window-all-closed',()=>app.quit());
app.on('before-quit',event=>{
  if(readyToQuit||!desktop?.state().busy)return;
  event.preventDefault();void desktop.stop().then(()=>{readyToQuit=true;app.quit();}).catch(error=>dialog.showErrorBox('Renderer cancellation is unresolved',String(error)));
});
app.on('will-quit',()=>{desktop?.close();if(probeDirectory)rmSync(probeDirectory,{recursive:true,force:true});});

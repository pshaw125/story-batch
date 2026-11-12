import type {DesktopState,PreviewResult} from '../../core/desktop';
import {compile} from '../../core/prompt';
import {Editor} from './editor';
import {Gallery} from './gallery';
import {Viewer} from './viewer';
const editor=new Editor();
let state:DesktopState|null=null,previewSource:string|null=null,previewConsumed=false;
const feedback=document.querySelector<HTMLElement>('#feedback')!;
function showError(message:string):void {feedback.textContent=message;feedback.hidden=false;}
function clearError():void {feedback.hidden=true;feedback.textContent='';}
const viewer=new Viewer(showError),gallery=new Gallery(id=>viewer.open(id),showError);
function tab(name:string):void {for(const button of document.querySelectorAll<HTMLButtonElement>('[data-tab]'))button.setAttribute('aria-pressed',String(button.dataset.tab===name));for(const value of ['preview','images','queue','activity'])(document.querySelector(`#${value}-pane`) as HTMLElement).hidden=value!==name;}
function validate():void {
  const text=document.querySelector<HTMLElement>('#validation')!;
  let valid=false,title:string|null=null;
  try{const compiled=compile(editor.source(),{defaultTitle:state?.title??undefined});if(!editor.prompt.value.trim())throw new Error('Enter a prompt to generate images.');valid=true;title=compiled.parameters.title;text.textContent=`${compiled.parameters.count} image(s) · ${compiled.parameters.width}×${compiled.parameters.height} · ${compiled.parameters.steps} steps`;text.classList.remove('invalid');}
  catch(e){text.textContent=String(e);text.classList.add('invalid');}
  const startsNew=!!state?.batchId&&title!==state.title;
  (document.querySelector('#preview') as HTMLButtonElement).disabled=!valid||!state?.configured;
  const queue=document.querySelector<HTMLButtonElement>('#queue')!;queue.textContent=state?.batchId&&!startsNew?'Queue More':'Generate';queue.disabled=!valid||!state?.configured||!!state.stopping||!!state.uncertain||!!(startsNew&&state.busy);
  (document.querySelector('#new-batch') as HTMLButtonElement).disabled=!valid||!state?.configured||!!state.busy||!!state.uncertain;
  const notice=document.querySelector<HTMLElement>('#preview-notice')!;
  notice.hidden=!previewSource||!previewConsumed&&previewSource===editor.source();
  notice.textContent=previewSource!==editor.source()?'Draft changed. Resolve preview to inspect the new choices.':'This preview has been queued. Resolve again to inspect the next request.';
}
function update(value:DesktopState):void {
  state=value;document.querySelector('#renderer-label')!.textContent=value.renderer+(value.renderer.startsWith('Synthetic')?' · color swatches, no inference':' · local / offline');
  document.querySelector('#batch-title')!.textContent=value.title??'No batch open';const folder=document.querySelector<HTMLElement>('#batch-folder')!;folder.textContent=value.folder??value.outputRoot;folder.title=value.folder??value.outputRoot;
  document.querySelector('#image-count')!.textContent=value.images.filter(i=>i.status==='completed').length.toString();document.querySelector('#queue-count')!.textContent=value.images.filter(i=>['queued','running','unknown'].includes(i.status)).length.toString();
  (document.querySelector('#stop') as HTMLButtonElement).disabled=!value.busy||value.stopping;(document.querySelector('#stop') as HTMLButtonElement).textContent=value.stopping?'Stopping…':'Stop Batch';
  for(const id of ['configure','synthetic','output-folder','open-batch'])(document.querySelector('#'+id) as HTMLButtonElement).disabled=value.busy;
  gallery.update(value);viewer.update(value);
  const queue=document.querySelector('#queue-list')!;queue.replaceChildren();
  for(const item of value.images.filter(i=>['queued','running','unknown'].includes(i.status))){const row=document.createElement('div');row.className='queue-row';const name=document.createElement('strong');name.textContent=item.filename;const meta=document.createElement('div');meta.className='image-params';meta.textContent=`${item.width}×${item.height} · Seed ${item.seed} · Shift ${item.shift} · Steps ${item.steps} · ${item.status}`;row.append(name,meta);queue.append(row);}
  if(!queue.childElementCount){const empty=document.createElement('p');empty.className='empty';empty.textContent='No queued work.';queue.append(empty);}
  document.querySelector('#activity-log')!.textContent=value.activity.join('\n');
  const current=value.images.find(i=>i.id===value.activeId),progress=document.querySelector<HTMLProgressElement>('#progress')!;
  progress.max=value.progress?.total??1;progress.value=value.progress?.completed??0;
  document.querySelector('#status-text')!.textContent=current&&value.busy?`${current.filename}${value.progress?` · ${value.progress.completed}/${value.progress.total}`:''}`:`${value.stopping?'Stopping':value.busy?'Preparing':value.uncertain?'Renderer status unresolved':'Ready'} · ${value.images.filter(i=>i.status==='completed').length} completed`;
  document.querySelector('#active-params')!.textContent=current&&value.busy?`Seed ${current.seed} · Shift ${current.shift} · Steps ${current.steps}`:'';
  if(value.error)showError(value.error);validate();
}
function showPreview(result:PreviewResult):void {
  const root=document.querySelector('#preview-content')!;root.replaceChildren();
  const note=document.createElement('p');note.className='muted';note.textContent=`${result.title} · ${result.startsNewBatch?'New batch':'Continue current batch'} · ${result.images.length} resolved preview(s)`;root.append(note);
  for(const image of result.images){const card=document.createElement('article');card.className='preview-card';const label=document.createElement('div');label.className='preview-heading';label.textContent=`#${image.number} · ${image.width}×${image.height} · Seed ${image.seed} · Shift ${image.shift} · Steps ${image.steps}`;const prompt=document.createElement('pre');prompt.textContent=image.prompt;card.append(label,prompt);root.append(card);}
}
async function action(task:()=>Promise<void>):Promise<void>{clearError();try{await task();}catch(e){showError(String(e));}}
function resetPreview():void {previewSource=null;previewConsumed=false;const p=document.createElement('p');p.className='empty';p.textContent='Resolve a preview to inspect the exact prompts and parameters before queueing.';document.querySelector('#preview-content')!.replaceChildren(p);}
async function open():Promise<void>{const result=await window.storyBatch.openPrompt();if(result){editor.load(result.source);resetPreview();validate();}}
async function save(saveAs=false):Promise<void>{await window.storyBatch.savePrompt(editor.source(),saveAs);}
editor.onChange(()=>{clearError();validate();});
for(const button of document.querySelectorAll<HTMLButtonElement>('[data-tab]'))button.addEventListener('click',()=>tab(button.dataset.tab!));
document.querySelector('#preview')!.addEventListener('click',()=>void action(async()=>{const source=editor.source(),result=await window.storyBatch.preview(source);if(source!==editor.source())return;previewSource=source;previewConsumed=false;showPreview(result);validate();tab('preview');}));
for(const [id,newBatch] of [['queue',false],['new-batch',true]] as const)document.querySelector('#'+id)!.addEventListener('click',()=>void action(async()=>{update(await window.storyBatch.queue(editor.source(),newBatch));previewConsumed=true;validate();tab('images');}));
document.querySelector('#stop')!.addEventListener('click',()=>void action(async()=>update(await window.storyBatch.stop())));
document.querySelector('#configure')!.addEventListener('click',()=>void action(async()=>{const result=await window.storyBatch.configureRenderer();if(result)update(result);}));
document.querySelector('#synthetic')!.addEventListener('click',()=>void action(async()=>update(await window.storyBatch.useSynthetic())));
document.querySelector('#output-folder')!.addEventListener('click',()=>void action(async()=>{const result=await window.storyBatch.chooseOutput();if(result)update(result);}));
document.querySelector('#open-prompt')!.addEventListener('click',()=>void action(open));document.querySelector('#save-prompt')!.addEventListener('click',()=>void action(()=>save()));document.querySelector('#save-as')!.addEventListener('click',()=>void action(()=>save(true)));
document.querySelector('#open-batch')!.addEventListener('click',()=>void action(async()=>{const result=await window.storyBatch.openBatch();if(result){editor.load(result.source);resetPreview();update(result.state);tab('images');}}));
window.storyBatch.onCommand(command=>{if(command.startsWith('error:'))showError(command.slice(6));else if(command==='open')void action(open);else if(command==='save')void action(()=>save());else if(command==='save-as')void action(()=>save(true));});
window.storyBatch.onState(update);void window.storyBatch.state().then(update).catch(e=>showError(String(e)));

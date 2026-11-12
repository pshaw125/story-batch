import type {DesktopState,PreviewResult} from '../../core/desktop';
import {compile} from '../../core/prompt';
import {Editor} from './editor';
import {Gallery} from './gallery';
import {Viewer} from './viewer';
import {RenderTools,importControls} from './render-tools';
import {Find} from './find';
import type {GalleryScope,ImageSort} from '../../core/gallery';
import {params} from './gallery';
const editor=new Editor();
let state:DesktopState|null=null,previewSource:string|null=null,previewConsumed=false;
const feedback=document.querySelector<HTMLElement>('#feedback')!;
function showError(message:string):void {feedback.textContent=message;feedback.hidden=false;}
function clearError():void {feedback.hidden=true;feedback.textContent='';}
let scope:GalleryScope='images',sort:ImageSort='seeded';
const find=new Find(editor);
function persist():void{if(state)void window.storyBatch.saveDraft(window.storyBatchDraft!()).catch(e=>showError(String(e)));}
window.storyBatchDraft=()=>({source:editor.source(),lastBatch:state?.folder??null,scope,sort,tools:state?.tools});
function imageAction(id:string,kind:'shortlisted'|'favorite'|'rejected'):void{void action(async()=>update(await(kind==='favorite'?window.storyBatch.favorite(id):window.storyBatch.selection(id,kind))));}
function setSort(value:ImageSort):void{sort=value;if(state)update(state);persist();}
const tools=new RenderTools(update,showError,()=>{if(state?.tools?.canvas?.mode==='append'){editor.replacePrompt('');}document.querySelector<HTMLDetailsElement>('#render-tools')!.open=true;validate();persist();});
const viewer=new Viewer(showError,imageAction,setSort,id=>void action(async()=>{const result=await window.storyBatch.openFavoriteSource(id);editor.load(result.source);resetPreview();update(result.state);tab('images');viewer.open(result.imageId);}),id=>void action(async()=>{update(await window.storyBatch.useCanvas(id));if(state?.tools?.canvas?.mode==='append')editor.replacePrompt('');document.querySelector<HTMLDetailsElement>('#render-tools')!.open=true;validate();persist();}));
const gallery=new Gallery(id=>viewer.open(id),showError,imageAction);
function tab(name:string):void {
  const collection=['images','shortlist','favorites','rejected'].includes(name);
  if(collection)scope=name as GalleryScope;
  for(const button of document.querySelectorAll<HTMLButtonElement>('[data-tab]'))button.setAttribute('aria-pressed',String(button.dataset.tab===name));
  for(const value of ['preview','images','queue','activity'])(document.querySelector(`#${value}-pane`) as HTMLElement).hidden=value!==(collection?'images':name);
  (document.querySelector('#refresh-favorites') as HTMLElement).hidden=scope!=='favorites';
  if(state){gallery.update(state,scope,sort);viewer.update(state,scope,sort);}persist();
  if(name==='favorites')void window.storyBatch.refreshFavorites().then(update).catch(e=>showError(String(e)));
}
function validate():void {
  const text=document.querySelector<HTMLElement>('#validation')!;
  let valid=false,title:string|null=null;
  try{const compiled=compile(editor.source(),{defaultTitle:state?.title??undefined});if(!editor.prompt.value.trim()&&!(state?.tools?.canvas?.mode==='append'&&state.tools.canvas.source.prompt.trim()))throw new Error('Enter a prompt to generate images.');valid=true;title=compiled.parameters.title;text.textContent=`${compiled.parameters.count} image(s) · ${compiled.parameters.width}×${compiled.parameters.height} · ${compiled.parameters.steps} steps`;text.classList.remove('invalid');}
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
  if(state&&JSON.stringify(state.tools)!==JSON.stringify(value.tools))resetPreview();state=value;document.querySelector('#renderer-label')!.textContent=value.renderer+(value.renderer.startsWith('Synthetic')?' · color swatches, no inference':' · local / offline');
  document.querySelector('#batch-title')!.textContent=value.title??'No batch open';const folder=document.querySelector<HTMLElement>('#batch-folder')!;folder.textContent=value.folder??value.outputRoot;folder.title=value.folder??value.outputRoot;
  document.querySelector('#image-count')!.textContent=value.images.filter(i=>i.status==='completed').length.toString();document.querySelector('#queue-count')!.textContent=value.images.filter(i=>['queued','running','unknown'].includes(i.status)).length.toString();
  (document.querySelector('#stop') as HTMLButtonElement).disabled=!value.busy||value.stopping;(document.querySelector('#stop') as HTMLButtonElement).textContent=value.stopping?'Stopping…':'Stop Batch';
  for(const id of ['configure','synthetic','output-folder','open-batch','import-batch'])(document.querySelector('#'+id) as HTMLButtonElement).disabled=value.busy;
  tools.render(value);gallery.update(value,scope,sort);viewer.update(value,scope,sort);
  (document.querySelector('#gallery-sort') as HTMLSelectElement).value=sort;
  (document.querySelector('#stop-after') as HTMLButtonElement).disabled=!value.busy||value.stopping;
  for(const id of ['collect-seeds','collect-shifts'])(document.querySelector('#'+id) as HTMLButtonElement).disabled=value.busy||!value.lastRunCount;
  const queue=document.querySelector('#queue-list')!;queue.replaceChildren();
  const queuedIds=[...(value.activeId?[value.activeId]:[]),...value.waiting];
  for(const id of [...new Set(queuedIds)]){const item=value.images.find(i=>i.id===id);if(!item)continue;const row=document.createElement('div');row.className='queue-row';row.dataset.id=id;const name=document.createElement('strong');name.textContent=item.filename;const meta=document.createElement('div');meta.className='image-params';meta.textContent=params(item)+' · '+item.status;row.append(name,meta);
    const controls=document.createElement('div');controls.className='toolbar';const add=(label:string,title:string,run:()=>Promise<DesktopState>,disabled=false)=>{const b=document.createElement('button');b.textContent=label;b.title=title;b.disabled=disabled||value.stopping;b.addEventListener('click',()=>void action(async()=>update(await run())));controls.append(b);};
    if(id===value.activeId)add('Skip current','Cancel only this image',()=>window.storyBatch.skip(id),!['queued','running'].includes(item.status));
    else{const index=value.waiting.indexOf(id);add('↑','Move up',()=>window.storyBatch.reorder(id,'up'),index===0);add('↓','Move down',()=>window.storyBatch.reorder(id,'down'),index===value.waiting.length-1);add('⏭','Run next',()=>window.storyBatch.reorder(id,'next'),index===0);add('Cancel','Remove waiting image',()=>window.storyBatch.cancelQueued(id));}
    row.append(controls);queue.append(row);
  }
  if(!queue.childElementCount){const empty=document.createElement('p');empty.className='empty';empty.textContent='No queued work.';queue.append(empty);}
  document.querySelector('#activity-log')!.textContent=value.activity.join('\n');
  const current=value.images.find(i=>i.id===value.activeId),progress=document.querySelector<HTMLProgressElement>('#progress')!;
  progress.max=value.progress?.total??1;progress.value=value.progress?.completed??0;
  document.querySelector('#status-text')!.textContent=current&&value.busy?`${current.filename}${value.progress?` · ${value.progress.completed}/${value.progress.total}`:''}`:`${value.stopping?'Stopping':value.busy?'Preparing':value.uncertain?'Renderer status unresolved':'Ready'} · ${value.images.filter(i=>i.status==='completed').length} completed`;
  document.querySelector('#active-params')!.textContent=current&&value.busy?`Seed ${current.seed} · Shift ${current.shift} · Steps ${current.steps}`:'';
  if(value.error)showError(value.error);validate();persist();
}
function showPreview(result:PreviewResult):void {
  const root=document.querySelector('#preview-content')!;root.replaceChildren();
  const note=document.createElement('p');note.className='muted';note.textContent=`${result.title} · ${result.startsNewBatch?'New batch':'Continue current batch'} · ${result.images.length} resolved preview(s)`;root.append(note);
  for(const image of result.images){const card=document.createElement('article');card.className='preview-card';const label=document.createElement('div');label.className='preview-heading';label.textContent=`#${image.number} · ${image.width}×${image.height} · Seed ${image.seed} · Shift ${image.shift} · Steps ${image.steps}`;const prompt=document.createElement('pre');prompt.textContent=image.prompt;card.append(label,prompt);root.append(card);}
}
async function action(task:()=>Promise<void>):Promise<void>{clearError();try{await task();}catch(e){showError(String(e));}}
function resetPreview():void {previewSource=null;previewConsumed=false;const p=document.createElement('p');p.className='empty';p.textContent='Resolve a preview to inspect the exact prompts and parameters before queueing.';document.querySelector('#preview-content')!.replaceChildren(p);}
async function open():Promise<void>{const result=await window.storyBatch.openPrompt();if(result){editor.load(result.source);resetPreview();validate();find.refresh();persist();}}
async function save(saveAs=false):Promise<void>{await window.storyBatch.savePrompt(editor.source(),saveAs);}
editor.onChange(()=>{clearError();validate();persist();});
for(const button of document.querySelectorAll<HTMLButtonElement>('[data-tab]'))button.addEventListener('click',()=>tab(button.dataset.tab!));
document.querySelector('#preview')!.addEventListener('click',()=>void action(async()=>{const source=editor.source(),result=await window.storyBatch.preview(source);if(source!==editor.source())return;previewSource=source;previewConsumed=false;showPreview(result);validate();tab('preview');}));
for(const [id,newBatch] of [['queue',false],['new-batch',true]] as const)document.querySelector('#'+id)!.addEventListener('click',()=>void action(async()=>{update(await window.storyBatch.queue(editor.source(),newBatch));previewConsumed=true;validate();tab('images');}));
document.querySelector('#stop')!.addEventListener('click',()=>void action(async()=>update(await window.storyBatch.stop())));
document.querySelector('#configure')!.addEventListener('click',()=>void action(async()=>{const result=await window.storyBatch.configureRenderer();if(result)update(result);}));
document.querySelector('#synthetic')!.addEventListener('click',()=>void action(async()=>update(await window.storyBatch.useSynthetic())));
document.querySelector('#output-folder')!.addEventListener('click',()=>void action(async()=>{const result=await window.storyBatch.chooseOutput();if(result)update(result);}));
document.querySelector('#open-prompt')!.addEventListener('click',()=>void action(open));document.querySelector('#save-prompt')!.addEventListener('click',()=>void action(()=>save()));document.querySelector('#save-as')!.addEventListener('click',()=>void action(()=>save(true)));
document.querySelector('#open-batch')!.addEventListener('click',()=>void action(async()=>{const result=await window.storyBatch.openBatch();if(result){editor.load(result.source);resetPreview();update(result.state);tab('images');}}));
window.storyBatch.onCommand(command=>{if(command==='find')find.open();else if(command==='find-next')find.next(1);else if(command==='find-previous')find.next(-1);else if(command.startsWith('error:'))showError(command.slice(6));else if(command==='open')void action(open);else if(command==='save')void action(()=>save());else if(command==='save-as')void action(()=>save(true));});
window.storyBatch.onState(update);void Promise.all([window.storyBatch.state(),window.storyBatch.draft()]).then(([value,draft])=>{editor.load(draft.source);scope=draft.scope;sort=draft.sort;update(value);tab(scope);find.refresh();}).catch(e=>showError(String(e)));
window.addEventListener('keydown',e=>{if((e.metaKey||e.ctrlKey)&&!e.altKey&&e.key.toLowerCase()==='f'){e.preventDefault();find.open();}else if((e.metaKey||e.ctrlKey)&&!e.altKey&&e.key.toLowerCase()==='g'){e.preventDefault();find.next(e.shiftKey?-1:1);}});

document.querySelector('#stop-after')!.addEventListener('click',()=>void action(async()=>update(await window.storyBatch.stopAfter())));
document.querySelector('#gallery-sort')!.addEventListener('change',e=>setSort((e.target as HTMLSelectElement).value as ImageSort));
document.querySelector('#refresh-favorites')!.addEventListener('click',()=>void action(async()=>update(await window.storyBatch.refreshFavorites())));
for(const [id,kind] of [['collect-seeds','seeds'],['collect-shifts','shift']] as const)document.querySelector('#'+id)!.addEventListener('click',()=>void action(async()=>{const before=editor.source(),result=await window.storyBatch.collect(before,kind);if(before!==editor.source())throw new Error('Draft changed during collection; collect again.');editor.replaceParameters(result);find.refresh();validate();persist();}));

importControls((source,value)=>{editor.load(source);resetPreview();update(value);find.refresh();tab('images');},showError);

import type {DesktopState,VariantChange} from '../../core/desktop';
import {SeedBoundaryGuard,retainViewport} from '../../core/inspection';
import {galleryImages,GalleryScope,ImageSort} from '../../core/gallery';
import {params} from './gallery';
import {imageActions} from './actions';
import {ImageInspection} from './image-viewport';
import {viewerKey} from './viewer-input';
export class Viewer {
  private dialog=document.querySelector<HTMLDialogElement>('#viewer')!;
  private recipeDialog=document.querySelector<HTMLDialogElement>('#recipe-dialog')!;
  private image=document.querySelector<HTMLImageElement>('#viewer-image')!;
  private pane=document.querySelector<HTMLElement>('.viewer-image-pane')!;
  private state:DesktopState|null=null;
  private selected:string|null=null;
  private generation=0;
  private scope:GalleryScope='images';
  private sort:ImageSort='seeded';
  private boundary=new SeedBoundaryGuard();
  private inspection:ImageInspection;
  private imageOnly=false;
  private nativeFullscreen=false;
  private fullscreenTransition=false;
  private fullscreenTarget=false;
  private fullscreenRequest=0;
  constructor(private error:(message:string)=>void,private action:(id:string,action:'shortlisted'|'favorite'|'rejected')=>void,private changeSort:(sort:ImageSort)=>void,private openSource:(id:string)=>void,private useCanvas:(id:string)=>void){
    this.inspection=new ImageInspection(this.pane,this.image,()=>this.inspectionChanged(),()=>this.dialog.open&&!this.recipeDialog.open);
    document.querySelector('#close-viewer')!.addEventListener('click',()=>this.close());
    document.querySelector('#previous')!.addEventListener('click',()=>this.move(-1));
    document.querySelector('#next')!.addEventListener('click',()=>this.move(1));
    document.querySelector('#zoom-in')!.addEventListener('click',()=>this.inspection.zoom(1.25));
    document.querySelector('#zoom-out')!.addEventListener('click',()=>this.inspection.zoom(1/1.25));
    document.querySelector('#fit-image')!.addEventListener('click',()=>this.inspection.reset());
    document.querySelector('#fullscreen')!.addEventListener('click',()=>void this.setFullscreen(!this.imageOnly));
    this.dialog.addEventListener('cancel',event=>{event.preventDefault();if(this.imageOnly||this.fullscreenTransition)void this.setFullscreen(false);else this.close();});
    this.dialog.addEventListener('close',()=>{
      this.generation++;this.boundary.clear();this.inspection.reset();
      if(this.imageOnly||this.fullscreenTransition)void this.setFullscreen(false);
    });
    window.storyBatch.onFullscreen(flag=>{
      this.nativeFullscreen=flag;
      if(this.dialog.open&&(!this.fullscreenTransition||flag===this.fullscreenTarget))this.applyFullscreen(flag);
    });
    void window.storyBatch.fullscreenState().then(flag=>{this.nativeFullscreen=flag;if(this.dialog.open&&!this.fullscreenTransition)this.applyFullscreen(flag);}).catch(e=>this.feedback(String(e)));
    document.querySelector('#viewer-canvas')!.addEventListener('click',()=>{if(this.selected){this.useCanvas(this.selected);this.close();}});
    document.querySelector('#native-copy')!.addEventListener('click',()=>{if(this.selected)void window.storyBatch.nativeTextCopy(this.selected).then(()=>this.feedback('Current-setup text render queued.')).catch(e=>this.feedback(String(e)));});
    document.querySelector('#recipe')!.addEventListener('click',()=>void this.showRecipe());
    document.querySelector('#close-recipe')!.addEventListener('click',()=>this.recipeDialog.close());
    document.querySelector('#copy-recipe')!.addEventListener('click',()=>{if(this.selected)void window.storyBatch.copyRecipe(this.selected).catch(e=>this.feedback(String(e)));});
    document.querySelector('#viewer-sort')!.addEventListener('change',event=>{this.changeSort((event.target as HTMLSelectElement).value as ImageSort);(event.target as HTMLSelectElement).blur();});
    document.querySelector('#open-source')!.addEventListener('click',()=>{if(this.selected)this.openSource(this.selected);});
    const input=document.querySelector<HTMLInputElement>('#absolute-shift')!,queue=()=>void this.variant({shift:input.value});
    document.querySelector('#set-shift')!.addEventListener('click',queue);
    input.addEventListener('keydown',e=>{if(e.key==='Enter'){e.preventDefault();queue();}});
    document.addEventListener('pointerdown',e=>{if(this.dialog.open&&document.activeElement===input&&e.target!==input)input.blur();});
    document.addEventListener('keydown',e=>this.key(e),{capture:true});
  }
  private feedback(message:string):void{document.querySelector('#viewer-feedback')!.textContent=message;}
  private editable(target:EventTarget|null):boolean{return target instanceof HTMLElement&&(target.isContentEditable||!!target.closest('input,textarea,select'));}
  private key(event:KeyboardEvent):void{
    if(!this.dialog.open||this.recipeDialog.open||this.editable(event.target)||this.editable(document.activeElement))return;
    const key=viewerKey(event);if(!key)return;
    if(key==='space'&&event.target instanceof HTMLButtonElement)return;
    event.preventDefault();
    if(key==='previous'||key==='next')this.move(key==='previous'?-1:1,event.repeat);
    else if(key==='zoom-in'||key==='zoom-out')this.inspection.zoom(key==='zoom-in'?1.25:1/1.25);
    else if(key==='fit')this.inspection.reset();
    else if(key==='fullscreen'&&!event.repeat&&!this.fullscreenTransition)void this.setFullscreen(!this.imageOnly);
    else if(key==='escape'&&!event.repeat){if(this.imageOnly||this.fullscreenTransition)void this.setFullscreen(false);else this.close();}
  }
  private close():void{if(this.recipeDialog.open)this.recipeDialog.close();this.dialog.close();}
  private applyFullscreen(flag:boolean):void{
    this.imageOnly=flag;this.dialog.classList.toggle('image-only',flag);
    const button=document.querySelector<HTMLButtonElement>('#fullscreen')!;button.textContent=flag?'Exit fullscreen':'Fullscreen';button.setAttribute('aria-pressed',String(flag));
    this.inspection.measure();this.notices();if(flag&&this.dialog.open)this.pane.focus({preventScroll:true});
  }
  private async setFullscreen(flag:boolean):Promise<void>{
    if(flag&&!this.dialog.open)return;
    const request=++this.fullscreenRequest;this.fullscreenTarget=flag;this.fullscreenTransition=true;this.applyFullscreen(flag);
    (document.querySelector('#fullscreen') as HTMLButtonElement).disabled=true;
    try{
      const actual=await window.storyBatch.fullscreen(flag);this.nativeFullscreen=actual;
      if(request===this.fullscreenRequest)this.applyFullscreen(this.dialog.open&&actual);
    }catch(error){
      if(request===this.fullscreenRequest){this.applyFullscreen(this.dialog.open&&this.nativeFullscreen);this.feedback(String(error));this.error(String(error));}
    }finally{if(request===this.fullscreenRequest){this.fullscreenTransition=false;(document.querySelector('#fullscreen') as HTMLButtonElement).disabled=false;}}
  }
  private inspectionChanged():void{
    if(!this.inspection.viewport.zoomed)this.boundary.clear();
    document.querySelector('#zoom-level')!.textContent=this.inspection.viewport.zoomed?`${Math.round(this.inspection.viewport.zoom*100)}% of fit`:'Fit';this.notices();
  }
  private notices():void{
    const notice=this.boundary.notice;
    const normal=document.querySelector<HTMLElement>('#seed-notice')!,fullscreen=document.querySelector<HTMLElement>('#fullscreen-seed-notice')!;
    normal.textContent=fullscreen.textContent=notice??'';normal.hidden=!notice||this.imageOnly;fullscreen.hidden=!notice||!this.imageOnly;
  }
  update(state:DesktopState,scope:GalleryScope,sort:ImageSort):void{
    const oldIds=this.ids(),oldIndex=oldIds.indexOf(this.selected!);
    if(this.scope!==scope||this.sort!==sort)this.boundary.clear();
    this.state=state;this.scope=scope;this.sort=sort;
    if(state.error)this.feedback(state.error);
    if(this.dialog.open&&this.selected&&!this.ids().includes(this.selected)){
      const ids=this.ids();if(ids.length)this.open(ids[Math.min(Math.max(oldIndex,0),ids.length-1)]);else{this.close();this.selected=null;}
    }
    if(this.boundary.pending){const ids=this.ids(),index=ids.indexOf(this.selected!);if(ids[index+this.boundary.pending.direction]!==this.boundary.pending.to)this.boundary.clear();}
    if(this.dialog.open)this.controls();
  }
  open(id:string):void{
    const previous=this.dialog.open?this.item()??null:null,next=[...(this.state?.images??[]),...(this.state?.favorites??[])].find(i=>i.id===id);if(!next)return;
    if(!retainViewport(previous,next))this.inspection.reset();this.boundary.clear();this.selected=id;
    if(!this.dialog.open){this.dialog.showModal();this.applyFullscreen(this.nativeFullscreen);}
    if(next.width!==null&&next.height!==null)this.inspection.dimensions(next.width,next.height);
    this.inspection.measure();this.controls();void this.loadImage();
  }
  private ids():string[]{return this.state?galleryImages(this.state,this.scope,this.sort).filter(i=>i.status==='completed').map(i=>i.id):[];}
  private item(){return [...(this.state?.images??[]),...(this.state?.favorites??[])].find(i=>i.id===this.selected);}
  private move(direction:-1|1,repeat=false):void{
    const ids=this.ids(),index=ids.indexOf(this.selected!)+direction;
    if(index<0||index>=ids.length){this.boundary.clear();this.notices();return;}
    const from=this.item(),to=[...(this.state?.images??[]),...(this.state?.favorites??[])].find(i=>i.id===ids[index]);
    if(!from||!to)return;
    if(this.boundary.allow(from.id,to.id,from.seed,to.seed,this.inspection.viewport.zoomed,direction,repeat))this.open(to.id);else this.notices();
  }
  private controls():void{
    const item=this.item();if(!item)return;const ids=this.ids(),index=ids.indexOf(item.id);
    document.querySelector('#viewer-index')!.textContent=`${index+1} / ${ids.length}`;document.querySelector('#viewer-name')!.textContent=item.filename;
    document.querySelector('#viewer-params')!.textContent=params(item)+(item.elapsedMs===null?'':` · ${(item.elapsedMs/1000).toFixed(2)}s`);
    (document.querySelector('#previous') as HTMLButtonElement).disabled=index<=0;(document.querySelector('#next') as HTMLButtonElement).disabled=index>=ids.length-1;
    (document.querySelector('#viewer-sort') as HTMLSelectElement).value=this.sort;(document.querySelector('#recipe') as HTMLButtonElement).disabled=!item.hasRecipe;
    const source=document.querySelector<HTMLButtonElement>('#open-source')!;source.hidden=!item.hasSource||item.inBatch;source.disabled=!!this.state?.busy;
    document.querySelector('#viewer-actions')!.replaceChildren(imageActions(item,action=>this.action(item.id,action)));
    (document.querySelector('#native-copy') as HTMLButtonElement).disabled=!item.inBatch||!item.hasRecipe||!this.state?.configured||!!this.state?.stopping||!!this.state?.uncertain;
    const steps=document.querySelector('#step-buttons')!;steps.replaceChildren();
    for(const n of item.steps===null?[]:[4,6,7,8].filter(n=>n>item.steps!)){const b=document.createElement('button');b.textContent=String(n);b.dataset.step=String(n);b.addEventListener('click',()=>void this.variant({steps:n}));steps.append(b);}
    const shifts=document.querySelector('#shift-buttons')!;shifts.replaceChildren();
    for(const delta of ['-1','-0.25','-0.1','-0.05','+0.05','+0.1','+0.25','+1']){const b=document.createElement('button');b.textContent=delta;b.addEventListener('click',()=>void this.variant({delta}));shifts.append(b);}
    for(const b of this.dialog.querySelectorAll<HTMLButtonElement>('.variant-controls button')){b.disabled=!!item.historical||!item.inBatch||!item.hasRecipe||!this.state?.configured||!!this.state?.stopping||!!this.state?.uncertain;b.title=item.inBatch?'Queue a source-preserving variant':'Open the source batch to create variants';}
    this.notices();
  }
  private async loadImage():Promise<void>{
    const id=this.selected,version=++this.generation;this.image.hidden=true;this.image.removeAttribute('src');if(!id)return;
    try{const url=await window.storyBatch.image(id,false);if(this.selected!==id||version!==this.generation)return;
      this.image.onload=()=>{if(this.selected===id&&version===this.generation&&this.image.currentSrc===url){this.inspection.dimensions(this.image.naturalWidth,this.image.naturalHeight);this.image.hidden=false;}};
      this.image.onerror=()=>{if(this.selected===id&&version===this.generation)this.feedback('Image could not be decoded.');};
      this.image.src=url;this.image.alt=this.item()?.filename??'Generated image';
    }catch(e){this.feedback(String(e));this.error(String(e));}
  }
  private async showRecipe():Promise<void>{if(!this.selected)return;const id=this.selected;try{const snapshot=await window.storyBatch.recipe(id);if(this.selected!==id)return;document.querySelector('#recipe-content')!.textContent=`${snapshot.job.prompt}\n\n${JSON.stringify({parameters:snapshot.job,environment:snapshot.environment},null,2)}`;if(!this.recipeDialog.open)this.recipeDialog.showModal();}catch(e){this.feedback(String(e));}}
  private async variant(change:VariantChange):Promise<void>{if(!this.selected)return;try{await window.storyBatch.variant(this.selected,change,this.scope==='shortlist');this.feedback('Variant queued.');(document.querySelector('#absolute-shift') as HTMLInputElement).blur();}catch(e){this.feedback(String(e));}}
}

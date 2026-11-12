import type {DesktopState,VariantChange} from '../../core/desktop';
import {galleryImages,GalleryScope,ImageSort} from '../../core/gallery';
import {params} from './gallery';
import {imageActions} from './actions';
export class Viewer {
  private dialog=document.querySelector<HTMLDialogElement>('#viewer')!;private recipeDialog=document.querySelector<HTMLDialogElement>('#recipe-dialog')!;private image=document.querySelector<HTMLImageElement>('#viewer-image')!;
  private state:DesktopState|null=null;private selected:string|null=null;private generation=0;private scope:GalleryScope='images';private sort:ImageSort='seeded';
  constructor(private error:(message:string)=>void,private action:(id:string,action:'shortlisted'|'favorite'|'rejected')=>void,private changeSort:(sort:ImageSort)=>void,private openSource:(id:string)=>void){
    document.querySelector('#close-viewer')!.addEventListener('click',()=>this.dialog.close());document.querySelector('#previous')!.addEventListener('click',()=>this.move(-1));document.querySelector('#next')!.addEventListener('click',()=>this.move(1));
    document.querySelector('#recipe')!.addEventListener('click',()=>void this.showRecipe());document.querySelector('#close-recipe')!.addEventListener('click',()=>this.recipeDialog.close());
    document.querySelector('#copy-recipe')!.addEventListener('click',()=>{if(this.selected)void window.storyBatch.copyRecipe(this.selected).catch(e=>this.error(String(e)));});
    document.querySelector('#viewer-sort')!.addEventListener('change',event=>{this.changeSort((event.target as HTMLSelectElement).value as ImageSort);(event.target as HTMLSelectElement).blur();});
    document.querySelector('#open-source')!.addEventListener('click',()=>{if(this.selected)this.openSource(this.selected);});
    const input=document.querySelector<HTMLInputElement>('#absolute-shift')!,queue=()=>void this.variant({shift:input.value});document.querySelector('#set-shift')!.addEventListener('click',queue);input.addEventListener('keydown',e=>{if(e.key==='Enter'){e.preventDefault();queue();}});
    document.addEventListener('pointerdown',e=>{if(this.dialog.open&&document.activeElement===input&&e.target!==input)input.blur();});
    document.addEventListener('keydown',e=>{if(!this.dialog.open||this.recipeDialog.open||e.altKey||e.ctrlKey||e.metaKey||e.target instanceof HTMLInputElement||e.target instanceof HTMLTextAreaElement||e.target instanceof HTMLSelectElement)return;if(e.key==='ArrowLeft'||e.key==='ArrowRight'){e.preventDefault();this.move(e.key==='ArrowLeft'?-1:1);}});
  }
  update(state:DesktopState,scope:GalleryScope,sort:ImageSort):void{
    const oldIds=this.ids(),oldIndex=oldIds.indexOf(this.selected!);this.state=state;this.scope=scope;this.sort=sort;
    if(state.error)document.querySelector('#viewer-feedback')!.textContent=state.error;
    if(this.dialog.open&&this.selected&&!this.ids().includes(this.selected)){
      const ids=this.ids();if(ids.length)this.open(ids[Math.min(Math.max(oldIndex,0),ids.length-1)]);else{this.dialog.close();this.selected=null;}
    }
    if(this.dialog.open)this.controls();
  }
  open(id:string):void{this.selected=id;if(!this.dialog.open)this.dialog.showModal();this.controls();void this.loadImage();}
  private ids():string[]{return this.state?galleryImages(this.state,this.scope,this.sort).filter(i=>i.status==='completed').map(i=>i.id):[];}
  private item(){return [...(this.state?.images??[]),...(this.state?.favorites??[])].find(i=>i.id===this.selected);}
  private move(delta:number):void{const ids=this.ids(),index=ids.indexOf(this.selected!)+delta;if(index>=0&&index<ids.length)this.open(ids[index]);}
  private controls():void{
    const item=this.item();if(!item)return;const ids=this.ids(),index=ids.indexOf(item.id);
    document.querySelector('#viewer-index')!.textContent=`${index+1} / ${ids.length}`;document.querySelector('#viewer-name')!.textContent=item.filename;document.querySelector('#viewer-params')!.textContent=params(item)+(item.elapsedMs===null?'':` · ${(item.elapsedMs/1000).toFixed(2)}s`);
    (document.querySelector('#previous') as HTMLButtonElement).disabled=index<=0;(document.querySelector('#next') as HTMLButtonElement).disabled=index>=ids.length-1;
    (document.querySelector('#viewer-sort') as HTMLSelectElement).value=this.sort;
    (document.querySelector('#recipe') as HTMLButtonElement).disabled=!item.hasRecipe;
    const source=document.querySelector<HTMLButtonElement>('#open-source')!;source.hidden=!item.hasSource||item.inBatch;source.disabled=!!this.state?.busy;
    document.querySelector('#viewer-actions')!.replaceChildren(imageActions(item,action=>this.action(item.id,action)));
    const steps=document.querySelector('#step-buttons')!;steps.replaceChildren();for(const n of item.steps===null?[]:[4,6,7,8].filter(n=>n>item.steps!)){const b=document.createElement('button');b.textContent=String(n);b.dataset.step=String(n);b.addEventListener('click',()=>void this.variant({steps:n}));steps.append(b);}
    const shifts=document.querySelector('#shift-buttons')!;shifts.replaceChildren();for(const delta of ['-1','-0.25','-0.1','-0.05','+0.05','+0.1','+0.25','+1']){const b=document.createElement('button');b.textContent=delta;b.addEventListener('click',()=>void this.variant({delta}));shifts.append(b);}
    for(const b of this.dialog.querySelectorAll<HTMLButtonElement>('.variant-controls button')){b.disabled=!item.inBatch||!item.hasRecipe||!this.state?.configured||!!this.state?.stopping||!!this.state?.uncertain;b.title=item.inBatch?'Queue a source-preserving variant':'Open the source batch to create variants';}
  }
  private async loadImage():Promise<void>{const id=this.selected,version=++this.generation;this.image.removeAttribute('src');if(!id)return;try{const url=await window.storyBatch.image(id,false);if(this.selected===id&&version===this.generation){this.image.src=url;this.image.alt=this.item()?.filename??'Generated image';}}catch(e){this.error(String(e));}}
  private async showRecipe():Promise<void>{if(!this.selected)return;const id=this.selected;try{const snapshot=await window.storyBatch.recipe(id);if(this.selected!==id)return;document.querySelector('#recipe-content')!.textContent=`${snapshot.job.prompt}\n\n${JSON.stringify({parameters:snapshot.job,environment:snapshot.environment},null,2)}`;if(!this.recipeDialog.open)this.recipeDialog.showModal();}catch(e){this.error(String(e));}}
  private async variant(change:VariantChange):Promise<void>{if(!this.selected)return;const feedback=document.querySelector('#viewer-feedback')!;try{await window.storyBatch.variant(this.selected,change,this.scope==='shortlist');feedback.textContent='Variant queued.';(document.querySelector('#absolute-shift') as HTMLInputElement).blur();}catch(e){feedback.textContent=String(e);}}
}

import type {DesktopState,ImageSummary} from '../../core/desktop';
import {galleryImages,GalleryScope,ImageSort} from '../../core/gallery';
import {imageActions} from './actions';
export function params(image:Pick<ImageSummary,'seed'|'shift'|'steps'|'width'|'height'>):string {
  return [image.seed===null?null:`Seed ${image.seed}`,image.shift===null?null:`Shift ${image.shift}`,image.steps===null?null:`Steps ${image.steps}`,image.width===null||image.height===null?null:`${image.width}×${image.height}`].filter(Boolean).join(' · ');
}
export class Gallery {
  private cards=new Map<string,{element:HTMLElement;image:ImageSummary;status:HTMLElement;loaded:boolean;frame:HTMLElement;actions:HTMLElement}>();
  constructor(private open:(id:string)=>void,private error:(message:string)=>void,private action:(id:string,action:'shortlisted'|'favorite'|'rejected')=>void){}
  update(state:DesktopState,scope:GalleryScope,sort:ImageSort):void {
    const root=document.querySelector('#gallery')!,images=galleryImages(state,scope,sort),ids=new Set(images.map(i=>i.id));
    for(const [id,card]of this.cards)if(!ids.has(id)){card.element.remove();this.cards.delete(id);}
    for(const image of images){
      let card=this.cards.get(image.id);
      if(!card){
        const element=document.createElement('article');element.className='image-card';element.dataset.imageId=image.id;
        const frame=document.createElement('div');frame.className='frame';frame.style.aspectRatio=`${image.width??1} / ${image.height??1}`;
        const content=document.createElement('div');content.className='card-content';const title=document.createElement('div');title.className='card-name';title.textContent=image.filename;title.title=image.filename;
        const meta=document.createElement('div');meta.className='image-params';meta.textContent=params(image);const status=document.createElement('div');status.className='image-status';const actions=document.createElement('div');
        content.append(title,meta,status,actions);element.append(frame,content);card={element,image,status,loaded:false,frame,actions};this.cards.set(image.id,card);
      }
      root.append(card.element);card.image=image;card.status.textContent=image.status+(image.elapsedMs===null?'':` · ${(image.elapsedMs/1000).toFixed(2)}s`)+(image.cached?' · cached':'');
      card.actions.replaceChildren(imageActions(image,action=>this.action(image.id,action)));if(image.error)card.status.title=image.error;
      if(image.status==='completed'&&!card.loaded){
        card.loaded=true;const button=document.createElement('button');button.type='button';button.setAttribute('aria-label',`View ${image.filename}`);const img=document.createElement('img');img.alt=image.filename;button.append(img);button.addEventListener('click',()=>this.open(image.id));card.frame.replaceChildren(button);
        const expected=card;void window.storyBatch.image(image.id,true).then(url=>{if(this.cards.get(image.id)===expected)img.src=url;}).catch(e=>{expected.loaded=false;this.error(String(e));});
      }else if(!card.loaded){
        const placeholder=document.createElement('div');placeholder.className='placeholder';if(image.status==='running'){const spinner=document.createElement('span');spinner.className='spinner';placeholder.append(spinner);}
        const text=document.createElement('span');text.textContent=image.status==='interrupted'?'Interrupted saved work':image.status==='unresolved'?'Unresolved saved job':image.status;placeholder.append(text);card.frame.replaceChildren(placeholder);
      }
    }
    (document.querySelector('#gallery-empty') as HTMLElement).hidden=images.length>0;
  }
}

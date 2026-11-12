import type {DesktopState,ImageSummary} from '../../core/desktop';
export function params(image:Pick<ImageSummary,'seed'|'shift'|'steps'|'width'|'height'>):string {return `Seed ${image.seed} · Shift ${image.shift} · Steps ${image.steps} · ${image.width}×${image.height}`;}
export class Gallery {
  private cards=new Map<string,{element:HTMLElement;image:ImageSummary;status:HTMLElement;loaded:boolean;frame:HTMLElement}>();
  private batchId:string|null=null;
  constructor(private open:(id:string)=>void,private error:(message:string)=>void){}
  update(state:DesktopState):void {
    const root=document.querySelector('#gallery')!;
    if(this.batchId!==state.batchId){this.cards.clear();root.replaceChildren();this.batchId=state.batchId;}
    for(const image of state.images){
      let card=this.cards.get(image.id);
      if(!card){
        const element=document.createElement('article');element.className='image-card';element.dataset.imageId=image.id;
        const frame=document.createElement('div');frame.className='frame';frame.style.aspectRatio=`${image.width} / ${image.height}`;
        const content=document.createElement('div');content.className='card-content';
        const title=document.createElement('div');title.className='card-name';title.textContent=image.filename;title.title=image.filename;
        const meta=document.createElement('div');meta.className='image-params';meta.textContent=params(image);
        const status=document.createElement('div');status.className='image-status';
        content.append(title,meta,status);element.append(frame,content);root.append(element);
        card={element,image,status,loaded:false,frame};this.cards.set(image.id,card);
      }
      card.image=image;card.status.textContent=image.status+(image.elapsedMs===null?'':` · ${(image.elapsedMs/1000).toFixed(2)}s`)+(image.cached?' · cached':'');
      if(image.error)card.status.title=image.error;
      if(image.status==='completed'&&!card.loaded){
        card.loaded=true;const button=document.createElement('button');button.type='button';button.setAttribute('aria-label',`View ${image.filename}`);
        const img=document.createElement('img');img.alt=image.filename;button.append(img);button.addEventListener('click',()=>this.open(image.id));card.frame.replaceChildren(button);
        const expected=card;void window.storyBatch.image(image.id,true).then(url=>{if(this.cards.get(image.id)===expected)img.src=url;}).catch(e=>{expected.loaded=false;this.error(String(e));});
      }else if(!card.loaded){
        const placeholder=document.createElement('div');placeholder.className='placeholder';
        if(image.status==='running'){const spinner=document.createElement('span');spinner.className='spinner';placeholder.append(spinner);}
        const text=document.createElement('span');text.textContent=image.status==='interrupted'?'Interrupted saved work':image.status==='unresolved'?'Unresolved saved job':image.status;placeholder.append(text);card.frame.replaceChildren(placeholder);
      }
    }
    (document.querySelector('#gallery-empty') as HTMLElement).hidden=state.images.length>0;
  }
}

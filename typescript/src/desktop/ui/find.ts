import {Editor} from './editor';
interface Match {editor:HTMLInputElement|HTMLTextAreaElement;start:number;end:number}
export class Find {
  private bar=document.querySelector<HTMLElement>('#find-bar')!;private input=document.querySelector<HTMLInputElement>('#find-input')!;
  private matches:Match[]=[];private active=-1;private mirrors=new Map<HTMLInputElement|HTMLTextAreaElement,HTMLElement>();
  constructor(editor:Editor){
    for(const control of [editor.parameters,editor.prompt,editor.fields]){
      const wrap=document.createElement('div');wrap.className='find-wrap '+control.id+'-wrap';control.before(wrap);wrap.append(control);
      const mirror=document.createElement('div');mirror.className='find-mirror';mirror.setAttribute('aria-hidden','true');wrap.prepend(mirror);this.mirrors.set(control,mirror);
      const sync=()=>{mirror.scrollTop=control.scrollTop;mirror.scrollLeft=control.scrollLeft;};control.addEventListener('scroll',sync);control.addEventListener('input',()=>this.refresh());control.addEventListener('click',()=>{const offset=control.selectionStart??0;const index=this.matches.findIndex(m=>m.editor===control&&offset>=m.start&&offset<=m.end);if(index>=0){this.active=index;this.refresh();}});
      new ResizeObserver(()=>{mirror.style.height=control.offsetHeight+'px';sync();}).observe(control);
    }
    this.input.addEventListener('input',()=>{this.active=0;this.refresh();this.reveal();});
    this.input.addEventListener('keydown',e=>{if(e.key==='Enter'){e.preventDefault();this.next(e.shiftKey?-1:1);}if(e.key==='Escape'){e.preventDefault();this.close();}});
    document.querySelector('#find-next')!.addEventListener('click',()=>this.next(1));document.querySelector('#find-previous')!.addEventListener('click',()=>this.next(-1));document.querySelector('#find-close')!.addEventListener('click',()=>this.close());
    for(const [control,mirror] of this.mirrors)mirror.addEventListener('click',()=>control.focus());
  }
  open():void{this.bar.hidden=false;this.input.focus();this.input.select();this.refresh();}
  close():void{this.bar.hidden=true;this.refresh();}
  refresh():void{
    const query=this.bar.hidden?'':this.input.value.toLocaleLowerCase();this.matches=[];
    for(const [control] of this.mirrors){if(query){const text=control.value.toLocaleLowerCase();let start=0;while((start=text.indexOf(query,start))>=0){this.matches.push({editor:control,start,end:start+query.length});start+=query.length;}}}
    this.active=Math.min(Math.max(this.active,0),this.matches.length-1);
    for(const [control,mirror] of this.mirrors){mirror.replaceChildren();let offset=0;for(const match of this.matches.filter(m=>m.editor===control)){mirror.append(document.createTextNode(control.value.slice(offset,match.start)));const mark=document.createElement('mark');mark.textContent=control.value.slice(match.start,match.end);mark.className=match===this.matches[this.active]?'active-match':'';mark.addEventListener('click',()=>{this.active=this.matches.indexOf(match);this.refresh();});mirror.append(mark);offset=match.end;}mirror.append(document.createTextNode(control.value.slice(offset)+'\n'));mirror.scrollTop=control.scrollTop;mirror.scrollLeft=control.scrollLeft;}
    document.querySelector('#find-count')!.textContent=`${this.matches.length?this.active+1:0} / ${this.matches.length}`;
  }
  next(delta:number):void{if(this.bar.hidden)this.open();if(!this.matches.length)return;this.active=(this.active+delta+this.matches.length)%this.matches.length;this.refresh();this.reveal();}
  private reveal():void{const match=this.matches[this.active];if(!match)return;const details=match.editor.closest('details');if(details)details.open=true;const mark=this.mirrors.get(match.editor)!.querySelector<HTMLElement>('.active-match');if(mark){const mirror=this.mirrors.get(match.editor)!;match.editor.scrollTop=Math.max(0,mark.offsetTop-mirror.clientHeight/2);match.editor.scrollLeft=Math.max(0,mark.offsetLeft-mirror.clientWidth/2);mirror.scrollTop=match.editor.scrollTop;mirror.scrollLeft=match.editor.scrollLeft;}}
}

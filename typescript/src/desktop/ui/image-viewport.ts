import {ImageViewport} from '../../core/inspection';
import {wheelMagnification,wheelPixels} from './viewer-input';
/** DOM input adapter. Geometry, bounds and inspection identity live outside DOM code. */
export class ImageInspection {
 readonly viewport=new ImageViewport();
 private drag:{id:number;x:number;y:number}|null=null;
 constructor(private pane:HTMLElement,private image:HTMLImageElement,private changed:()=>void,private enabled:()=>boolean){
  this.image.draggable=false;this.image.addEventListener('dragstart',e=>e.preventDefault());
  this.pane.addEventListener('wheel',e=>{
   if(!this.enabled())return;e.preventDefault();const delta=wheelPixels(e,this.pane.clientHeight);
   if(e.ctrlKey||e.altKey){const rect=this.pane.getBoundingClientRect();this.viewport.magnify(wheelMagnification(delta.y),e.clientX-rect.left,e.clientY-rect.top);}
   else if(e.shiftKey)this.viewport.pan(-(delta.x||delta.y),0);else this.viewport.pan(-delta.x,-delta.y);this.apply();
  },{passive:false});
  this.pane.addEventListener('pointerdown',e=>{
   if(!this.enabled()||this.drag||!this.viewport.zoomed||![0,1].includes(e.button))return;e.preventDefault();this.pane.focus({preventScroll:true});this.drag={id:e.pointerId,x:e.clientX,y:e.clientY};this.pane.setPointerCapture(e.pointerId);this.pane.classList.add('dragging');
  });
  this.pane.addEventListener('pointermove',e=>{if(!this.drag||this.drag.id!==e.pointerId)return;this.viewport.pan(e.clientX-this.drag.x,e.clientY-this.drag.y);this.drag.x=e.clientX;this.drag.y=e.clientY;this.apply();});
  for(const name of ['pointerup','pointercancel','lostpointercapture'])this.pane.addEventListener(name,event=>{const e=event as PointerEvent;if(this.drag?.id===e.pointerId)this.endDrag();});
  this.pane.addEventListener('auxclick',e=>{if(e.button===1)e.preventDefault();});
  window.addEventListener('blur',()=>this.endDrag());new ResizeObserver(()=>this.measure()).observe(this.pane);
 }
 private endDrag():void{const id=this.drag?.id;this.drag=null;this.pane.classList.remove('dragging');if(id!==undefined&&this.pane.hasPointerCapture(id))this.pane.releasePointerCapture(id);}
 reset():void{this.endDrag();this.viewport.fit();this.apply();}
 measure():void{const bounds=this.pane.getBoundingClientRect();this.viewport.resize(bounds.width,bounds.height);this.apply();}
 dimensions(width:number,height:number):void{this.viewport.image(width,height);this.apply();}
 zoom(factor:number):void{this.viewport.magnify(factor);this.apply();}
 private apply():void{const rect=this.viewport.rect;Object.assign(this.image.style,{left:rect.left+'px',top:rect.top+'px',width:rect.width+'px',height:rect.height+'px'});this.pane.classList.toggle('zoomed',this.viewport.zoomed);this.pane.dataset.zoom=String(this.viewport.zoom);this.pane.dataset.centerX=String(this.viewport.centerX);this.pane.dataset.centerY=String(this.viewport.centerY);this.changed();}
}

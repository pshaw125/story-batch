export interface ViewRect {left:number;top:number;width:number;height:number}
/** One active inspection point, normalized to image coordinates; no per-seed history. */
export class ImageViewport {
  zoom=1;centerX=.5;centerY=.5;
  private areaWidth=1;private areaHeight=1;private imageWidth=1;private imageHeight=1;
  readonly maximumZoom=16;
  get zoomed():boolean{return this.zoom>1.000001;}
  private size():{width:number;height:number}{const fit=Math.min(this.areaWidth/this.imageWidth,this.areaHeight/this.imageHeight);return {width:this.imageWidth*fit*this.zoom,height:this.imageHeight*fit*this.zoom};}
  get rect():ViewRect{const {width,height}=this.size();return {width,height,left:this.areaWidth/2-this.centerX*width,top:this.areaHeight/2-this.centerY*height};}
  private clamp():void{const {width,height}=this.size();const bound=(value:number,size:number,area:number)=>size<=area ? .5 : Math.max(area/(2*size),Math.min(1-area/(2*size),value));this.centerX=bound(this.centerX,width,this.areaWidth);this.centerY=bound(this.centerY,height,this.areaHeight);if(!this.zoomed){this.zoom=1;this.centerX=this.centerY=.5;}}
  resize(width:number,height:number):void{if(!Number.isFinite(width)||!Number.isFinite(height)||width<=0||height<=0)return;this.areaWidth=width;this.areaHeight=height;this.clamp();}
  image(width:number,height:number):void{if(!Number.isFinite(width)||!Number.isFinite(height)||width<=0||height<=0)return;this.imageWidth=width;this.imageHeight=height;this.clamp();}
  fit():void{this.zoom=1;this.centerX=this.centerY=.5;}
  magnify(factor:number,x=this.areaWidth/2,y=this.areaHeight/2):void{
    if(!Number.isFinite(factor)||factor<=0||!Number.isFinite(x)||!Number.isFinite(y))return;
    const before=this.rect,anchorX=(x-before.left)/before.width,anchorY=(y-before.top)/before.height;
    this.zoom=Math.max(1,Math.min(this.maximumZoom,this.zoom*factor));const after=this.size();
    this.centerX=anchorX+(this.areaWidth/2-x)/after.width;this.centerY=anchorY+(this.areaHeight/2-y)/after.height;this.clamp();
  }
  pan(x:number,y:number):void{if(!Number.isFinite(x)||!Number.isFinite(y))return;const size=this.size();this.centerX-=x/size.width;this.centerY-=y/size.height;this.clamp();}
}
export interface Boundary {from:string;to:string;direction:-1|1}
export class SeedBoundaryGuard {
  pending:Boundary|null=null;
  clear():void{this.pending=null;}
  get notice():string|null{return this.pending?(this.pending.direction===1?'Next seed; press again to proceed':'Previous seed; press again to proceed'):null;}
  allow(from:string,to:string,sourceSeed:number|null,targetSeed:number|null,zoomed:boolean,direction:-1|1,repeat=false):boolean{
    if(!zoomed||sourceSeed===null||targetSeed===null||sourceSeed===targetSeed){this.clear();return true;}
    if(this.pending?.from===from&&this.pending.to===to&&this.pending.direction===direction){if(repeat)return false;this.clear();return true;}
    this.pending={from,to,direction};return false;
  }
}
export function retainViewport(from:{id:string;seed:number|null}|null,to:{id:string;seed:number|null}):boolean{return !!from&&(from.id===to.id||from.seed!==null&&to.seed!==null&&from.seed===to.seed);}

import {createHash} from 'node:crypto';
import {readFile,mkdir,writeFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {PNG} from 'pngjs';
import {CanvasAsset,CanvasSelection,ImageInput,ImageJob} from '../core/planning';
import {validateCanvasAsset} from '../core/reports';
import {validatePNG} from './png';
import {RenderError} from '../core/renderer';
export const digest=(bytes:Uint8Array)=>createHash('sha256').update(bytes).digest('hex');
export function pngSize(bytes:Uint8Array):{width:number;height:number}{const b=Buffer.from(bytes);if(b.length<33)throw new Error('Canvas must be a PNG.');const width=b.readUInt32BE(16),height=b.readUInt32BE(20);validatePNG(b,width,height);return {width,height};}
export async function readCanvas(asset:CanvasAsset):Promise<Buffer>{validateCanvasAsset(asset);const bytes=await readFile(asset.path);if(digest(bytes)!==asset.hash)throw new RenderError('Copied canvas changed; choose it again.','validation');validatePNG(bytes,asset.width,asset.height);return bytes;}
export async function recoverCanvas(asset:CanvasAsset,batchFolder:string):Promise<CanvasAsset>{try{await readCanvas(asset);return structuredClone(asset);}catch{const copied={...asset,path:resolve(batchFolder,'inputs',asset.hash+'.png')};await readCanvas(copied);return copied;}}
/** Content-addressed copies survive original deletion. Never overwrite a hash collision or changed file. */
export class CanvasStore {
 constructor(private root:string){}
 async capture(bytes:Uint8Array):Promise<CanvasAsset>{const size=pngSize(bytes),hash=digest(bytes),folder=join(this.root,'.inputs'),path=resolve(folder,hash+'.png');await mkdir(folder,{recursive:true});try{await writeFile(path,bytes,{flag:'wx'});}catch(error){if((error as NodeJS.ErrnoException).code!=='EEXIST')throw error;if(digest(await readFile(path))!==hash)throw new Error('Stored canvas hash differs; refusing to overwrite it.');}return {path,hash,...size};}
 async prepare(canvas:CanvasSelection,width:number,height:number,instructions:string):Promise<ImageInput>{
  if(!Number.isFinite(canvas.strength)||canvas.strength<0||canvas.strength>1)throw new Error('Image strength must be from 0 to 1.');
  if(!['append','replace'].includes(canvas.mode)||!['match','center-crop'].includes(canvas.policy))throw new Error('Invalid canvas mode.');
  const original=await readCanvas(canvas.asset),source=PNG.sync.read(original),sw=source.width,sh=source.height;
  if(canvas.policy==='match'&&sw*height!==sh*width)throw new Error('Canvas and output aspect ratios differ. Choose center-crop or matching dimensions.');
  let cw=sw,ch=sh;if(sw*height>sh*width)cw=sh*width/height;else ch=sw*height/width;const x=(sw-cw)/2,y=(sh-ch)/2;
  const output=new PNG({width,height});
  for(let row=0;row<height;row++)for(let col=0;col<width;col++){
   const sx=Math.max(0,Math.min(sw-1,x+(col+.5)*cw/width-.5)),sy=Math.max(0,Math.min(sh-1,y+(row+.5)*ch/height-.5)),x0=Math.floor(sx),y0=Math.floor(sy),dx=sx-x0,dy=sy-y0;
   const samples=[[x0,y0,(1-dx)*(1-dy)],[Math.min(sw-1,x0+1),y0,dx*(1-dy)],[x0,Math.min(sh-1,y0+1),(1-dx)*dy],[Math.min(sw-1,x0+1),Math.min(sh-1,y0+1),dx*dy]];
   const offset=(row*width+col)*4;
   for(let channel=0;channel<3;channel++){let value=0;for(const [px,py,w] of samples){const i=(py*sw+px)*4,a=source.data[i+3]/255;value+=(source.data[i+channel]*a+255*(1-a))*w;}output.data[offset+channel]=Math.round(value);}output.data[offset+3]=255;
  }
  const asset=await this.capture(PNG.sync.write(output));return {asset,original:structuredClone(canvas.asset),source:structuredClone(canvas.source),strength:canvas.strength,preprocessing:{method:'bilinear-rgba-white-v1',policy:canvas.policy,crop:{x,y,width:cw,height:ch}},prompt:{mode:canvas.mode,instructions}};
 }
}
export async function validateInput(job:ImageJob):Promise<void>{if(job.input)await readCanvas(job.input.asset);}

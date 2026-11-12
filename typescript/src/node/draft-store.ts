import {copyFile,mkdir,readFile,rename,writeFile,rm,constants} from 'node:fs/promises';
import {dirname} from 'node:path';
import {randomUUID} from 'node:crypto';
import {validateCanvasSelection} from '../core/reports';
import {validateRecipe,drawThingsPreset} from '../core/recipes';
import type {DraftSnapshot} from '../core/desktop';
export const emptyDraft=():DraftSnapshot=>({source:'count=4; steps=3; aspect=1:1\n',lastBatch:null,scope:'images',sort:'seeded'});
export function validateDraft(value:DraftSnapshot):void{
  if(!value||typeof value.source!=='string'||Buffer.byteLength(value.source)>2_000_000||value.lastBatch!==null&&typeof value.lastBatch!=='string'||!['images','shortlist','favorites','rejected'].includes(value.scope)||!['seeded','seeded-step','newest'].includes(value.sort))throw new Error('Invalid saved draft.');
  if(value.tools){if(!['draw-things','comfyui'].includes(value.tools.backend))throw new Error('Invalid draft renderer tools.');validateRecipe({...drawThingsPreset(),loras:value.tools.loras});if(value.tools.canvas!==null)validateCanvasSelection(value.tools.canvas);}
}
export class DraftStore {
  private current=emptyDraft();private tail:Promise<void>=Promise.resolve();private timer:NodeJS.Timeout|null=null;private invalid=false;
  constructor(private file:string,private onError:(error:unknown)=>void=()=>{}){}
  snapshot():DraftSnapshot{return structuredClone(this.current);}
  async load():Promise<DraftSnapshot>{try{const data=JSON.parse(await readFile(this.file,'utf8'));if(data.schemaVersion!==1)throw new Error('Unsupported draft schema.');validateDraft(data.draft);this.current=data.draft;return this.snapshot();}catch(error){if((error as NodeJS.ErrnoException).code==='ENOENT')return this.snapshot();this.invalid=true;throw error;}}
  save(value:DraftSnapshot):void{validateDraft(value);if(JSON.stringify(value)===JSON.stringify(this.current))return;this.current=structuredClone(value);if(this.timer)clearTimeout(this.timer);this.timer=setTimeout(()=>{this.timer=null;void this.write().catch(error=>this.onError(error));},200);this.timer.unref();}
  private write():Promise<void>{const draft=this.snapshot();const next=this.tail.then(async()=>{
    await mkdir(dirname(this.file),{recursive:true});if(this.invalid){await copyFile(this.file,this.file+'.invalid-'+Date.now(),constants.COPYFILE_EXCL);this.invalid=false;}
    const temp=this.file+'.'+randomUUID()+'.tmp';try{await writeFile(temp,JSON.stringify({schemaVersion:1,draft},null,2)+'\n',{flag:'wx'});await rename(temp,this.file);}finally{await rm(temp,{force:true});}
  });this.tail=next.catch(()=>{});return next;}
  async flush():Promise<void>{if(this.timer){clearTimeout(this.timer);this.timer=null;}await this.write();}
}

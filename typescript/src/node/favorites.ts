import {mkdir,readFile,readdir,writeFile,rename,rm,stat} from 'node:fs/promises';
import {join,basename,resolve} from 'node:path';
import {createHash,randomUUID} from 'node:crypto';
import {safeTitle,validateContext} from '../core/planning';
import {validateJob} from '../core/reports';
import type {RecipeSnapshot} from '../core/desktop';
export interface FavoriteFile {id:string;filename:string;recency:number;snapshot:RecipeSnapshot|null;sourceFolder:string|null}
interface FavoriteMetadata {schemaVersion:1;snapshot:RecipeSnapshot;sourceFolder:string;imageHash:string}
const extensions=new Set(['png','jpg','jpeg','webp','gif','bmp']);
const identity=(name:string)=>'favorite:'+createHash('sha256').update(name).digest('hex');
export function imageMime(filename:string):string {const ext=filename.split('.').at(-1)!.toLowerCase();return ext==='jpg'||ext==='jpeg'?'image/jpeg':`image/${ext}`;}
/** The directory is authoritative. Sidecars add provenance, never membership.
 * Removed copies are archived so external images have no destructive unfavorite path. */
export class Favorites {
  readonly folder:string;private index=new Map<string,FavoriteFile>();
  constructor(outputRoot:string){this.folder=join(outputRoot,'_favorites');}
  async list():Promise<FavoriteFile[]>{
    let files;try{files=await readdir(this.folder,{withFileTypes:true});}catch(e){if((e as NodeJS.ErrnoException).code==='ENOENT'){this.index.clear();return [];}throw e;}
    const result:FavoriteFile[]=[];
    for(const file of files.filter(f=>f.isFile()&&extensions.has(f.name.split('.').at(-1)!.toLowerCase())).sort((a,b)=>a.name.localeCompare(b.name))){
      let metadata:FavoriteMetadata|null=null;
      try{const value=JSON.parse(await readFile(join(this.folder,file.name+'.json'),'utf8'));if(value.schemaVersion!==1||typeof value.sourceFolder!=='string')throw new Error('Unknown favorite sidecar.');validateJob(value.snapshot.job);validateContext(value.snapshot.environment);if(value.snapshot.environment.id!==value.snapshot.job.runId||typeof value.imageHash!=='string'||createHash('sha256').update(await readFile(join(this.folder,file.name))).digest('hex')!==value.imageHash)throw new Error('Favorite provenance does not match its image.');metadata=value;}catch{/* External/malformed sidecars are metadata-free images. */}
      result.push({id:identity(file.name),filename:file.name,recency:(await stat(join(this.folder,file.name))).mtimeMs,snapshot:metadata?.snapshot??null,sourceFolder:metadata?.sourceFolder??null});
    }
    this.index=new Map(result.map(f=>[f.id,f]));return structuredClone(result);
  }
  file(id:string):FavoriteFile {const file=this.index.get(id);if(!file)throw new Error('Favorite is no longer in the folder; refresh Favorites.');return structuredClone(file);}
  async bytes(id:string):Promise<Uint8Array>{return readFile(join(this.folder,this.file(id).filename));}
  async add(snapshot:RecipeSnapshot,sourceFolder:string,bytes:Uint8Array):Promise<void>{
    const existing=(await this.list()).find(f=>f.snapshot?.job.id===snapshot.job.id&&f.sourceFolder===sourceFolder);if(existing)return;
    await mkdir(this.folder,{recursive:true});let name=snapshot.job.filename;
    const names=await readdir(this.folder);
    if(Buffer.byteLength(name)>220||names.includes(name)||names.includes(name+'.json'))name=`${safeTitle(name.replace(/\.png$/i,''),150)}_${randomUUID()}.png`;
    const target=join(this.folder,name);
    await writeFile(target,bytes,{flag:'wx'});
    try{const metadata:FavoriteMetadata={schemaVersion:1,snapshot:structuredClone(snapshot),sourceFolder:resolve(sourceFolder),imageHash:createHash('sha256').update(bytes).digest('hex')};await writeFile(target+'.json',JSON.stringify(metadata,null,2)+'\n',{flag:'wx'});}
    catch(error){await rm(target,{force:true});throw error;}
    await this.list();
  }
  async remove(id:string):Promise<void>{
    const file=this.file(id);if(basename(file.filename)!==file.filename)throw new Error('Invalid favorite path.');
    const archive=join(this.folder,'.removed',randomUUID());await mkdir(archive,{recursive:true});
    await rename(join(this.folder,file.filename),join(archive,file.filename));
    try{await rename(join(this.folder,file.filename+'.json'),join(archive,file.filename+'.json'));}catch(e){if((e as NodeJS.ErrnoException).code!=='ENOENT')throw e;}
    await this.list();
  }
}

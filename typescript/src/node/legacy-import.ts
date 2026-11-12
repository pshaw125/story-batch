import {readFile,readdir,mkdir,writeFile,rename,realpath,stat} from 'node:fs/promises';
import {join,resolve,relative,isAbsolute,sep,basename} from 'node:path';
import {randomUUID} from 'node:crypto';
import {ImageJob,RunContext,filename,FrozenBatch} from '../core/planning';
import {drawThingsPreset,DrawThingsRecipe,unknownAsset,validateRecipe} from '../core/recipes';
import {BatchReport,ImageRecord,validateJob} from '../core/reports';
import {RecipeSnapshot,SwiftImportPreview} from '../core/desktop';
import {ReportStore} from './storage';
import {digest} from './canvas';
import {validatePNG} from './png';
import {Favorites} from './favorites';
type Json=Record<string,any>; // Swift versions are validated before mapping; raw records remain archived.
const legacyPath=(p:string)=>p.replace(/\\/g,'/').replace(/\/+$/,'');
async function legacy(folder:string):Promise<{value:Json;bytes:Buffer;name:string}>{
 const names=(await readdir(folder)).filter(n=>/^report_.*\.json$/.test(n)).sort().reverse();if(!names.length)throw new Error('Choose a Swift batch folder containing report_*.json.');
 const name=names[0];if((await stat(join(folder,name))).size>100_000_000)throw new Error('Legacy report exceeds 100 MB.');const bytes=await readFile(join(folder,name));if(bytes.length>100_000_000)throw new Error('Legacy report exceeds 100 MB.');const value=JSON.parse(bytes.toString('utf8'));
 if(value.version!==1||!Array.isArray(value.images)||value.images.length>100000||typeof value.folder!=='string'||typeof value.sourceMetaprompt!=='string'||typeof value.parameters?.title!=='string'||!Number.isFinite(Date.parse(value.createdAt)))throw new Error('Unsupported or incomplete Swift report.');
 return {value,bytes,name};
}
export async function inspectSwiftBatch(folder:string):Promise<SwiftImportPreview>{const {value,name}=await legacy(folder);return {folder:resolve(folder),originalFolder:value.folder,reportFilename:name,title:value.parameters.title,images:value.images.length,warnings:['Historical recipes retain Draw Things settings. New backend renders require an explicit current-renderer copy.','Only completed, readable PNG outputs are marked completed; originals and raw records are preserved.']};}
async function within(folder:string,reference:string,oldFolder:string):Promise<string>{
 let rel=reference.replace(/\\/g,'/');if(rel.startsWith('/')||/^[A-Za-z]:/.test(rel)){const prefix=legacyPath(oldFolder)+'/';if(!rel.startsWith(prefix))throw new Error('Legacy path needs an explicit mapping: '+reference);rel=rel.slice(prefix.length);}
 if(rel.split('/').some(p=>p==='..')||isAbsolute(rel))throw new Error('Unsafe legacy relative path.');const root=await realpath(folder),file=await realpath(resolve(root,rel)),difference=relative(root,file);if(isAbsolute(difference)||difference==='..'||difference.startsWith('..'+sep))throw new Error('Legacy path escapes the selected folder.');return file;
}
export function swiftRecipe(raw:Json|null,model:string):DrawThingsRecipe {
 const recipe=drawThingsPreset();delete recipe.negativePrompt;recipe.model=unknownAsset(typeof raw?.model==='string'?raw.model:model||recipe.model.id);
 if(raw){recipe.sampler=raw.sampler??recipe.sampler;recipe.seedMode=raw.seedMode??recipe.seedMode;recipe.guidance=raw.guidanceScale??recipe.guidance;
  if(raw.resolutionDependentShift===true)throw new Error('Legacy automatic shift cannot be represented by this native baseline.');
  recipe.loras=(raw.loras??[]).map((l:Json)=>({asset:unknownAsset(l.file),modelWeight:l.weight,encoderWeight:null,...(l.version?{nativeVersion:l.version}:{})}));
  if(typeof raw.negativePrompt==='string')recipe.negativePrompt=raw.negativePrompt;
 }validateRecipe(recipe);return recipe;
}
function favoriteSnapshot(record:Json,source:Json|null,config:Json|null,at:string):RecipeSnapshot {
 const p=record?.plan;if(!p||typeof p.prompt!=='string')throw new Error('Favorite has no usable historical plan.');
 const context:RunContext={id:randomUUID(),createdAt:at,os:{name:'unknown',version:'unknown',arch:'unknown'},framework:{name:'draw-things-cli',version:'unknown (Swift favorite)'},hardware:'unknown',driver:'unknown',computeRuntime:'unknown',applicationVersion:'unknown (Swift favorite)'};
 const title=record.requestParameters?.title??'Imported favorite',shift=typeof p.shift==='string'?p.shift:String(p.shift?.text??p.shift?.jsonNumber??p.shift);
 const job:ImageJob={schemaVersion:1,id:randomUUID(),batchId:randomUUID(),runId:context.id,number:p.number,title,source:record.sourceMetaprompt??'count=1\n'+p.prompt,notes:record.requestParameters?.notes??'',prompt:p.prompt,sharedFields:{},seed:p.seed,shift,steps:p.steps,width:p.width,height:p.height,filename:filename(title,p.seed,p.steps,shift,p.number),recipe:swiftRecipe(p.recipe??config,'unknown (legacy favorite)'),legacy:{kind:'swift',originalNumber:p.number,originalFilename:p.filename,recipeSource:p.recipe?'plan':config?'configuration':'unknown',record:{record,source,configuration:config}}};validateJob(job);return {job,environment:context};
}
export interface SwiftImportOptions {folder:string;outputRoot:string;mapping:{from:string;to:string};selectionsFile?:string;favoritesFolder?:string}
export async function importSwiftBatch(options:SwiftImportOptions):Promise<{folder:string;warnings:string[]}>{
 const data=await legacy(options.folder),old=data.value,warnings:string[]=[];
 if(legacyPath(options.mapping.from)!==legacyPath(old.folder)||resolve(options.mapping.to)!==resolve(options.folder))throw new Error('Confirm the explicit old-folder → selected-folder mapping before import.');
 const id=randomUUID(),at=new Date().toISOString(),runs:RunContext[]=[],runIds=new Map<string,string>(),jobs:ImageJob[]=[],records:ImageRecord[]=[];
 const archives=new Map<string,Buffer>([['legacy/report.json',data.bytes]]),outputs=new Map<string,Buffer>();
 const run=(record:Json):RunContext=>{const key=String(record.runID??old.id??'legacy');let mapped=runIds.get(key);if(!mapped){mapped=randomUUID();runIds.set(key,mapped);runs.push({id:mapped,createdAt:old.createdAt,os:{name:'unknown',version:'unknown',arch:'unknown'},framework:{name:'draw-things-cli',version:String(old.cliVersion??'unknown')},hardware:'unknown',driver:'unknown',computeRuntime:'unknown',applicationVersion:'unknown (Swift import)'});}return runs.find(r=>r.id===mapped)!;};
 for(const [index,record] of old.images.entries()){
  const p=record.plan;if(!p||typeof p.filename!=='string'||typeof p.prompt!=='string'||!Number.isSafeInteger(p.number)||p.number<1)throw new Error('Invalid legacy image plan at index '+index);
  let config:Json|null=null;
  if(typeof record.configurationFile==='string')try{const bytes=await readFile(await within(options.folder,record.configurationFile,old.folder));archives.set(`legacy/config-${index+1}.json`,bytes);config=JSON.parse(bytes.toString('utf8'));}catch(error){warnings.push(`Image ${p.number}: configuration unavailable: ${String(error)}`);}
  const recipeSource=p.recipe?'plan':config?'configuration':'legacy-preset';const recipe=swiftRecipe(p.recipe??config,old.model);
  if(recipeSource==='legacy-preset')warnings.push(`Image ${p.number}: native defaults were not recorded; marked legacy-preset.`);
  const context=run(record),shift=typeof p.shift==='string'?p.shift:typeof p.shift?.text==='string'?p.shift.text:String(p.shift?.jsonNumber??p.shift);
  const job:ImageJob={schemaVersion:1,id:randomUUID(),batchId:id,runId:context.id,number:p.number,title:old.parameters.title,source:record.sourceMetaprompt??old.sourceMetaprompt,notes:String(record.requestParameters?.notes??old.parameters.notes??''),prompt:p.prompt,sharedFields:{},seed:p.seed,shift,steps:p.steps,width:p.width,height:p.height,filename:filename(old.parameters.title,p.seed,p.steps,shift,p.number),recipe,legacy:{kind:'swift',originalNumber:p.number,originalFilename:p.filename,recipeSource,record:structuredClone(record)}};
  validateJob(job);jobs.push(job);
  const result:ImageRecord={jobId:job.id,status:'cancelled',attempts:Math.max(0,Math.min(2,record.renderAttempts??(record.status==='completed'?1:0))),elapsedMs:typeof record.elapsedSeconds==='number'?record.elapsedSeconds*1000:null,output:null,error:null};
  if(typeof record.startedAt==='string'&&Number.isFinite(Date.parse(record.startedAt)))result.startedAt=record.startedAt;
  if(typeof record.finishedAt==='string'&&Number.isFinite(Date.parse(record.finishedAt)))result.finishedAt=record.finishedAt;
  if(result.attempts)result.executionIndex=index+1;
  if(record.status==='completed')try{const bytes=await readFile(await within(options.folder,p.filename,old.folder));validatePNG(bytes,p.width,p.height);outputs.set(job.id,bytes);result.status='completed';result.output=job.filename;}catch(error){result.status='failed';result.error='Imported output unavailable: '+String(error);warnings.push(`Image ${p.number}: ${result.error}`);}
  else if(record.status==='failed'){result.status='failed';result.error=String(record.error??'Historical render failed.');}
  if(typeof record.inputImageFile==='string')try{archives.set(`legacy/input-${index+1}${/\.[a-z0-9]+$/i.exec(record.inputImageFile)?.[0]??'.bin'}`,await readFile(await within(options.folder,record.inputImageFile,old.folder)));}catch(error){warnings.push(`Image ${p.number}: original canvas unavailable: ${String(error)}`);}
  records.push(result);
 }
 if(!jobs.length)throw new Error('Legacy batch has no image records to import.');
 const selections:NonNullable<BatchReport['selections']>={};
 if(options.selectionsFile){const bytes=await readFile(options.selectionsFile),items=JSON.parse(bytes.toString('utf8'));if(!Array.isArray(items))throw new Error('Selections must be the Swift image-selections.json array.');archives.set('legacy/image-selections.json',bytes);
  for(const item of items){if(typeof item.folderPath!=='string'||legacyPath(item.folderPath)!==legacyPath(old.folder))continue;const job=jobs.find(j=>j.legacy!.originalFilename===item.record?.plan?.filename);if(job&&(item.shortlisted===true||item.rejected===true))selections[job.id]={shortlisted:item.shortlisted===true,rejected:item.rejected===true};}
 }
 const batch:FrozenBatch={schemaVersion:1,id,title:old.parameters.title,createdAt:old.createdAt,run:runs[0],jobs};
 const staging=join(options.outputRoot,'.imports',id),store=await ReportStore.create(staging,batch);
 await mkdir(join(store.folder,'legacy'),{recursive:true});for(const [name,bytes] of archives)await writeFile(join(store.folder,name),bytes,{flag:'wx'});
 for(const job of jobs){const bytes=outputs.get(job.id);if(bytes)await store.writeOutput(job,bytes);}
 const report:BatchReport={schemaVersion:1,batch,runs,records,editorSource:old.sourceMetaprompt,selections,imported:{kind:'swift',sourceFolder:old.folder,reportFilename:data.name,reportHash:digest(data.bytes),importedAt:at,mapping:options.mapping,warnings}};
 await store.save(report);const folder=join(options.outputRoot,basename(store.folder));await rename(store.folder,folder);
 if(options.favoritesFolder){const favorites=new Favorites(options.outputRoot);if(resolve(options.favoritesFolder)===resolve(favorites.folder))warnings.push('Favorites source equals destination; skipped copying.');else{
  for(const file of await readdir(options.favoritesFolder,{withFileTypes:true})){
   if(!file.isFile()||! /\.(png|jpe?g|webp|gif|bmp)$/i.test(file.name))continue;
   try{const bytes=await readFile(join(options.favoritesFolder,file.name));let metadata:Json|null=null;try{metadata=JSON.parse(await readFile(join(options.favoritesFolder,file.name+'.json'),'utf8'));}catch{/* External image. */}
    const job=typeof metadata?.source?.folderPath==='string'&&legacyPath(metadata.source.folderPath)===legacyPath(old.folder)?jobs.find(j=>j.legacy!.originalFilename===metadata?.source?.record?.plan?.filename&&j.prompt===metadata?.source?.record?.plan?.prompt):undefined;
    if(job&&digest(bytes)===digest(outputs.get(job.id)??new Uint8Array()))await favorites.add({job,environment:runs.find(r=>r.id===job.runId)!},folder,bytes);else if(metadata?.record){try{let config:Json|null=null;if(typeof metadata.record.configurationFile==='string')config=JSON.parse(await readFile(await within(options.favoritesFolder,metadata.record.configurationFile,options.favoritesFolder),'utf8'));const snapshot=favoriteSnapshot(metadata.record,metadata.source??null,config,at);validatePNG(bytes,snapshot.job.width,snapshot.job.height);await favorites.add(snapshot,null,bytes);}catch(error){warnings.push('Favorite '+file.name+': preserved without usable native recipe: '+String(error));await favorites.addExternal(file.name,bytes);}}else await favorites.addExternal(file.name,bytes);
   }catch(error){warnings.push('Favorite '+file.name+': '+String(error));}
  }
 }}
 await ReportStore.open(folder).save({...structuredClone(await ReportStore.open(folder).load()),imported:{...report.imported!,warnings}});
 return {folder,warnings};
}

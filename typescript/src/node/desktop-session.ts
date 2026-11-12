import { randomUUID } from 'node:crypto';
import { readFile, realpath } from 'node:fs/promises';
import { join, relative, isAbsolute, sep } from 'node:path';
import { compile } from '../core/prompt';
import { shifts } from '../core/arithmetic';
import { deepFreeze } from '../core/errors';
import { FrozenBatch, filename, freezeBatch, variant } from '../core/planning';
import { BatchReport } from '../core/reports';
import { DesktopState, PreviewResult, RecipeSnapshot, VariantChange } from '../core/desktop';
import { BatchExecutor } from './executor';
import { ReportStore } from './storage';
import { Runtime } from './runtime';
export class DesktopSession {
  private report:BatchReport|null=null;
  private store:ReportStore|null=null;
  private runtime:Runtime|null=null;
  private pending:FrozenBatch[]=[];
  private active:FrozenBatch|null=null;
  private execution:Promise<void>|null=null;
  private operations:Promise<void>=Promise.resolve();
  private executor=new BatchExecutor();
  private previewCache:{source:string;round:FrozenBatch}|null=null;
  private listeners=new Set<(state:DesktopState)=>void>();
  private activeId:string|null=null;
  private progress:DesktopState['progress']=null;
  private preparing=false;
  private stopping=false;
  private uncertain=false;
  private error:string|null=null;
  private activity:string[]=[];
  constructor(private outputRoot:string){}
  subscribe(listener:(state:DesktopState)=>void):()=>void {this.listeners.add(listener);return()=>this.listeners.delete(listener);}
  state():DesktopState {
    const owned=new Set([...(this.active?.jobs??[]),...this.pending.flatMap(r=>r.jobs)].map(j=>j.id));
    return structuredClone({renderer:this.runtime?.label??'No renderer selected',configured:!!this.runtime,busy:this.preparing||!!this.execution||this.pending.length>0,stopping:this.stopping,uncertain:this.uncertain,
      batchId:this.report?.batch.id??null,title:this.report?.batch.title??null,folder:this.store?.folder??null,outputRoot:this.outputRoot,
      images:(this.report?.batch.jobs??[]).map(job=>{
        const record=this.report!.records.find(r=>r.jobId===job.id)!;
        return {id:job.id,number:job.number,filename:job.filename,seed:job.seed,shift:job.shift,steps:job.steps,width:job.width,height:job.height,
          status:!owned.has(job.id)&&record.status==='unknown'?'unresolved':!owned.has(job.id)&&['running','queued'].includes(record.status)?'interrupted':record.status,elapsedMs:record.elapsedMs,error:record.error,cached:record.cached};
      }),activeId:this.activeId,progress:this.progress,activity:this.activity,error:this.error});
  }
  private publish():void {const state=this.state();for(const listener of this.listeners)listener(state);}
  private note(message:string):void {this.activity.push(`${new Date().toLocaleTimeString()} · ${message}`);this.activity=this.activity.slice(-200);}
  private serial<T>(action:()=>Promise<T>):Promise<T>{const next=this.operations.then(action);this.operations=next.then(()=>{},()=>{});return next;}
  private lastNumber():number {return this.report?.batch.jobs.reduce((n,j)=>Math.max(n,j.number),0)??0;}
  async setRuntime(runtime:Runtime):Promise<void>{await this.serial(async()=>{if(this.state().busy)throw new Error('Stop the batch before changing renderer.');this.runtime?.close();this.runtime=runtime;this.uncertain=false;this.previewCache=null;this.error=null;this.note(`Renderer: ${runtime.label}`);this.publish();});}
  async setOutputRoot(folder:string):Promise<void>{await this.serial(async()=>{if(this.state().busy)throw new Error('Stop the batch before changing output folder.');this.outputRoot=folder;this.publish();});}
  private async prepare(source:string):Promise<FrozenBatch>{
    if(!this.runtime)throw new Error('Choose a local renderer configuration first.');
    const compiled=compile(source,{defaultTitle:this.report?.batch.title});
    const same=this.report?.batch.title===compiled.parameters.title;
    const context=await this.runtime.context();context.id=randomUUID();context.createdAt=new Date().toISOString();
    const round=freezeBatch(source,this.runtime.recipe,context,{random:Math.random,id:randomUUID,continuing:same?{id:this.report!.batch.id,title:this.report!.batch.title,lastNumber:this.lastNumber()}:undefined});
    for(const job of round.jobs)if(!job.prompt.trim())throw new Error(`Resolved prompt for image ${job.number} is empty.`);
    return round;
  }
  async preview(source:string):Promise<PreviewResult>{return this.serial(async()=>{
    const round=await this.prepare(source);this.previewCache={source,round};
    return {images:structuredClone(round.jobs.slice(0,4)),startsNewBatch:round.id!==this.report?.batch.id,title:round.title};
  });}
  async queue(source:string,newBatch=false):Promise<DesktopState>{return this.serial(async()=>{
    if(this.stopping||this.uncertain)throw new Error('Renderer work must be stopped/reconciled before queueing more.');
    const wasRunning=!!this.execution||this.pending.length>0;
    this.preparing=true;this.publish();
    try {
      let round=this.previewCache?.source===source?this.previewCache.round:await this.prepare(source);
      if(this.stopping)return this.state();
      if(round.id===this.report?.batch.id&&round.jobs[0]?.number!==this.lastNumber()+1){
        const first=this.lastNumber()+1;
        round=deepFreeze({...structuredClone(round),jobs:round.jobs.map((j,i)=>({...structuredClone(j),number:first+i,filename:filename(j.title,j.seed,j.steps,j.shift,first+i)}))});
      }
      if((newBatch||round.id!==this.report?.batch.id)&&wasRunning)throw new Error('Wait for the batch to finish or stop it before starting a new batch/title.');
      if(newBatch&&round.id===this.report?.batch.id){
        const id=randomUUID();
        round=deepFreeze({...structuredClone(round),id,jobs:round.jobs.map((j,i)=>({...structuredClone(j),batchId:id,number:i+1,filename:filename(j.title,j.seed,j.steps,j.shift,i+1)}))});
      }
      this.previewCache=null;this.error=null;
      await this.persistRound(round,true);
      this.note(`Queued ${round.jobs.length} image(s).`);this.pending.push(round);
      if(!this.stopping)this.start();
      this.publish();return this.state();
    } finally {this.preparing=false;this.publish();}
  }).then(()=>this.state());}
  private async persistRound(round:FrozenBatch,editor:boolean):Promise<void>{
    if(!this.store||round.id!==this.report?.batch.id)this.store=await ReportStore.create(this.outputRoot,round);
    else await this.store.append(round,editor);
    this.report=structuredClone(await this.store.load());
  }
  private start():void {
    if(this.execution)return;
    this.execution=this.pump().catch(error=>{this.error=String(error);this.uncertain=true;this.note(this.error);}).finally(()=>{
      this.execution=null;this.active=null;this.activeId=null;this.progress=null;this.stopping=false;this.publish();
      if(this.pending.length&&!this.uncertain)this.start();
    });
  }
  private async pump():Promise<void>{
    while(this.pending.length&&!this.stopping){
      const round=this.pending.shift()!;this.active=round;const store=this.store!,runtime=this.runtime!;
      const result=await this.executor.execute(round,runtime.renderer,store,{onEvent:event=>{
        this.activeId=event.jobId;
        if(event.type==='progress')this.progress={completed:event.completed,total:event.total};
        else {if(event.status==='running'||event.status==='queued')this.progress=null;const r=this.report?.records.find(r=>r.jobId===event.jobId);if(r&&['queued','running','unknown'].includes(event.status))r.status=event.status;}
        this.publish();
      },onComplete:record=>{
        const r=this.report?.records.findIndex(r=>r.jobId===record.jobId)??-1;if(r>=0)this.report!.records[r]=record;
        const j=this.report?.batch.jobs.find(j=>j.id===record.jobId);
        this.note(`${record.status}: ${j?.filename??record.jobId} · ${((record.elapsedMs??0)/1000).toFixed(2)}s`);this.publish();
      }});
      this.report=structuredClone(result);this.active=null;
      const failed=result.records.find(r=>round.jobs.some(j=>j.id===r.jobId)&&['failed','unknown'].includes(r.status));
      if(failed){this.error=failed.error??'Rendering failed.';this.uncertain=failed.status==='unknown';await this.clearPending();break;}
    }
  }
  private async clearPending():Promise<void>{
    const ids=new Set(this.pending.flatMap(r=>r.jobs.map(j=>j.id)));this.pending=[];
    if(this.store&&this.report){const records=this.report.records.filter(r=>ids.has(r.jobId)&&r.status==='queued').map(r=>({...r,status:'cancelled' as const}));await this.store.updateRecords(records);this.report=structuredClone(await this.store.load());}
  }
  async stop():Promise<DesktopState>{
    this.stopping=true;this.publish();
    await this.serial(async()=>{await this.clearPending();await this.executor.stop();});
    await this.execution;this.stopping=false;this.publish();return this.state();
  }
  async load(folder:string):Promise<{source:string;state:DesktopState}>{return this.serial(async()=>{
    if(this.state().busy)throw new Error('Stop the active batch before opening another.');
    const store=ReportStore.open(folder),report=structuredClone(await store.load());this.store=store;this.report=report;this.previewCache=null;
    this.uncertain=this.uncertain||report.records.some(r=>r.status==='unknown');
    this.error=this.uncertain?'Saved renderer work is unresolved. Check the dedicated renderer, then reselect its configuration before queueing new images.':null;
    this.note('Opened saved batch. Saved waiting work is not resumed.');this.publish();
    return {source:report.editorSource??report.batch.jobs.at(-1)?.source??'\n',state:this.state()};
  });}
  recipe(id:string):RecipeSnapshot {
    const job=this.report?.batch.jobs.find(j=>j.id===id);if(!job)throw new Error('Image is not in the open batch.');
    return structuredClone({job,environment:this.report!.runs.find(r=>r.id===job.runId)!});
  }
  async image(id:string):Promise<Uint8Array>{
    const {job}=this.recipe(id);if(this.report?.records.find(r=>r.jobId===id)?.status!=='completed')throw new Error('Image has not completed.');
    const folder=await realpath(this.store!.folder),file=await realpath(join(folder,job.filename)),rel=relative(folder,file);
    if(isAbsolute(rel)||rel==='..'||rel.startsWith('..'+sep))throw new Error('Image path leaves its batch folder.');
    return readFile(file);
  }
  async queueVariant(id:string,change:VariantChange):Promise<DesktopState>{return this.serial(async()=>{
    if(this.stopping||this.uncertain)throw new Error('Stop/reconcile renderer work before queueing a variant.');
    this.preparing=true;this.publish();
    try {
    const {job:source}=this.recipe(id);
    if(this.report?.records.find(r=>r.jobId===id)?.status!=='completed')throw new Error('Choose a completed source image.');
    if(!this.runtime||source.recipe.backend!==this.runtime.recipe.backend)throw new Error('Select the source image’s renderer backend before queueing a variant.');
    const context=await this.runtime.context();context.id=randomUUID();context.createdAt=new Date().toISOString();
    if(this.stopping)return this.state();
    let steps:number|undefined,shift:string|undefined;
    if('steps'in change){if(![4,6,7,8].includes(change.steps)||change.steps<=source.steps)throw new Error('Choose an available higher step count.');steps=change.steps;}
    else if('delta'in change){if(!['-1','-0.25','-0.1','-0.05','+0.05','+0.1','+0.25','+1'].includes(change.delta))throw new Error('Invalid shift adjustment.');shift=shifts(`(${source.shift})+(${change.delta})`)[0];}
    else {if(!/^(?:\d+(?:\.\d{1,3})?|\.\d{1,3})$/.test(change.shift.trim()))throw new Error('Enter a positive shift with at most three decimal places.');shift=shifts(change.shift)[0];}
    const job=variant(source,{steps,shift},this.lastNumber()+1,randomUUID(),context.id);
    const round:FrozenBatch=deepFreeze({schemaVersion:1,id:this.report!.batch.id,title:this.report!.batch.title,createdAt:context.createdAt,run:context,jobs:[job]});
    this.error=null;await this.persistRound(round,false);this.pending.push(round);this.note(`Queued variant: ${job.filename}`);if(!this.stopping)this.start();this.publish();return this.state();
    } finally {this.preparing=false;this.publish();}
  }).then(()=>this.state());}
  async idle():Promise<void>{await this.operations;while(this.execution)await this.execution;}
  close():void {this.runtime?.close();}
}

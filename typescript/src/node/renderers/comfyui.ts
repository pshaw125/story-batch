import { randomUUID, createHash } from 'node:crypto';
import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { ImageJob, RunContext } from '../../core/planning';
import { validateJob } from '../../core/reports';
import { Capabilities, RenderError } from '../../core/renderer';
import { runContext } from '../environment';
import { validatePNG, validateOutputSize } from '../png';
import { comfyWorkflow, Workflow, workflowNodes } from '../comfy-workflow';
import { Adapter, Entry } from './base';
export interface ComfyConfig { baseUrl:string; workRoot:string; dedicated:true; timeoutMs?:number }
type Json=Record<string,any>; // Native API payloads are validated at each boundary; no application code consumes them directly.
interface Remote { promptId:string; token:string; graph:Workflow; socket:WebSocket|null; cancelled:boolean; outputLoaded:boolean }
export class ComfyAdapter extends Adapter {
  readonly capabilities:Capabilities={backend:'comfyui',textToImage:true,imageToImage:false,loras:false,cancellation:true,progress:true,nativeControls:['seed','shift','steps','dimensions','guidance','sampler','scheduler']};
  private base:URL;
  private remotes=new Map<string,Remote>();
  constructor(readonly config:ComfyConfig){
    super();this.base=new URL(config.baseUrl);
    if(config.dedicated!==true||this.base.protocol!=='http:'||!['127.0.0.1','[::1]'].includes(this.base.hostname)||this.base.username||this.base.password||this.base.pathname!=='/'||this.base.search||this.base.hash)throw new RenderError('ComfyUI must be a dedicated local loopback HTTP service (127.0.0.1 or [::1]).','validation');
  }
  private async request(path:string, body?:unknown):Promise<Response>{
    return fetch(new URL(path,this.base),{method:body===undefined?'GET':'POST',headers:body===undefined?{}:{'content-type':'application/json'},body:body===undefined?undefined:JSON.stringify(body),redirect:'error',signal:AbortSignal.timeout(this.config.timeoutMs??10000)});
  }
  private async json(path:string,body?:unknown):Promise<Json>{
    const response=await this.request(path,body);if(!response.ok)throw new Error(`ComfyUI ${path}: HTTP ${response.status}: ${(await response.text()).slice(0,1000)}`);
    return response.json() as Promise<Json>;
  }
  async context():Promise<RunContext>{
    const stats=await this.json('/system_stats'), system=stats.system??{};
    const c=runContext('comfyui',String(system.comfyui_version??'unknown'));
    c.rendererOs={name:String(system.os??'unknown'),version:String(system.os_version??'unknown'),arch:String(system.arch??'unknown')};
    c.hardware=JSON.stringify(stats.devices??'unknown');c.computeRuntime=`Python ${system.python_version??'unknown'}; PyTorch ${system.pytorch_version??'unknown'}`;
    return c; // Loopback may bridge Windows to WSL; do not invent the service OS from the app host.
  }
  async validate(job:ImageJob):Promise<void>{
    try{
      validateJob(job);validateOutputSize(job.width,job.height);const graph=comfyWorkflow(job,'story-batch-validation');
      const info=await this.json('/object_info');
      for(const node of Object.values(graph)){
        if(!info[node.class_type])throw new Error(`Missing native node ${node.class_type}. Install the pinned ComfyUI build separately.`);
        const types={...info[node.class_type].input?.required,...info[node.class_type].input?.optional};
        for(const [key,value] of Object.entries(node.inputs)){
          const spec=types[key];if(!spec)throw new Error(`Unsupported node input ${node.class_type}.${key}.`);
          if(Array.isArray(value))continue; // Graph links, not user choices.
          if(Array.isArray(spec[0])&&!spec[0].includes(value))throw new Error(`Unsupported ${node.class_type}.${key}: ${value}`);
          if(typeof value==='number'&&(!Number.isFinite(value)||spec[1]?.min!==undefined&&value<spec[1].min||spec[1]?.max!==undefined&&value>spec[1].max))throw new Error(`Out-of-range ${node.class_type}.${key}: ${value}`);
        }
      }
      if(job.recipe.backend!=='comfyui')throw new Error('ComfyUI recipe required.');
      for(const [folder,asset] of [['diffusion_models',job.recipe.model],['text_encoders',job.recipe.textEncoder],['vae',job.recipe.vae]] as const){
        const response=await this.request(`/models/${folder}`);if(!response.ok)throw new Error(`Cannot inspect local ${folder}.`);
        const names:unknown=await response.json();if(!Array.isArray(names)||!names.includes(asset.id))throw new Error(`Missing local ${folder}: ${asset.id}. No download will be attempted.`);
      }
    }catch(error){throw new RenderError(String(error),'validation');}
  }
  protected async launch(e:Entry):Promise<void>{
    let queue:Json;
    try{queue=await this.json('/queue');}catch(error){throw new RenderError(`Cannot validate dedicated instance: ${String(error)}`,'validation');}
    if(!Array.isArray(queue.queue_running)||!Array.isArray(queue.queue_pending)||queue.queue_running.length||queue.queue_pending.length)throw new RenderError('Dedicated ComfyUI instance must be idle before submission.','validation');
    const token=randomUUID(), graph=comfyWorkflow(e.job,`story-batch/${token}`), remote:Remote={promptId:token,token,graph,socket:null,cancelled:false,outputLoaded:false};
    this.remotes.set(e.handle,remote);
    const folder=join(this.config.workRoot,createHash('sha256').update(e.handle).digest('hex'));await mkdir(folder,{recursive:true});
    const body={prompt:graph,prompt_id:token,client_id:token,extra_data:{story_batch:{token,jobId:e.job.id,attempt:e.attempt}}};
    await writeFile(join(folder,'submission.json'),JSON.stringify(body,null,2),{flag:'wx'});
    const wsUrl=new URL('/ws',this.base);wsUrl.protocol='ws:';wsUrl.searchParams.set('clientId',token);
    const ws=new WebSocket(wsUrl);remote.socket=ws;
    ws.addEventListener('error',()=>{}); // HTTP history remains authoritative after socket loss.
    ws.addEventListener('message',event=>{
      if(typeof event.data!=='string')return;
      try{const m=JSON.parse(event.data);if(m.data?.prompt_id!==remote.promptId)return;
        if(m.type==='progress'&&Number.isFinite(m.data.value)&&Number.isFinite(m.data.max))e.emit({jobId:e.job.id,type:'progress',completed:m.data.value,total:m.data.max});
      }catch{/* Binary previews and malformed progress never establish completion/failure. */}
    });
    // A socket is optional for completion, but let it connect before queueing for progress.
    await Promise.race([new Promise<void>(resolve=>{ws.addEventListener('open',()=>resolve(),{once:true});ws.addEventListener('error',()=>resolve(),{once:true});}),new Promise<void>(resolve=>setTimeout(resolve,1000))]);
    try{
      const response=await this.request('/prompt',body), json:Json=await response.json() as Json;
      if(!response.ok||!json.prompt_id)throw new RenderError(`ComfyUI rejected workflow: ${JSON.stringify(json)}`,'validation');
      remote.promptId=String(json.prompt_id);await writeFile(join(folder,'receipt.json'),JSON.stringify(json,null,2),{flag:'wx'});this.transition(e,'queued');
    }catch(error){
      if(error instanceof RenderError&&error.kind==='validation'){ws.close();throw error;}
      // Receipt is uncertain. Never POST again; reconcile ownership via token in queue/history.
      this.failed(e,new RenderError(`Submission acknowledgement uncertain: ${String(error)}`,'uncertain'));
    }
  }
  private owned(item:unknown,remote:Remote):item is any[]{return Array.isArray(item)&&(item[1]===remote.promptId||item[3]?.story_batch?.token===remote.token);}
  protected async refresh(e:Entry):Promise<void>{
    const remote=this.remotes.get(e.handle);if(!remote)return;
    try{
      let history=await this.json(`/history/${encodeURIComponent(remote.promptId)}`), found:Json|undefined=history[remote.promptId];
      if(!found){
        const queue=await this.json('/queue');
        for(const [key,status] of [['queue_running','running'],['queue_pending','queued']] as const){
          const items=queue[key];if(!Array.isArray(items))throw new Error('Malformed remote queue.');
          const match=items.find((item:unknown)=>this.owned(item,remote));
          if(match){remote.promptId=String(match[1]);this.transition(e,status);return;}
        }
        // Older servers may allocate their own prompt_id. Token survives lost acknowledgement.
        history=await this.json('/history');found=Object.values(history).find((h:Json)=>this.owned(h.prompt,remote));
      }
      if(!found){this.transition(e,'unknown');return;}
      if(!this.owned(found.prompt,remote)||JSON.stringify(found.prompt?.[2])!==JSON.stringify(remote.graph))throw new RenderError('Remote history does not match submitted workflow.','uncertain');
      remote.promptId=String(found.prompt[1]);
      const messages:unknown[]=Array.isArray(found.status?.messages)?found.status.messages:[];
      if(messages.some((m:any)=>m?.[0]==='execution_interrupted')){this.transition(e,'cancelled');remote.socket?.close();return;}
      if(found.status?.status_str==='error'||messages.some((m:any)=>m?.[0]==='execution_error')){
        const text=JSON.stringify(found.status);this.failed(e,new RenderError(text,remote.cancelled?'cancelled':'render'));remote.socket?.close();return;
      }
      if(!found.status?.completed){this.transition(e,'running');return;}
      const images=found.outputs?.['10']?.images;
      if(!Array.isArray(images)||images.length!==1||images[0].type!=='output')throw new RenderError('Workflow did not return one saved output image.','render');
      const image=images[0];
      if(typeof image.filename!=='string'||typeof image.subfolder!=='string')throw new RenderError('Invalid output identity.','render');
      const url='/view?'+new URLSearchParams({filename:image.filename,subfolder:image.subfolder,type:'output'});
      const response=await this.request(url);if(!response.ok)throw new Error(`Cannot retrieve completed output: HTTP ${response.status}`);
      const bytes=new Uint8Array(await response.arrayBuffer());
      const folder=join(this.config.workRoot,createHash('sha256').update(e.handle).digest('hex'));
      await writeFile(join(folder,'history.json'),JSON.stringify(found,null,2),{flag:'wx'});
      await writeFile(join(folder,'output.png'),bytes,{flag:'wx'});
      validatePNG(bytes,e.job.width,e.job.height);
      const cached=messages.some((m:any)=>m?.[0]==='execution_cached'&&m[1]?.nodes?.includes('8'));
      e.result={jobId:e.job.id,bytes,mediaType:'image/png',cached,effectiveJob:e.job,elapsedMs:performance.now()-e.started,observations:{frameworkJobId:remote.promptId}};
      remote.outputLoaded=true;this.transition(e,'completed');remote.socket?.close();
    }catch(error){
      if(error instanceof RenderError&&error.kind==='render'){this.failed(e,error);remote.socket?.close();}
      else this.failed(e,new RenderError(`Reconciliation uncertain: ${String(error)}`,'uncertain'));
    }
  }
  protected async interrupt(e:Entry):Promise<void>{
    const remote=this.remotes.get(e.handle);if(!remote)return;
    await this.refresh(e);if(['completed','failed','cancelled'].includes(e.status))return;
    const queue=await this.json('/queue');
    const running=queue.queue_running as unknown[],pending=queue.queue_pending as unknown[];
    if(!Array.isArray(running)||!Array.isArray(pending))throw new RenderError('Cannot confirm cancellation ownership.','uncertain');
    remote.cancelled=true;
    const queued=pending.find(i=>this.owned(i,remote));
    if(queued){await this.json('/queue',{delete:[remote.promptId]}).catch(async error=>{
      // Native /queue can return an empty 200 response; confirm through GET below.
      if(!(error instanceof SyntaxError))throw error;
    });}
    else if(running.some(i=>this.owned(i,remote))){
      // Refuse global interruption whenever unrelated work appears on this dedicated instance.
      if(running.some(i=>!this.owned(i,remote))||pending.some(i=>!this.owned(i,remote)))throw new RenderError('Foreign work prevents safe interruption.','uncertain');
      const response=await this.request('/interrupt',{prompt_id:remote.promptId});if(!response.ok)throw new RenderError('Interrupt request failed.','uncertain');
    }else {
      await this.refresh(e);if(['completed','failed','cancelled'].includes(e.status))return;
      throw new RenderError('Owned job is absent; reconcile before cancellation.','uncertain');
    }
    // Do not release the adapter until remote history/queue confirms it stopped.
    for(let i=0;i<40;i++){
      await this.refresh(e);if(['completed','failed','cancelled'].includes(e.status))return;
      const q=await this.json('/queue');
      if(![...q.queue_running,...q.queue_pending].some(item=>this.owned(item,remote))){this.transition(e,'cancelled');remote.socket?.close();return;}
      await new Promise(resolve=>setTimeout(resolve,50));
    }
    throw new RenderError('Cancellation is not yet confirmed.','uncertain');
  }
  close():void {for(const r of this.remotes.values())r.socket?.close();}
}
export {workflowNodes};

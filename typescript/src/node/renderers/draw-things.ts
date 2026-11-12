import { spawn, ChildProcess, execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { access, mkdir, open, readFile, writeFile } from 'node:fs/promises';
import {homedir} from 'node:os';
import { constants } from 'node:fs';
import { join, delimiter, dirname } from 'node:path';
import { createHash } from 'node:crypto';
import { ImageJob, RunContext } from '../../core/planning';
import { validateJob } from '../../core/reports';
import { Capabilities, RenderError } from '../../core/renderer';
import { runContext } from '../environment';
import { validatePNG, validateOutputSize } from '../png';
import {validateInput,readCanvas} from '../canvas';
import { Adapter, Entry } from './base';
export interface DrawThingsConfig { executablePath:string; workRoot:string; modelsDirectory?:string; timeoutMs?:number; argumentsPrefix?:string[] }
interface ProcessState { child:ChildProcess; done:Promise<void>; cancel:boolean }
export function drawThingsConfiguration(job:ImageJob):string {
  if(job.recipe.backend!=='draw-things')throw new RenderError('Draw Things recipe required.','validation');
  const r=job.recipe;
  const json=JSON.stringify({model:r.model.id,width:job.width,height:job.height,seed:job.seed,steps:job.steps,seedMode:r.seedMode,sampler:r.sampler,guidanceScale:r.guidance,
    resolutionDependentShift:false,batchSize:1,batchCount:1,strength:job.input?.strength??1,sharpness:0,loras:r.loras.map(l=>({file:l.asset.id,weight:l.modelWeight,...(l.nativeVersion?{version:l.nativeVersion}:{})})),controls:[],hiresFix:false,teaCache:false,tiledDiffusion:false,tiledDecoding:false,refinerModel:'',upscaler:''},null,2);
  // Shift remains numeric JSON while preserving supplied decimal precision.
  const canonical=job.shift.replace(/^\+/,'').replace(/^\./,'0.').replace(/^(0+)(?=\d)/,'').replace(/\.(?=[eE]|$)/,'');
  return json.slice(0,-1)+`,\n"shift":${canonical}\n}\n`;
}
export class DrawThingsAdapter extends Adapter {
  readonly capabilities:Capabilities={backend:'draw-things',textToImage:true,imageToImage:true,loras:true,cancellation:true,progress:true,nativeControls:['seed','shift','steps','dimensions','guidance','sampler','seedMode']};
  private processes=new Map<string,ProcessState>();
  constructor(readonly config:DrawThingsConfig){super();}
  async context():Promise<RunContext> {
    const {stdout}=await promisify(execFile)(this.config.executablePath,[...(this.config.argumentsPrefix??[]),'--version'],{timeout:10000,windowsHide:true});
    const context=runContext('draw-things-cli',stdout.trim()||'unknown');
    // A "dev" build still gets a stable executable identity in durable run details.
    context.computeRuntime=`CLI SHA256 ${createHash('sha256').update(await readFile(this.config.executablePath)).digest('hex')}; runtime unknown`;
    return context;
  }
  async validate(job:ImageJob):Promise<void> {
    try {
      validateJob(job);validateOutputSize(job.width,job.height);
      if(job.recipe.backend!=='draw-things'||job.recipe.negativePrompt===undefined)throw new Error('Draw Things recipe must include an explicit negative prompt.');
      for(const lora of job.recipe.loras){if(!/\.ckpt$/i.test(lora.asset.id)||/[\\/]/.test(lora.asset.id)||lora.encoderWeight!==null||!Number.isFinite(Math.fround(lora.modelWeight)))throw new Error('Use a converted local Draw Things .ckpt LoRA and a unified finite weight (encoderWeight=null); raw SafeTensors require separate conversion.');
        let models=this.config.modelsDirectory??process.env.DRAWTHINGS_MODELS_DIR;if(!models){if(process.platform==='darwin')models=join(homedir(),'Library/Containers/com.liuliu.draw-things/Data/Documents/Models');else{const adjacent=join(dirname(this.config.executablePath),'Models');try{await access(adjacent);models=adjacent;}catch{models=join(homedir(),'Documents/Models');}}}
        const file=await open(join(models,lora.asset.id),'r');try{const header=Buffer.alloc(16);await file.read(header,0,16,0);if(header.toString('binary')!=='SQLite format 3\x00')throw new Error('LoRA is not a converted Draw Things tensor store.');}finally{await file.close();}
        if(!lora.nativeVersion){let registered=false;try{const catalog=JSON.parse(await readFile(join(models,'custom_lora.json'),'utf8'));registered=Array.isArray(catalog)&&catalog.some((entry:{file?:string})=>entry.file===lora.asset.id);}catch{/* Explicit nativeVersion remains available. */}if(!registered)throw new Error('LoRA is not registered; provide its correct native version (for Z-Image: z_image).');}
      }
      await validateInput(job);
      if(!job.recipe.model.id.endsWith('.ckpt')||/[\\/]/.test(job.recipe.model.id))throw new Error('Use an imported local Draw Things checkpoint identifier.');
      await access(this.config.executablePath,constants.X_OK);
    } catch(e){throw new RenderError(String(e),'validation');}
  }
  protected async launch(e:Entry):Promise<void> {
    const folder=join(this.config.workRoot,createHash('sha256').update(e.handle).digest('hex'));
    await mkdir(this.config.workRoot,{recursive:true});
    await mkdir(folder,{recursive:false});
    await writeFile(join(folder,'prompt.txt'),e.job.prompt,{flag:'wx'});
    await writeFile(join(folder,'config.json'),drawThingsConfiguration(e.job),{flag:'wx'});
    const args=[...(this.config.argumentsPrefix??[]),'generate','--local','--offline','--no-download-missing','--model',e.job.recipe.model.id,
      '--prompt-file',join(folder,'prompt.txt'),'--config-file',join(folder,'config.json'),'--negative-prompt',e.job.recipe.backend==='draw-things'?e.job.recipe.negativePrompt!:'', '--seed',String(e.job.seed),'--output',join(folder,'output.png')];
    if(e.job.input){await writeFile(join(folder,'canvas.png'),await readCanvas(e.job.input.asset),{flag:'wx'});args.push('--image',join(folder,'canvas.png'),'--width',String(e.job.width),'--height',String(e.job.height),'--strength',String(e.job.input.strength));}
    if(this.config.modelsDirectory)args.push('--models-dir',this.config.modelsDirectory);
    await writeFile(join(folder,'invocation.json'),JSON.stringify({executable:this.config.executablePath,args},null,2),{flag:'wx'});
    const logFile=await open(join(folder,'renderer.log'),'wx');
    let writes:Promise<unknown>=Promise.resolve();
    let logError:unknown=null;
    const child=spawn(this.config.executablePath,args,{cwd:folder,shell:false,windowsHide:true,env:{...process.env,PATH:dirname(this.config.executablePath)+delimiter+(process.env.PATH??'')}});
    let log='', tail='';
    const data=(bytes:Buffer)=>{
      const text=bytes.toString('utf8');log=(log+text).slice(-65536);
      writes=writes.then(()=>logFile.write(bytes)).catch(error=>{logError=error;});
      tail=(tail+text).slice(-8192).replace(/\x1b\[[0-9;?]*[ -/]*[@-~]/g,'');
      const matches=[...tail.matchAll(/Sampling\.\.\.\s*(\d+)\s*\/\s*(\d+)/g)],last=matches.at(-1);
      if(last)e.emit({jobId:e.job.id,type:'progress',completed:Number(last[1]),total:Number(last[2])});
    };
    child.stdout.on('data',data);child.stderr.on('data',data);
    const state:ProcessState={child,cancel:false,done:Promise.resolve()};this.processes.set(e.handle,state);
    let timeout=false;
    const timer=setTimeout(()=>{timeout=true;child.kill('SIGTERM');setTimeout(()=>{if(child.exitCode===null&&child.signalCode===null)child.kill('SIGKILL');},1500).unref();},this.config.timeoutMs??30*60*1000);timer.unref();
    state.done=new Promise<void>(resolve=>{
      let launchError:Error|null=null;
      child.once('error',error=>{launchError=error;});
      child.once('close',async code=>{
        clearTimeout(timer);
        try {
          await writes;await logFile.close();if(logError)throw logError;
          if(state.cancel)this.failed(e,new RenderError('Cancelled by owner.','cancelled'));
          else if(launchError)this.failed(e,new RenderError(`Cannot launch renderer: ${launchError.message}`,'validation'));
          else if(timeout)this.failed(e,new RenderError('Renderer timed out after being terminated.','render'));
          else if(code!==0)this.failed(e,new RenderError(`Renderer exited ${code}: ${log.slice(-2000)}`,/missing|not found|not downloaded|unrecognized|unknown model/i.test(log)?'validation':'render'));
          else {
            const bytes=await readFile(join(folder,'output.png'));validatePNG(bytes,e.job.width,e.job.height);
            e.result={jobId:e.job.id,bytes,mediaType:'image/png',cached:false,effectiveJob:e.job,elapsedMs:performance.now()-e.started,observations:{
              reportedSamplingSteps:log.match(/Sampling step time \(([0-9]+) step/)?.[1]===undefined?undefined:Number(log.match(/Sampling step time \(([0-9]+) step/)![1]),
              reportedGenerationMs:log.match(/Total generation time \(including model loading\):\s*([0-9.]+)\s*s/)?.[1]===undefined?undefined:Number(log.match(/Total generation time \(including model loading\):\s*([0-9.]+)\s*s/)![1])*1000
            }};this.transition(e,'completed');
          }
        } catch(error){this.failed(e,error);}finally{this.processes.delete(e.handle);resolve();}
      });
    });
    this.transition(e,'running');
  }
  protected async refresh(_e:Entry):Promise<void>{}
  protected async interrupt(e:Entry):Promise<void>{
    const state=this.processes.get(e.handle);if(!state)return;
    state.cancel=true;state.child.kill('SIGTERM');
    const timer=setTimeout(()=>state.child.kill('SIGKILL'),1500);timer.unref();
    await state.done;clearTimeout(timer);
  }
}

import { readFile } from 'node:fs/promises';
import { resolve, dirname, join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { freezeBatch } from '../core/planning';
import { drawThingsPreset } from '../core/recipes';
import { comfyPreset } from './comfy-workflow';
import { DrawThingsAdapter } from './renderers/draw-things';
import { ComfyAdapter } from './renderers/comfyui';
import { ReportStore } from './storage';
import { BatchExecutor } from './executor';
async function main():Promise<void>{
  const args=new Map<string,string>();
  for(let i=2;i<process.argv.length;i+=2){const key=process.argv[i],value=process.argv[i+1];if(!['--config','--source','--output','--cancel-after-ms'].includes(key)||!value||args.has(key))throw new Error('Usage: npm run render -- --config renderer.local.json --source prompt.local.txt --output Batches [--cancel-after-ms 1000]');args.set(key,value);}
  if(!args.has('--config')||!args.has('--source')||!args.has('--output'))throw new Error('Specify --config, --source and --output. Rendering is explicit; no downloads are performed.');
  const configFile=resolve(args.get('--config')!),config=JSON.parse(await readFile(configFile,'utf8'));
  if(config.schemaVersion!==1)throw new Error('Unsupported renderer configuration schema.');
  const output=resolve(args.get('--output')!),workRoot=join(output,'.attempts');
  const renderer=config.backend==='draw-things'?new DrawThingsAdapter({executablePath:resolve(dirname(configFile),config.executablePath),modelsDirectory:config.modelsDirectory?resolve(dirname(configFile),config.modelsDirectory):undefined,workRoot})
    :config.backend==='comfyui'?new ComfyAdapter({baseUrl:config.baseUrl,dedicated:config.dedicated,workRoot}):null;
  if(!renderer)throw new Error('Choose draw-things or comfyui in local configuration.');
  const executor=new BatchExecutor();let timer:NodeJS.Timeout|undefined;
  let stopRequested=false;
  const stop=()=>{stopRequested=true;void executor.stop().catch(e=>console.error('Cancellation requires reconciliation:',e));};
  process.on('SIGINT',stop);process.on('SIGTERM',stop);
  try{
    const context=await renderer.context(),recipe=config.recipe??(config.backend==='draw-things'?drawThingsPreset():comfyPreset());
    const batch=freezeBatch(await readFile(resolve(args.get('--source')!),'utf8'),recipe,context,{random:Math.random,id:randomUUID});
    await renderer.validate(batch.jobs[0]);
    if(stopRequested)return;
    const store=await ReportStore.create(output,batch);
    console.log(`Report: ${join(store.folder,'report.json')}`);
    if(args.has('--cancel-after-ms')){
      const ms=Number(args.get('--cancel-after-ms'));if(!Number.isSafeInteger(ms)||ms<=0)throw new Error('Cancellation delay must be a positive integer.');
      timer=setTimeout(stop,ms);
    }
    const report=await executor.execute(batch,renderer,store,{onEvent:e=>console.log(JSON.stringify(e)),onComplete:r=>{
      const job=batch.jobs.find(j=>j.id===r.jobId)!;
      console.log(`${r.status}: ${job.filename} — ${((r.elapsedMs??0)/1000).toFixed(2)}s; seed=${job.seed}; shift=${job.shift}; steps=${job.steps}; cached=${r.cached??'unknown'}`);
    }});
    if(report.records.some(r=>['failed','unknown'].includes(r.status)))process.exitCode=1;
  }finally{if(timer)clearTimeout(timer);process.off('SIGINT',stop);process.off('SIGTERM',stop);if(renderer instanceof ComfyAdapter)renderer.close();}
}
if(require.main===module)void main().catch(e=>{console.error(e);process.exitCode=1;});

import { setTimeout as delay } from 'node:timers/promises';
import { FrozenBatch } from '../core/planning';
import { Renderer, RenderError, RenderEvent, JobStatus } from '../core/renderer';
import { BatchReport, ImageRecord } from '../core/reports';
import { ReportStore } from './storage';
import { validatePNG } from './png';
export interface ExecutionOptions { pollMs?:number; timeoutMs?:number; onEvent?:(event:RenderEvent)=>void; onComplete?:(record:ImageRecord)=>void }
/** Exactly one active image. Pending recipes already exist on disk before execution.
 * Unknown API work stops the queue; no new submission can hide a possible duplicate. */
export class BatchExecutor {
  private busy=false;
  private stopped=false;
  private skipped=false;
  private current:{renderer:Renderer;handle:string|null}|null=null;
  async stop():Promise<void>{this.stopped=true;if(this.current?.handle)await this.current.renderer.cancel(this.current.handle);}
  async skip():Promise<void>{if(!this.current)return;this.skipped=true;if(this.current.handle)await this.current.renderer.cancel(this.current.handle);}
  async execute(batch:FrozenBatch,renderer:Renderer,store:ReportStore,options:ExecutionOptions={}):Promise<BatchReport>{
    if(this.busy)throw new RenderError('An execution is already active.','validation');
    this.busy=true;this.stopped=false;
    try{
      const report:BatchReport=structuredClone(await store.load());
      if(report.batch.id!==batch.id||JSON.stringify(report.batch.jobs)!==JSON.stringify(batch.jobs)||report.records.some(r=>r.status!=='queued'))throw new RenderError('Execution requires a fresh, matching frozen queue; saved work never resumes implicitly.','validation');
      for(const [index,job] of batch.jobs.entries()){
        if(this.stopped)break;
        const record=report.records[index];this.skipped=false;this.current={renderer,handle:null};const start=performance.now();
        for(const attempt of [1,2] as const){
          if(this.stopped||this.skipped){record.status='cancelled';break;}
          record.attempts=attempt;record.status='running';await store.save(report);
          try{
            this.current.handle=await renderer.submit(job,event=>options.onEvent?.(event),{attempt});
            if(this.stopped||this.skipped)await renderer.cancel(this.current.handle);
            const deadline=performance.now()+(options.timeoutMs??30*60*1000);
            let status:JobStatus=await renderer.status(this.current.handle);
            while(['queued','running','unknown'].includes(status)&&performance.now()<deadline){
              await delay(options.pollMs??100);status=await renderer.status(this.current.handle);
            }
            if(['queued','running','unknown'].includes(status)){
              // An uncertain transport/API timeout is never a retryable render failure.
              try{await renderer.cancel(this.current.handle);}catch{/* Preserve uncertainty and stop subsequent work. */}
              status=await renderer.status(this.current.handle);
              if(!['cancelled','completed','failed'].includes(status))throw new RenderError('Timed out with uncertain renderer ownership; queue stopped for reconciliation.','uncertain');
            }
            if(status==='completed'){
              const result=await renderer.result(this.current.handle);if(!result)throw new RenderError('Completed result unavailable; reconcile instead of rerendering.','uncertain');
              validatePNG(result.bytes,job.width,job.height);
              if(JSON.stringify(result.effectiveJob)!==JSON.stringify(job))throw new RenderError('Renderer result differs from frozen native recipe.','validation');
              await store.writeOutput(job,result.bytes);record.status='completed';record.output=job.filename;
              record.cached=result.cached;record.rendererElapsedMs=result.elapsedMs;record.effectiveJob=result.effectiveJob;record.observations=result.observations;
              break;
            }
            if(status==='cancelled'){record.status='cancelled';break;}
            const failure=await renderer.failure?.(this.current.handle);
            throw failure??new RenderError('Renderer failed.','render');
          }catch(error){
            const failure=error instanceof RenderError?error:new RenderError(String(error),'validation');
            record.error=failure.message;
            if(this.stopped||this.skipped||failure.kind==='cancelled'){record.status='cancelled';break;}
            if(attempt===1&&failure.kind==='render')continue;
            record.status=failure.kind==='uncertain'?'unknown':'failed';this.stopped=true;break;
          }
        }
        record.elapsedMs=performance.now()-start;
        if(record.status==='completed')record.error=null;
        await store.save(report);options.onComplete?.(structuredClone(record));this.current=null;
      }
      for(const record of report.records)if(record.status==='queued')record.status='cancelled';
      await store.save(report);return report;
    }finally{this.current=null;this.busy=false;}
  }
}

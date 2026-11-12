import { deepFreeze } from '../../core/errors';
import { ImageJob } from '../../core/planning';
import { Capabilities, JobStatus, Renderer, RenderError, RenderEvent, RenderResult, Submission } from '../../core/renderer';
export interface Entry {
  handle: string; job: ImageJob; attempt: 1 | 2; status: JobStatus; started: number;
  result: RenderResult | null; error: RenderError | null; emit: (event: RenderEvent) => void;
}
/** Shared lifecycle only; queue policy belongs to BatchExecutor. Unknown work keeps
 * this adapter occupied until reconciliation or explicit cancellation confirms it ended. */
export abstract class Adapter implements Renderer {
  abstract readonly capabilities: Capabilities;
  protected entries = new Map<string, Entry>();
  private submitting = false;
  abstract validate(job: ImageJob): Promise<void>;
  protected abstract launch(entry: Entry): Promise<void>;
  protected abstract refresh(entry: Entry): Promise<void>;
  protected abstract interrupt(entry: Entry): Promise<void>;
  protected transition(e: Entry, status: JobStatus): void {
    if (e.status !== status) { e.status = status; e.emit({jobId:e.job.id,type:'status',status}); }
  }
  protected failed(e: Entry, error: unknown): void {
    e.error = error instanceof RenderError ? error : new RenderError(String(error),'render');
    this.transition(e, e.error.kind === 'uncertain' ? 'unknown' : e.error.kind === 'cancelled' ? 'cancelled' : 'failed');
  }
  async submit(job: ImageJob, emit: (event: RenderEvent) => void, s: Submission = {attempt:1}): Promise<string> {
    const handle = `${job.id}:attempt:${s.attempt}`, existing = this.entries.get(handle);
    if (existing) {
      if (JSON.stringify(existing.job) !== JSON.stringify(job)) throw new RenderError('Job ID reused with different frozen parameters.','validation');
      return handle;
    }
    if (![1,2].includes(s.attempt)) throw new RenderError('Only two render attempts are permitted.','validation');
    if (this.submitting || [...this.entries.values()].some(e => ['queued','running','unknown'].includes(e.status))) throw new RenderError('Renderer has active or uncertain work.','validation');
    if (s.attempt === 2) {
      const previous=this.entries.get(`${job.id}:attempt:1`);
      if (previous?.status !== 'failed' || previous.error?.kind !== 'render' || JSON.stringify(previous.job)!==JSON.stringify(job)) throw new RenderError('Retry needs a confirmed render failure and identical frozen job.','validation');
    }
    this.submitting = true;
    try {
      await this.validate(job);
      const entry:Entry={handle,job:deepFreeze(structuredClone(job)),attempt:s.attempt,status:'queued',started:performance.now(),result:null,error:null,emit};
      this.entries.set(handle,entry);emit({jobId:job.id,type:'status',status:'queued'});
      try {await this.launch(entry);} catch(error) {
        this.failed(entry,error);
        if (entry.error?.kind === 'validation') throw entry.error;
      }
      return handle;
    } finally {this.submitting=false;}
  }
  async status(handle:string):Promise<JobStatus> {
    const e=this.entries.get(handle);if(!e)return 'unknown';
    if(['queued','running','unknown'].includes(e.status)) await this.refresh(e);
    return e.status;
  }
  async result(handle:string):Promise<RenderResult|null> {const e=this.entries.get(handle);if(e)await this.status(handle);return e?.result?structuredClone(e.result):null;}
  release(handle:string):void {const e=this.entries.get(handle);if(e&&['completed','failed','cancelled'].includes(e.status))e.result=null;}
  async failure(handle:string):Promise<RenderError|null> {return this.entries.get(handle)?.error??null;}
  async cancel(handle:string):Promise<void> {
    const e=this.entries.get(handle);if(!e||['completed','cancelled','failed'].includes(e.status))return;
    await this.interrupt(e);
  }
}

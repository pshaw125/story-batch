import { deepFreeze } from './errors';
import { ImageJob } from './planning';
import { validateJob } from './reports';
import { Capabilities, JobStatus, Renderer, RenderError, RenderEvent, RenderResult, Submission } from './renderer';
// A synthetic 1x1 PNG. Fake results are marked in run context and are never inference evidence.
const png = [137,80,78,71,13,10,26,10,0,0,0,13,73,72,68,82,0,0,0,1,0,0,0,1,8,2,0,0,0,144,119,83,222,0,0,0,12,73,68,65,84,120,156,99,88,16,96,3,0,2,192,1,45,94,86,18,20,0,0,0,0,73,69,78,68,174,66,96,130];
interface Entry { job: ImageJob; status: JobStatus; result: RenderResult | null; events: (event: RenderEvent) => void; started: number }
export class FakeRenderer implements Renderer {
  readonly capabilities: Capabilities = deepFreeze({ backend: 'fake', textToImage: true, imageToImage: false, loras: false, cancellation: true, progress: true, nativeControls: ['seed','shift','steps','width','height'] });
  private entries = new Map<string, Entry>();
  async validate(job: ImageJob): Promise<void> {
    try { validateJob(job); } catch (e) { throw new RenderError(String(e), 'validation'); }
    if (!job.id || !Number.isSafeInteger(job.steps) || job.steps < 1 || job.recipe.loras.length) throw new RenderError('Invalid or unsupported fake job.', 'validation');
  }
  async submit(job: ImageJob, events: (event: RenderEvent) => void, submission: Submission = { attempt: 1 }): Promise<string> {
    await this.validate(job);
    const handle = `${job.id}:attempt:${submission.attempt}`;
    if (![1, 2].includes(submission.attempt)) throw new RenderError('Invalid render attempt.', 'validation');
    if (submission.attempt === 2) {
      const prior = this.entries.get(`${job.id}:attempt:1`);
      if (prior?.status !== 'failed' || JSON.stringify(prior.job) !== JSON.stringify(job)) throw new RenderError('Retry requires a confirmed failure and the identical frozen job.', 'validation');
    }
    const existing = this.entries.get(handle);
    if (existing) {
      if (JSON.stringify(existing.job) !== JSON.stringify(job)) throw new RenderError('Job ID reused with a different recipe.', 'validation');
      return handle;
    }
    if ([...this.entries.values()].some(e => e.status === 'running')) throw new RenderError('Fake renderer already has an active image.', 'validation');
    const entry: Entry = { job: deepFreeze(structuredClone(job)), status: 'running', result: null, events, started: performance.now() };
    this.entries.set(handle, entry); events({ jobId: job.id, type: 'status', status: 'running' });
    return handle;
  }
  async status(handle: string): Promise<JobStatus> { return this.entries.get(handle)?.status ?? 'unknown'; }
  async result(handle: string): Promise<RenderResult | null> { const r = this.entries.get(handle)?.result; return r ? structuredClone(r) : null; }
  async cancel(handle: string): Promise<void> {
    const e = this.entries.get(handle); if (e?.status !== 'running') return;
    e.status = 'cancelled'; e.events({ jobId: e.job.id, type: 'status', status: 'cancelled' });
  }
  fail(handle: string): void {
    const e = this.entries.get(handle);
    if (e?.status !== 'running') return;
    e.status = 'failed'; e.events({ jobId: e.job.id, type: 'status', status: 'failed' });
  }
  // Explicit advancement makes contract tests deterministic, independent of timers/GPU.
  advance(handle: string, completed: number): void {
    const e = this.entries.get(handle);
    if (!e || e.status !== 'running') return;
    e.events({ jobId: e.job.id, type: 'progress', completed: Math.min(completed, e.job.steps), total: e.job.steps });
    if (completed >= e.job.steps) {
      e.result = { jobId: e.job.id, bytes: new Uint8Array(png), mediaType: 'image/png', cached: false, effectiveJob: e.job, elapsedMs: performance.now() - e.started };
      e.status = 'completed'; e.events({ jobId: e.job.id, type: 'status', status: 'completed' });
    }
  }
}

import { FrozenBatch, ImageJob, RunContext, validateContext } from './planning';
import { validateRecipe } from './recipes';
import { shiftValue } from './arithmetic';
import { requireThat } from './errors';
import { JobStatus, NativeObservations } from './renderer';
export interface ImageRecord { observations?: NativeObservations; cached?: boolean; rendererElapsedMs?: number; effectiveJob?: ImageJob; jobId: string; status: JobStatus; attempts: number; elapsedMs: number | null; output: string | null; error: string | null }
export interface BatchReport { editorSource?: string; schemaVersion: 1; batch: FrozenBatch; runs: RunContext[]; records: ImageRecord[] }
export function validateJob(job: ImageJob): void {
  requireThat(job?.schemaVersion === 1 && [job.id, job.batchId, job.runId, job.title, job.filename].every(v => typeof v === 'string' && v.trim()), 'Invalid image identity.');
  requireThat(typeof job.prompt === 'string' && typeof job.source === 'string' && typeof job.notes === 'string', 'Invalid prompt snapshot.');
  requireThat(job.sharedFields && Object.values(job.sharedFields).every(v => typeof v === 'string'), 'Invalid resolved fields.');
  requireThat(!/[\\/:\u0000-\u001f]/.test(job.filename) && job.filename.endsWith('.png'), 'Unsafe output filename.');
  requireThat(Number.isSafeInteger(job.number) && job.number > 0 && Number.isSafeInteger(job.seed) && job.seed >= 0 && job.seed <= 2147483647,
    'Invalid image number or seed.');
  requireThat(Number.isSafeInteger(job.steps) && job.steps > 0 && [job.width, job.height].every(v => Number.isSafeInteger(v) && v > 0 && v % 64 === 0 && v <= 64 * 65535), 'Invalid image dimensions/steps.');
  shiftValue(job.shift); validateRecipe(job.recipe);
}
export function validateReport(value: BatchReport): void {
  requireThat(value?.schemaVersion === 1 && value.batch?.schemaVersion === 1, 'Unsupported report schema.');
  requireThat(value.editorSource===undefined||typeof value.editorSource==='string','Invalid editor source.');
  const b = value.batch;
  requireThat([b.id, b.title, b.createdAt].every(v => typeof v === 'string' && v.trim()) && !Number.isNaN(Date.parse(b.createdAt)), 'Invalid batch identity.');
  validateContext(b.run);
  requireThat(Array.isArray(value.runs) && value.runs.length > 0, 'Report needs run contexts.');
  const runIds = new Set<string>();
  for (const run of value.runs) { validateContext(run); requireThat(!runIds.has(run.id), 'Duplicate run context.'); runIds.add(run.id); }
  requireThat(JSON.stringify(value.runs[0]) === JSON.stringify(b.run), 'Initial run context changed.');
  requireThat(Array.isArray(b.jobs) && Array.isArray(value.records) && value.records.length === b.jobs.length, 'Invalid report jobs/records.');
  const ids = new Set<string>(), numbers = new Set<number>(), names = new Set<string>();
  for (const job of b.jobs) {
    validateJob(job);
    requireThat(job.batchId === b.id && runIds.has(job.runId) && job.title === b.title, 'Job belongs to a different batch/run.');
    requireThat(!ids.has(job.id) && !numbers.has(job.number) && !names.has(job.filename), 'Duplicate image identity.');
    ids.add(job.id); numbers.add(job.number); names.add(job.filename);
  }
  const recordIds = new Set<string>(), jobsById = new Map(b.jobs.map(j => [j.id, j]));
  for (const r of value.records) {
    requireThat(ids.has(r.jobId) && !recordIds.has(r.jobId) && ['queued','running','completed','cancelled','failed','unknown'].includes(r.status), 'Invalid record identity/status.'); recordIds.add(r.jobId);
    requireThat(Number.isSafeInteger(r.attempts) && r.attempts >= 0 && r.attempts <= 2 && (r.elapsedMs === null || Number.isFinite(r.elapsedMs) && r.elapsedMs >= 0), 'Invalid attempt/timing.');
    const job = jobsById.get(r.jobId)!;
    requireThat(r.output === null || r.output === job.filename, 'Output differs from planned filename.');
    requireThat(r.error === null || typeof r.error === 'string', 'Invalid record error.');
    requireThat(r.status !== 'completed' || r.output === job.filename, 'Completed image needs an output identity.');
    if(r.effectiveJob!==undefined){validateJob(r.effectiveJob);requireThat(JSON.stringify(r.effectiveJob)===JSON.stringify(job),'Applied recipe differs from frozen job.');}
    requireThat(r.cached===undefined||typeof r.cached==='boolean','Invalid cache flag.');
    requireThat(r.rendererElapsedMs===undefined||Number.isFinite(r.rendererElapsedMs)&&r.rendererElapsedMs>=0,'Invalid renderer timing.');
  }
}
export function appendRound(report: BatchReport, round: FrozenBatch, updateEditorSource = true): BatchReport {
  validateReport(report);
  requireThat(round.id === report.batch.id && round.title === report.batch.title, 'Round title/batch identity differs.');
  requireThat(!report.runs.some(r => r.id === round.run.id), 'Round run identifier already exists.');
  const last = report.batch.jobs.reduce((n, j) => Math.max(n, j.number), 0);
  requireThat(round.jobs.every((j, i) => j.number === last + i + 1), 'Continuation numbering must follow existing jobs.');
  const result: BatchReport = {
    schemaVersion: 1,
    editorSource: updateEditorSource ? round.jobs[0]?.source ?? report.editorSource : report.editorSource ?? report.batch.jobs.at(-1)?.source,
    batch: { ...structuredClone(report.batch), jobs: [...structuredClone(report.batch.jobs), ...structuredClone(round.jobs)] },
    runs: [...structuredClone(report.runs), structuredClone(round.run)],
    records: [...structuredClone(report.records), ...round.jobs.map(j => ({ jobId: j.id, status: 'queued' as const, attempts: 0, elapsedMs: null, output: null, error: null }))]
  };
  validateReport(result); return result;
}

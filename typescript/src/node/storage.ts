import { mkdir, readFile, writeFile, rename, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { FrozenBatch, ImageJob } from '../core/planning';
import { BatchReport, validateReport, validateJob } from '../core/reports';
export { BatchReport, appendRound } from '../core/reports';
import { deepFreeze, requireThat } from '../core/errors';
/** One owner per store. Serialize replacements, write within the batch, then rename.
 * Reload returns state for inspection only; it never starts interrupted jobs. */
export class ReportStore {
  private tail: Promise<void> = Promise.resolve();
  private constructor(readonly folder: string) {}
  static async create(root: string, batch: FrozenBatch): Promise<ReportStore> {
    requireThat(/^[A-Za-z0-9_-]+$/.test(batch.id), 'Unsafe batch folder identity.');
    const report: BatchReport = { schemaVersion: 1, batch, runs: [batch.run], records: batch.jobs.map(j => ({ jobId: j.id, status: 'queued', attempts: 0, elapsedMs: null, output: null, error: null })) };
    validateReport(report);
    await mkdir(root, { recursive: true });
    const folder = join(root, batch.id); await mkdir(folder); // exclusive; never reuse an existing batch
    const store = new ReportStore(folder); await store.save(report); return store;
  }
  static open(folder: string): ReportStore { return new ReportStore(folder); }
  async load(): Promise<Readonly<BatchReport>> {
    await this.tail;
    const parsed: BatchReport = JSON.parse(await readFile(join(this.folder, 'report.json'), 'utf8'));
    validateReport(parsed); return deepFreeze(parsed);
  }
  save(report: BatchReport): Promise<void> {
    const snapshot = structuredClone(report); validateReport(snapshot);
    const next = this.tail.then(async () => {
      let previous: BatchReport | null = null;
      try { previous = JSON.parse(await readFile(join(this.folder, 'report.json'), 'utf8')); }
      catch (error) { if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error; }
      if (previous) {
        validateReport(previous);
        requireThat(previous.batch.id === snapshot.batch.id && previous.batch.title === snapshot.batch.title && previous.batch.createdAt === snapshot.batch.createdAt,
          'Cannot change saved batch identity.');
        requireThat(previous.batch.jobs.every((job, i) => JSON.stringify(job) === JSON.stringify(snapshot.batch.jobs[i])) &&
          previous.runs.every((run, i) => JSON.stringify(run) === JSON.stringify(snapshot.runs[i])), 'Cannot change or remove frozen jobs/run contexts.');
      }
      const temp = join(this.folder, `.report-${randomUUID()}.tmp`);
      try { await writeFile(temp, JSON.stringify(snapshot, null, 2) + '\n', { flag: 'wx' }); await rename(temp, join(this.folder, 'report.json')); }
      finally { await rm(temp, { force: true }); }
    });
    this.tail = next.catch(() => {}); return next;
  }
  async writeOutput(job: ImageJob, bytes: Uint8Array): Promise<void> {
    validateJob(job);
    requireThat(bytes.length >= 8 && [137,80,78,71,13,10,26,10].every((v, i) => bytes[i] === v), 'Invalid PNG signature.');
    // Full dimensions/completeness validation belongs to real adapters in Phase 2.
    const saved = await this.load(); requireThat(saved.batch.jobs.some(j => JSON.stringify(j) === JSON.stringify(job)), 'Output job does not match the frozen report.');
    await writeFile(join(this.folder, job.filename), bytes, { flag: 'wx' });
  }
}

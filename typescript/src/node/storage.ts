import { access, mkdir, readFile, writeFile, rename, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { FrozenBatch, ImageJob, safeTitle } from '../core/planning';
import { appendRound, BatchReport, ImageRecord, validateReport, validateJob } from '../core/reports';
export { BatchReport, appendRound } from '../core/reports';
import {readCanvas,digest} from './canvas';
import { deepFreeze, requireThat } from '../core/errors';
/** One owner per store. All updates read inside the writer queue so an active
 * image cannot overwrite a round appended while it was rendering. */
export class ReportStore {
  private tail: Promise<void> = Promise.resolve();
  private constructor(readonly folder: string) {}
  static async create(root: string, batch: FrozenBatch): Promise<ReportStore> {
    requireThat(/^[A-Za-z0-9_-]{1,80}$/.test(batch.id), 'Unsafe batch folder identity.');
    const report: BatchReport = { schemaVersion: 1, batch, editorSource: batch.jobs[0]?.source ?? '', runs: [batch.run], records: batch.jobs.map(j => ({ jobId: j.id, status: 'queued', attempts: 0, elapsedMs: null, output: null, error: null })) };
    validateReport(report);
    await mkdir(root, { recursive: true });
    // Keep old UUID-only folders addressable; never recreate an existing identity.
    try{await access(join(root,batch.id));throw new Error('Batch identity already exists.');}catch(error){if((error as NodeJS.ErrnoException).code!=='ENOENT')throw error;}
    const stamp=new Date(batch.createdAt).toISOString().replace(/[:.]/g,'-');
    const folder=join(root,`${stamp}_${safeTitle(batch.title,80)}_${batch.id}`);await mkdir(folder);
    const store = new ReportStore(folder); await store.save(report);await store.archiveInputs(batch.jobs); return store;
  }
  static open(folder: string): ReportStore { return new ReportStore(folder); }
  private async read(): Promise<BatchReport> {
    const report: BatchReport = JSON.parse(await readFile(join(this.folder, 'report.json'), 'utf8'));
    validateReport(report); return report;
  }
  load(): Promise<Readonly<BatchReport>> {
    const next=this.tail.then(()=>this.read());
    this.tail=next.then(()=>{},()=>{});
    return next.then(report=>deepFreeze(report));
  }
  private change(update: (previous: BatchReport | null) => BatchReport): Promise<void> {
    const next = this.tail.then(async () => {
      let previous: BatchReport | null = null;
      try { previous = await this.read(); }
      catch (error) { if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error; }
      const snapshot = update(previous); validateReport(snapshot);
      if (previous) {
        requireThat(previous.batch.id === snapshot.batch.id && previous.batch.title === snapshot.batch.title && previous.batch.createdAt === snapshot.batch.createdAt, 'Cannot change saved batch identity.');
        requireThat(previous.batch.jobs.every((job, i) => JSON.stringify(job) === JSON.stringify(snapshot.batch.jobs[i])) && previous.runs.every((run, i) => JSON.stringify(run) === JSON.stringify(snapshot.runs[i])), 'Cannot change or remove frozen jobs/run contexts.');
      }
      const temp = join(this.folder, `.report-${randomUUID()}.tmp`);
      try { await writeFile(temp, JSON.stringify(snapshot, null, 2) + '\n', { flag: 'wx' }); await rename(temp, join(this.folder, 'report.json')); }
      finally { await rm(temp, { force: true }); }
    });
    this.tail = next.catch(() => {}); return next;
  }
  save(report: BatchReport): Promise<void> { const snapshot = structuredClone(report); return this.change(() => snapshot); }
  async append(round: FrozenBatch, updateEditorSource = true): Promise<void> {
    await this.change(previous => { requireThat(previous, 'Batch report is missing.'); return appendRound(previous, round, updateEditorSource); });await this.archiveInputs(round.jobs);
  }
  updateRecords(records: readonly ImageRecord[]): Promise<void> {
    const snapshots = structuredClone(records);
    return this.change(previous => {
      requireThat(previous, 'Batch report is missing.');
      for (const record of snapshots) { const i = previous.records.findIndex(r => r.jobId === record.jobId); requireThat(i >= 0, 'Unknown image record.'); previous.records[i] = record; }
      return previous;
    });
  }
  private async archiveInputs(jobs:readonly ImageJob[]):Promise<void>{const assets=new Map(jobs.flatMap(j=>j.input?[j.input.asset,j.input.original]:[]).map(a=>[a.hash,a]));if(!assets.size)return;await mkdir(join(this.folder,'inputs'),{recursive:true});for(const asset of assets.values()){const bytes=await readCanvas(asset),file=join(this.folder,'inputs',asset.hash+'.png');try{await writeFile(file,bytes,{flag:'wx'});}catch(error){if((error as NodeJS.ErrnoException).code!=='EEXIST')throw error;if(digest(await readFile(file))!==asset.hash)throw new Error('Archived canvas changed; refusing to overwrite.');}}}
  async claim(id:string):Promise<ImageRecord>{
    let claimed:ImageRecord|undefined;
    await this.change(previous=>{
      requireThat(previous,'Batch report is missing.');const record=previous.records.find(r=>r.jobId===id);requireThat(record?.status==='queued','Image is already claimed or unavailable.');
      const index=previous.records.reduce((n,r)=>Math.max(n,r.executionIndex??(r.attempts>0?previous.batch.jobs.find(j=>j.id===r.jobId)!.number:0)),0)+1;
      record.executionIndex=index;record.startedAt=new Date().toISOString();record.status='running';claimed=structuredClone(record);return previous;
    });return claimed!;
  }
  selection(id:string,kind:'shortlisted'|'rejected',value:boolean):Promise<void>{return this.change(previous=>{
    requireThat(previous&&previous.batch.jobs.some(j=>j.id===id),'Unknown selection image.');
    previous.selections??={};const flags=previous.selections[id]??{shortlisted:false,rejected:false};flags[kind]=value;
    if(flags.shortlisted||flags.rejected)previous.selections[id]=flags;else delete previous.selections[id];return previous;
  });}
  queueOrder(ids:readonly string[]):Promise<void>{return this.change(previous=>{requireThat(previous,'Batch report is missing.');previous.queueOrder=[...ids];return previous;});}
  async writeOutput(job: ImageJob, bytes: Uint8Array): Promise<void> {
    validateJob(job);
    requireThat(bytes.length >= 8 && [137,80,78,71,13,10,26,10].every((v, i) => bytes[i] === v), 'Invalid PNG signature.');
    const saved = await this.load(); requireThat(saved.batch.jobs.some(j => JSON.stringify(j) === JSON.stringify(job)), 'Output job does not match the frozen report.');
    await writeFile(join(this.folder, job.filename), bytes, { flag: 'wx' });
  }
}

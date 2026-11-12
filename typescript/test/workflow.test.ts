import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, readFile, writeFile, readdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { freezeBatch, variant, RunContext } from '../src/core/planning';
import { drawThingsPreset, NativeRecipe, unknownAsset } from '../src/core/recipes';
import { FakeRenderer } from '../src/core/fake-renderer';
import { RenderEvent } from '../src/core/renderer';
import { ReportStore, BatchReport } from '../src/node/storage';
import { hostProbe } from '../src/node/host-probe';
function factory() {
  let id = 0;
  const run: RunContext = { id: 'run-1',createdAt:'2026-11-11T12:00:00Z',os:{name:'test-os',version:'test',arch:'test'},framework:{name:'fake',version:'1'},hardware:'unknown',driver:'unknown',computeRuntime:'unknown',applicationVersion:'test' };
  const recipe = drawThingsPreset();
  return { recipe, run, options: { random: () => .5, id: () => `id-${++id}`, now: 1000000 } };
}
test('frozen jobs survive draft/recipe edits, pair lists, and retain all chosen settings', () => {
  const f = factory(), b = freezeBatch('title=synthetic;count=3;seed=7,_,_;shift=1.3,1.4,1.5\n[COLOR] [COLOR]\n%%FIELDS%%\nCOLOR={red|blue}', f.recipe, f.run, f.options);
  f.recipe.model.id = 'edited'; f.run.os.version = 'edited';
  assert.equal(b.jobs[0].recipe.model.id,'z_image_turbo_1.0_q6p.ckpt'); assert.equal(b.run.os.version,'test');
  assert.deepEqual(b.jobs.map(j=>j.seed),[7,1073741824,1073741824]);
  assert.deepEqual(b.jobs.map(j=>j.shift),['1.3','1.4','1.5']);
  assert.ok(b.jobs.every(j=>j.prompt==='blue blue'));
  assert.equal(b.jobs[0].filename,'synthetic_7_3_1.3_1.png');
  assert.throws(()=>{ b.jobs[0].recipe.model.id='mutated'; }, TypeError);
  assert.deepEqual(JSON.parse(JSON.stringify(b)).jobs,b.jobs);
});
test('random seeds/shifts are independent from prompt choices, endpoints inclusive', () => {
  const f=factory(); let i=0; const draws=[0,0,.999999999,.999999999];
  const b=freezeBatch('count=2\nplain',f.recipe,f.run,{...f.options,random:()=>draws[i++]});
  assert.deepEqual(b.jobs.map(j=>[j.seed,j.shift]),[[0,'1.500'],[2147483645,'2.250']]); assert.equal(i,4);
});
test('continuation is title-based and variants keep resolved prompt/native recipe', () => {
  const f=factory(), a=freezeBatch('title=one;count=1;seed=1;shift=4.550123\nOriginal',f.recipe,f.run,f.options);
  const b=freezeBatch('count=1\nChanged prompt',f.recipe,f.run,{...f.options,continuing:{id:a.id,title:a.title,lastNumber:10}});
  assert.equal(b.id,a.id);assert.equal(b.jobs[0].number,11);assert.equal(b.jobs[0].prompt,'Changed prompt');
  assert.throws(()=>freezeBatch('title=two\nx',f.recipe,f.run,{...f.options,continuing:{id:a.id,title:a.title,lastNumber:10}}),/title/);
  const v=variant(a.jobs[0],{steps:6},12,'variant','run-2');assert.equal(v.prompt,'Original');assert.equal(v.shift,'4.550123');assert.equal(v.steps,6);assert.deepEqual(v.recipe,a.jobs[0].recipe);
  assert.throws(()=>variant(a.jobs[0],{steps:6,shift:'2'},13,'x','y'));
});
test('tagged native settings never reinterpret sampler 17 as a portable sampler', () => {
  const f=factory();
  const comfy: NativeRecipe = {backend:'comfyui',model:unknownAsset('synthetic-model','bf16'),textEncoder:unknownAsset('synthetic-encoder'),vae:unknownAsset('synthetic-vae'),
    guidance:1,loras:[],sampler:'native-test',scheduler:'native-test',noisePolicy:'native',workflow:{id:'synthetic',version:'1',hash:'unknown',nodes:{test:'1'}}};
  const b=freezeBatch('count=1\nx',comfy,f.run,f.options);assert.equal(b.jobs[0].recipe.backend,'comfyui');
  assert.throws(()=>freezeBatch('\nx',{...comfy,sampler:17} as unknown as NativeRecipe,f.run,f.options));
  assert.throws(()=>freezeBatch('\nx',f.recipe,{...f.run,os:{...f.run.os,version:''}},f.options));
});
test('cross-platform filenames remove unsafe characters and stay under byte budget', () => {
  const f=factory(), b=freezeBatch(`title=${'a/\\:<>"|?*☕'.repeat(50)};count=1;shift=4.550000\nx`,f.recipe,f.run,f.options);
  assert.ok(!/[\\/:<>"|?*]/.test(b.jobs[0].filename)); assert.ok(Buffer.byteLength(b.jobs[0].filename)<=250);
});
test('fake submission/status/progress/result/cancel contract, no concurrent jobs or ID reuse', async () => {
  const f=factory(), b=freezeBatch('count=2;shift=1.75;seed=9\nx',f.recipe,f.run,f.options), r=new FakeRenderer(), events:RenderEvent[]=[];
  const h=await r.submit(b.jobs[0],e=>events.push(e));assert.equal(await r.status(h),'running');assert.equal(await r.result(h),null);
  assert.equal(await r.submit(b.jobs[0],()=>{}),h);
  await assert.rejects(r.submit({...b.jobs[0],shift:'2'},()=>{}),/different recipe/);
  await assert.rejects(r.submit(b.jobs[1],()=>{}),/active/);
  r.advance(h,1);assert.equal(events.at(-1)?.type,'progress');
  await r.cancel(h); r.advance(h,3); assert.equal(await r.status(h),'cancelled');assert.equal(await r.result(h),null);
  const next=await r.submit(b.jobs[1],()=>{});r.advance(next,3);assert.equal(await r.status(next),'completed');
  assert.equal((await r.result(next))?.cached,false);assert.deepEqual((await r.result(next))?.effectiveJob,b.jobs[1]);
  assert.equal(await r.status('missing'),'unknown');await r.cancel('missing');
});
test('persistence round-trip, immutable reload, cancellation, interrupted work never resumes, output never overwrites', async () => {
  const root=await mkdtemp(join(tmpdir(),'story-batch-test-'));
  try {
    const f=factory(), b=freezeBatch('count=2;resolution=64*64\nsynthetic',f.recipe,f.run,f.options), s=await ReportStore.create(root,b);
    const r=new FakeRenderer(), report:BatchReport=structuredClone(await s.load());
    const h=await r.submit(b.jobs[0],()=>{});report.records[0].status='running';report.records[0].attempts=1;await s.save(report);
    const reload=await ReportStore.open(s.folder).load();assert.equal(reload.records[0].status,'running');
    assert.throws(()=>{reload.batch.jobs[0].prompt='edit';},TypeError);
    await r.cancel(h);report.records[0].status='cancelled';await s.save(report);
    const next=await r.submit(b.jobs[1],()=>{});r.advance(next,3);const result=(await r.result(next))!;
    await s.writeOutput(b.jobs[1],result.bytes);await assert.rejects(s.writeOutput(b.jobs[1],result.bytes),/EEXIST/);
    report.records[1]={jobId:b.jobs[1].id,status:'completed',attempts:1,elapsedMs:result.elapsedMs,output:b.jobs[1].filename,error:null};await s.save(report);
    assert.deepEqual((await s.load()).batch,b);assert.equal((await s.load()).records[0].status,'cancelled');
    await assert.rejects(ReportStore.create(root,b),/EEXIST/);
    assert.ok((await readFile(join(s.folder,b.jobs[1].filename))).length>0);
    assert.deepEqual((await readdir(s.folder)).sort(),[b.jobs[1].filename,'report.json'].sort());
    await writeFile(join(s.folder,'report.json'),'{"schemaVersion":99}');await assert.rejects(s.load(),/schema/);
  } finally {await rm(root,{recursive:true,force:true});}
});
test('storage rejects path traversal, duplicate jobs and malformed provenance', async () => {
  const f=factory(), b=freezeBatch('count=1\nx',f.recipe,f.run,f.options), root=await mkdtemp(join(tmpdir(),'story-batch-reject-'));
  try {
    await assert.rejects(ReportStore.create(root,{...b,id:'../escape'}),/Unsafe/);
    await assert.rejects(ReportStore.create(root,{...b,jobs:[{...b.jobs[0],filename:'../outside.png'}]}),/Unsafe/);
    await assert.rejects(ReportStore.create(root,{...b,jobs:[b.jobs[0],b.jobs[0]]}),/Duplicate/);
  } finally {await rm(root,{recursive:true,force:true});}
});
test('host filesystem, child process and local API are available without external services', async () => {
  const result=await hostProbe();assert.ok(result);
});
test('retry contract permits exactly one confirmed-failure retry with the frozen job', async () => {
  const f=factory(), b=freezeBatch('count=1\nx',f.recipe,f.run,f.options), r=new FakeRenderer(), j=b.jobs[0];
  await assert.rejects(r.submit(j,()=>{}, {attempt:2}),/confirmed/);
  const first=await r.submit(j,()=>{});
  await assert.rejects(r.submit(j,()=>{}, {attempt:2}),/confirmed/);
  r.fail(first);assert.equal(await r.status(first),'failed');
  await assert.rejects(r.submit({...j,shift:'3'},()=>{}, {attempt:2}),/identical/);
  const retry=await r.submit(j,()=>{}, {attempt:2});assert.notEqual(retry,first);
  r.advance(retry,3);assert.deepEqual((await r.result(retry))?.effectiveJob,j);
  await assert.rejects(r.submit(j,()=>{}, {attempt:3} as never),/Invalid/);
});
test('multiple frozen rounds retain per-run context in the same persisted batch', async () => {
  const { appendRound } = await import('../src/core/reports');
  const root=await mkdtemp(join(tmpdir(),'story-batch-rounds-'));
  try {
    const f=factory(), first=freezeBatch('title=rounds;count=1\nfirst',f.recipe,f.run,f.options), s=await ReportStore.create(root,first);
    const nextRun={...f.run,id:'run-2',framework:{name:'other-native-version',version:'2'}};
    const next=freezeBatch('count=2;steps=6\nsecond',f.recipe,nextRun,{...f.options,continuing:{id:first.id,title:first.title,lastNumber:1}});
    const combined=appendRound(structuredClone(await s.load()),next);await s.save(combined);
    const loaded=await s.load();assert.equal(loaded.runs.length,2);assert.equal(loaded.batch.jobs[0].runId,'run-1');
    assert.deepEqual(loaded.batch.jobs.map(j=>j.number),[1,2,3]);assert.deepEqual(loaded.batch.jobs.map(j=>j.prompt),['first','second','second']);
    assert.throws(()=>appendRound(combined,next),/already exists/);
  } finally {await rm(root,{recursive:true,force:true});}
});
test('storage refuses edits to already-frozen jobs and preserves the prior report', async () => {
  const root=await mkdtemp(join(tmpdir(),'story-batch-frozen-'));
  try {
    const f=factory(), b=freezeBatch('count=1\noriginal',f.recipe,f.run,f.options), s=await ReportStore.create(root,b);
    const edited:BatchReport=structuredClone(await s.load());edited.batch.jobs[0].prompt='changed';
    await assert.rejects(s.save(edited),/frozen/);assert.equal((await s.load()).batch.jobs[0].prompt,'original');
  } finally {await rm(root,{recursive:true,force:true});}
});

import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm,readFile,readdir}from 'node:fs/promises';
import {tmpdir}from 'node:os';import{join}from'node:path';import{randomUUID}from'node:crypto';
import{setTimeout as delay}from'node:timers/promises';
import{freezeBatch}from'../src/core/planning';import{drawThingsPreset}from'../src/core/recipes';
import{runContext}from'../src/node/environment';import{DrawThingsAdapter}from'../src/node/renderers/draw-things';
import{ComfyAdapter}from'../src/node/renderers/comfyui';import{comfyPreset}from'../src/node/comfy-workflow';
import{BatchExecutor}from'../src/node/executor';import{ReportStore}from'../src/node/storage';import{fakeComfy}from'./fixtures/comfy-server';
import{validatePNG}from'../src/node/png';
async function draw(mode:string, action:(r:DrawThingsAdapter,root:string)=>Promise<void>,timeoutMs=2000){const root=await mkdtemp(join(tmpdir(),'story-draw-test-'));try{await action(new DrawThingsAdapter({executablePath:process.execPath,argumentsPrefix:[join(__dirname,'../../test/fixtures/fake-draw-things.cjs'),'--test-mode',mode],workRoot:join(root,'attempts'),timeoutMs}),root);}finally{await rm(root,{recursive:true,force:true});}}
function batch(backend:'draw'|'comfy',extra='count=2') {return freezeBatch(`${extra};resolution=64*64;seed=1234;shift=1.7500\nsynthetic`,backend==='draw'?drawThingsPreset():comfyPreset(),runContext('synthetic-test','1'),{random:()=>.5,id:randomUUID});}
async function wait(r:DrawThingsAdapter|ComfyAdapter,h:string){for(let i=0;i<500;i++){const s=await r.status(h);if(['completed','failed','cancelled'].includes(s))return s;await delay(5);}throw new Error('Test renderer did not finish.');}
test('Draw Things: exact offline invocation, native settings, progress and validated PNG',async()=>draw('success',async(r,root)=>{
 const b=batch('draw','count=1'),events:unknown[]=[];const h=await r.submit(b.jobs[0],e=>events.push(e));assert.equal(await wait(r,h),'completed');
 const result=(await r.result(h))!;validatePNG(result.bytes,64,64);assert.equal(result.cached,false);assert.equal(result.observations?.reportedSamplingSteps,3);assert.equal(result.observations?.reportedGenerationMs,1250);assert.ok(events.length>2);
 const dirs=await readdir(join(root,'attempts'));const folder=join(root,'attempts',dirs[0]);
 const config=JSON.parse(await readFile(join(folder,'config.json'),'utf8'));assert.equal(config.shift,1.75);assert.equal(config.sampler,17);assert.equal(config.seedMode,2);assert.equal(config.batchSize,1);
 const invocation=JSON.parse(await readFile(join(folder,'invocation.json'),'utf8'));for(const flag of['--local','--offline','--no-download-missing'])assert.ok(invocation.args.includes(flag));
 assert.equal((await r.context()).framework.version,'synthetic-cli-1');
}));
for(const mode of['incomplete','wrong-size'])test(`Draw Things rejects ${mode} output`,async()=>draw(mode,async r=>{const h=await r.submit(batch('draw','count=1').jobs[0],()=>{});assert.equal(await wait(r,h),'failed');assert.equal((await r.failure(h))?.kind,'render');}));
test('Draw Things and executor recover once with frozen parameters, preserving failed partial output',async()=>draw('once',async(r,root)=>{
 const b=batch('draw'),s=await ReportStore.create(join(root,'batches'),b);const report=await new BatchExecutor().execute(b,r,s,{pollMs:5});
 assert.deepEqual(report.records.map(x=>[x.status,x.attempts]),[['completed',2],['completed',1]]);
 assert.deepEqual(report.records[0].effectiveJob,b.jobs[0]);assert.equal(report.records[0].cached,false);
 const attempts=await readdir(join(root,'attempts'));assert.ok(attempts.length>=3);assert.ok((await s.load()).records.every(r=>r.output));
}));
for(const mode of['failure','missing'])test(`executor stops waiting jobs after ${mode}`,async()=>draw(mode,async(r,root)=>{
 const b=batch('draw'),s=await ReportStore.create(join(root,'batches'),b),report=await new BatchExecutor().execute(b,r,s,{pollMs:5});
 assert.equal(report.records[0].status,'failed');assert.equal(report.records[0].attempts,mode==='failure'?2:1);assert.equal(report.records[1].status,'cancelled');
}));
test('Draw Things launch validation does not render/retry',async()=>draw('success',async(r,root)=>{const missing=new DrawThingsAdapter({...r.config,executablePath:join(root,'missing')});await assert.rejects(missing.submit(batch('draw','count=1').jobs[0],()=>{}),/validation|ENOENT/);}));
test('skip targets only the current image and leaves the next job usable',async()=>draw('hang',async(r,root)=>{
 const b=batch('draw'),s=await ReportStore.create(join(root,'batches'),b),executor=new BatchExecutor();let skipped=false;
 const pending=executor.execute(b,r,s,{pollMs:5,onEvent:event=>{if(event.type==='status'&&event.status==='running'&&!skipped){skipped=true;void executor.skip();}}});
 // Second job has a deliberate short process timeout, proving it starts after skip.
 const report=await pending;assert.equal(report.records[0].status,'cancelled');assert.equal(report.records[0].attempts,1);assert.equal(report.records[1].attempts,2);
},80));
test('stop terminates current and clears waiting work without retry',async()=>draw('hang',async(r,root)=>{
 const b=batch('draw'),s=await ReportStore.create(join(root,'batches'),b),executor=new BatchExecutor();let stopped=false;
 const report=await executor.execute(b,r,s,{pollMs:5,onEvent:event=>{if(event.type==='status'&&event.status==='running'&&!stopped){stopped=true;void executor.stop();}}});
 assert.deepEqual(report.records.map(r=>r.status),['cancelled','cancelled']);assert.equal(report.records[1].attempts,0);
}));
async function comfy(mode:string,action:(r:ComfyAdapter,root:string,server:Awaited<ReturnType<typeof fakeComfy>>)=>Promise<void>){const server=await fakeComfy(mode),root=await mkdtemp(join(tmpdir(),'story-comfy-test-')),r=new ComfyAdapter({baseUrl:server.url,dedicated:true,workRoot:join(root,'attempts'),timeoutMs:500});try{await action(r,root,server);}finally{r.close();await server.close();await rm(root,{recursive:true,force:true});}}
for(const mode of['success','lost-socket','lost-ack','lost-ack-assigned','cached'])test(`ComfyUI ${mode} completes without duplicate submission`,async()=>comfy(mode,async(r,_root,server)=>{
 const b=batch('comfy','count=1'),h=await r.submit(b.jobs[0],()=>{});assert.equal(await wait(r,h),'completed');const result=(await r.result(h))!;
 assert.equal(server.posts.length,1);assert.equal(result.cached,mode==='cached');validatePNG(result.bytes,64,64);
 assert.equal(server.posts[0].prompt['7'].inputs.shift,1.75);assert.equal(server.posts[0].prompt['8'].inputs.seed,1234);
 assert.equal((await r.context()).framework.version,'synthetic-1');
}));
for(const mode of['missing-model','missing-node','invalid-workflow'])test(`ComfyUI validation: ${mode} never retries`,async()=>comfy(mode,async(r,root,server)=>{
 const b=batch('comfy'),s=await ReportStore.create(join(root,'batches'),b),report=await new BatchExecutor().execute(b,r,s,{pollMs:5});
 assert.equal(report.records[0].status,'failed');assert.equal(report.records[0].attempts,1);assert.equal(server.posts.length,mode==='invalid-workflow'?1:0);
}));
for(const mode of['incomplete','wrong-size','failure'])test(`ComfyUI ${mode} stops after bounded retry`,async()=>comfy(mode,async(r,root,server)=>{
 const b=batch('comfy'),s=await ReportStore.create(join(root,'batches'),b),report=await new BatchExecutor().execute(b,r,s,{pollMs:5});
 assert.equal(report.records[0].status,'failed');assert.equal(report.records[0].attempts,2);assert.equal(report.records[1].attempts,0);assert.equal(server.posts.length,2);
}));
test('ComfyUI one transient failure recovers and continues queue',async()=>comfy('once',async(r,root,server)=>{
 const b=batch('comfy'),s=await ReportStore.create(join(root,'batches'),b),report=await new BatchExecutor().execute(b,r,s,{pollMs:5});
 assert.deepEqual(report.records.map(r=>r.attempts),[2,1]);assert.ok(report.records.every(r=>r.status==='completed'));assert.equal(server.posts.length,3);
}));
for(const mode of['hang','queued'])test(`ComfyUI cancellation owns ${mode} job and leaves service usable`,async()=>comfy(mode,async(r,_root,server)=>{
 const b=batch('comfy'),h=await r.submit(b.jobs[0],()=>{});await r.cancel(h);assert.equal(await r.status(h),'cancelled');assert.equal(server.interrupts,mode==='hang'?1:0);
 const next=await r.submit(b.jobs[1],()=>{});await r.cancel(next);assert.equal(await r.status(next),'cancelled');
}));
test('ComfyUI refuses interruption if foreign work appears',async()=>comfy('foreign',async(r,_root,server)=>{
 const h=await r.submit(batch('comfy','count=1').jobs[0],()=>{});await assert.rejects(r.cancel(h),/Foreign/);assert.equal(server.interrupts,0);
}));
test('uncertain submission timeout stops queue without blind retry',async()=>comfy('uncertain',async(r,root,server)=>{
 const b=batch('comfy'),s=await ReportStore.create(join(root,'batches'),b),report=await new BatchExecutor().execute(b,r,s,{pollMs:5,timeoutMs:40});
 assert.equal(report.records[0].status,'unknown');assert.equal(report.records[0].attempts,1);assert.equal(report.records[1].attempts,0);assert.equal(server.posts.length,1);
}));
test('ComfyUI forbids external URL, credentials, and shared-instance configuration',()=>{
 for(const baseUrl of['https://127.0.0.1:8188','http://example.com:8188','http://user:password@127.0.0.1:8188','http://127.0.0.1:8188/prefix'])assert.throws(()=>new ComfyAdapter({baseUrl,workRoot:tmpdir(),dedicated:true}));
});
test('PNG validation rejects corrupt CRC and truncated pixel data',async()=>{
 const {PNG}=await import('pngjs');const png=new PNG({width:64,height:64});png.data.fill(80);const bytes=PNG.sync.write(png);
 validatePNG(bytes,64,64);const corrupt=Buffer.from(bytes);corrupt[29]^=1;assert.throws(()=>validatePNG(corrupt,64,64),/Invalid/);
 assert.throws(()=>validatePNG(bytes.subarray(0,bytes.length-10),64,64),/Invalid/);
});

test('native decode limits reject oversized requests before process submission',async()=>draw('success',async r=>{
 await assert.rejects(r.validate({...batch('draw','count=1').jobs[0],width:16384,height:8192}),/64-megapixel/);
}));

import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm,readFile,writeFile,symlink} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {randomUUID} from 'node:crypto';
import {setTimeout as delay} from 'node:timers/promises';
import type {BatchReport} from '../src/core/reports';
import {DesktopSession} from '../src/node/desktop-session';
import {syntheticRuntime} from '../src/node/runtime';
import {ReportStore} from '../src/node/storage';
import {freezeBatch} from '../src/core/planning';
import {drawThingsPreset} from '../src/core/recipes';
import {runContext} from '../src/node/environment';
async function session(action:(session:DesktopSession,root:string)=>Promise<void>,tick=5):Promise<void>{const root=await mkdtemp(join(tmpdir(),'story-desktop-test-'));const service=new DesktopSession(root);await service.setRuntime(syntheticRuntime(tick));try{await action(service,root);}finally{await service.stop();service.close();await rm(root,{recursive:true,force:true});}}
const doc=(parameters:string,prompt='A [COLOR] circle.',fields='COLOR={red|blue}')=>`${parameters}\n${prompt}\n%%FIELDS%%\n${fields}`;
async function active(service:DesktopSession):Promise<void>{for(let i=0;i<100;i++){if(service.state().activeId)return;await delay(5);}throw new Error('No active image.');}
test('preview selections are reused, snapshots persist, and output has requested dimensions',async()=>session(async(s)=>{
 const source=doc('title=preview;count=4;steps=2;seed=_*;shift=1.5..2;resolution=64*64');
 const preview=await s.preview(source);await s.queue(source);await s.idle();const state=s.state();
 assert.ok(state.folder?.includes('_preview_'));assert.equal(state.images.length,4);assert.ok(state.images.every(i=>i.status==='completed'));
 for(let i=0;i<4;i++){const recipe=s.recipe(state.images[i].id);assert.deepEqual(recipe.job,preview.images[i]);assert.equal(recipe.environment.framework.name,'synthetic-renderer');}
 const {PNG}=await import('pngjs');const image=PNG.sync.read(Buffer.from(await s.image(state.images[0].id)));assert.equal(image.width,64);assert.equal(image.height,64);
}));
test('Queue More persists frozen rounds while active; edits do not split a title or change queued jobs',async()=>session(async(s)=>{
 const first=doc('title=continuity;count=4;steps=25;seed=7;shift=1.75;resolution=64*64','First [COLOR] scene.');
 const second=doc('title=continuity;count=4;steps=2;seed=7,_*;shift=1.5,1.6..1.8*;resolution=64*64','Second [COLOR] scene.','COLOR={green|gold}');
 await s.queue(first);await active(s);const batch=s.state().batchId;
 await assert.rejects(s.queue(doc('title=changed;count=1;resolution=64*64')),/new batch|title/i);
 await assert.rejects(s.queue(first,true),/new batch|title/i);
 await s.queue(second);assert.equal(s.state().images.length,8);assert.equal(s.state().batchId,batch);await s.idle();
 assert.deepEqual(s.state().images.map(i=>i.number),[1,2,3,4,5,6,7,8]);assert.ok(s.state().images.every(i=>i.status==='completed'));
 const report=await ReportStore.open(s.state().folder!).load();assert.equal(report.runs.length,2);assert.equal(report.editorSource,second);
 assert.ok(report.batch.jobs.slice(0,4).every(j=>j.prompt.startsWith('First')));assert.ok(report.batch.jobs.slice(4).every(j=>j.prompt.startsWith('Second')));
}));
test('force-new and changed-title requests start separate folders, restarting numbering',async()=>session(async(s)=>{
 const source=doc('title=one;count=1;steps=1;resolution=64*64');await s.queue(source);await s.idle();const first=s.state().folder;
 await s.preview(source);await s.queue(source,true);await s.idle();const second=s.state().folder;assert.notEqual(second,first);assert.equal(s.state().images[0].number,1);
 await s.queue(doc('title=two;count=1;steps=1;resolution=64*64'));await s.idle();assert.notEqual(s.state().folder,second);assert.equal(s.state().title,'two');
}));
test('viewer variants preserve original recipe and resolved prompt, and reload keeps the latest editor source',async()=>session(async(s)=>{
 const original=doc('title=variants;count=1;steps=2;seed=19;shift=1.7500;resolution=64*64','Original [COLOR] scene.');
 await s.queue(original);await s.idle();const id=s.state().images[0].id,originalJob=s.recipe(id).job;
 const edited=doc('count=1;steps=2;seed=21;shift=2;resolution=64*64','Later editor scene.');await s.queue(edited);await s.idle();
 const legacyStore=ReportStore.open(s.state().folder!),legacy=structuredClone(await legacyStore.load()) as BatchReport;delete legacy.editorSource;await legacyStore.save(legacy);await s.load(legacyStore.folder);
 await s.queueVariant(id,{steps:6});await s.idle();const variant=s.recipe(s.state().images[2].id).job;
 assert.equal(variant.prompt,originalJob.prompt);assert.deepEqual(variant.recipe,originalJob.recipe);assert.equal(variant.seed,19);assert.equal(variant.shift,'1.7500');assert.equal(variant.steps,6);
 await s.queueVariant(id,{delta:'+0.05'});await s.idle();assert.equal(s.state().images[3].shift,'1.8');
 await assert.rejects(s.queueVariant(id,{shift:'1.2345'}),/three decimal/);await assert.rejects(s.queueVariant(id,{shift:'0'}),/positive/);
 const loaded=await s.load(s.state().folder!);assert.equal(loaded.source,edited);assert.equal(loaded.state.busy,false);assert.equal(loaded.state.images.length,4);
}));
test('stop clears current and persisted waiting rounds; completed files survive; continuation reserves cancelled numbers',async()=>session(async(s)=>{
 const first=doc('title=stop;count=1;steps=1;resolution=64*64');await s.queue(first);await s.idle();const initial=s.state().images[0].id;
 await s.queue(doc('title=stop;count=3;steps=100;resolution=64*64'));await active(s);await s.queue(doc('title=stop;count=2;steps=1;resolution=64*64'));
 await s.stop();assert.equal(s.state().busy,false);assert.equal(s.state().images[0].status,'completed');assert.ok(s.state().images.slice(1).every(i=>i.status==='cancelled'));assert.ok((await s.image(initial)).length>0);
 await s.queue(first);await s.idle();assert.equal(s.state().images.at(-1)?.number,7);assert.equal(s.state().images.at(-1)?.status,'completed');
}));
test('opening saved waiting/running records never resumes them; fresh continuation executes only new jobs',async()=>session(async(s,root)=>{
 const source=doc('title=interrupted;count=2;steps=1;resolution=64*64');
 const batch=freezeBatch(source,drawThingsPreset(),runContext('synthetic','1'),{random:()=>.5,id:randomUUID});const store=await ReportStore.create(root,batch);
 const report=structuredClone(await store.load());report.records[0].status='running';report.records[0].attempts=1;await store.save(report);
 const opened=await s.load(store.folder);assert.deepEqual(opened.state.images.map(i=>i.status),['interrupted','interrupted']);assert.equal(opened.state.busy,false);
 await s.queue(doc('title=interrupted;count=1;steps=1;resolution=64*64'));await s.idle();assert.deepEqual(s.state().images.map(i=>i.status),['interrupted','interrupted','completed']);
}));
test('three four-image workflow batches at 1MP use synthetic rendering only',async()=>session(async(s)=>{
 for(const [index,params]of ['seed=7;shift=1.75','seed=7,_*;shift=1.5,1.6..1.8*','seed=_*;shift=(1.5,1.6,1.7,1.8)+0.05'].entries()){
  await s.queue(doc(`title=workflow ${index};count=4;steps=1;aspect=1:1;${params}`));await s.idle();assert.equal(s.state().images.length,4);assert.ok(s.state().images.every(i=>i.status==='completed'&&i.width===1024&&i.height===1024));
 }
}));
test('invalid drafts and renderer changes cannot alter an active frozen queue',async()=>session(async(s)=>{
 await assert.rejects(s.queue('\n'),/empty/);await s.queue(doc('title=guards;count=1;steps=30;resolution=64*64'));await active(s);
 await assert.rejects(s.setRuntime(syntheticRuntime()),/Stop/);await assert.rejects(s.load('/missing'),/Stop/);await assert.rejects(s.queue(doc('title=guards;count=3;seed=1,2;resolution=64*64')),/count/);
 assert.equal(s.state().images.length,1);await s.idle();assert.equal(s.state().images[0].status,'completed');
}));
test('image lookup rejects unknown IDs and paths redirected outside a chosen batch',async()=>session(async(s,root)=>{
 await s.queue(doc('title=files;count=1;steps=1;resolution=64*64'));await s.idle();await assert.rejects(s.image('unknown'),/open batch/);
 const image=s.state().images[0],file=join(s.state().folder!,image.filename),outside=join(root,'outside.png');await writeFile(outside,await readFile(file));await rm(file);
 // Symlink creation may require Developer Mode on Windows; skip that platform-specific check there.
 if(process.platform!=='win32'){await symlink(outside,file);await assert.rejects(s.image(image.id),/leaves/);}
}));
test('metaprompt Open/Save preserves separate editor data and rejects invalid opens without changing the save target',async()=>{
 const {MetapromptFiles}=await import('../src/node/metaprompt-files');const root=await mkdtemp(join(tmpdir(),'story-prompt-files-'));
 try{
  const files=new MetapromptFiles(),a=join(root,'first.txt'),b=join(root,'second.txt'),invalid=join(root,'invalid.txt');
  const source=doc('title=files;count=4','A [COLOR] shape.','COLOR={red|blue}\nDESCRIPTION=Multiple\nlines.');
  await assert.rejects(files.save(source),/Choose/);await files.save(source,a);assert.deepEqual(await files.open(a),{source,path:a});
  const changed=source.replace('red|blue','red|blue|green');await files.save(changed);assert.equal(await readFile(a,'utf8'),changed);
  await files.save(source,b);await writeFile(invalid,'missing header newline');await assert.rejects(files.open(invalid),/newline/);assert.equal(files.path,b);
  assert.equal(await readFile(a,'utf8'),changed);assert.equal(await readFile(b,'utf8'),source);
 }finally{await rm(root,{recursive:true,force:true});}
});
test('desktop session uses configured ComfyUI API without a synthetic fallback',async()=>{
 const {fakeComfy}=await import('./fixtures/comfy-server');const {configuredRuntime}=await import('../src/node/runtime');
 const server=await fakeComfy(),root=await mkdtemp(join(tmpdir(),'story-desktop-comfy-')),service=new DesktopSession(root);
 try{
  const file=join(root,'renderer.local.json');await writeFile(file,JSON.stringify({schemaVersion:1,backend:'comfyui',baseUrl:server.url,dedicated:true}));
  await service.setRuntime(await configuredRuntime(file,join(root,'.attempts')));
  await service.queue(doc('title=comfy desktop;count=4;steps=3;seed=7,_*;shift=1.5,1.6..1.8*;resolution=64*64'));await service.idle();
  assert.equal(service.state().renderer,'ComfyUI');assert.equal(server.posts.length,4);assert.ok(service.state().images.every(i=>i.status==='completed'));
  const recipe=service.recipe(service.state().images[0].id);assert.equal(recipe.environment.framework.version,'synthetic-1');assert.equal(recipe.job.recipe.backend,'comfyui');
  await service.queueVariant(service.state().images[0].id,{delta:'+0.05'});await service.idle();assert.equal(server.posts.length,5);assert.equal(service.state().images[4].shift,'1.55');
 }finally{await service.stop();service.close();await server.close();await rm(root,{recursive:true,force:true});}
});
test('saved uncertain renderer work blocks submission until an explicit renderer reset',async()=>session(async(s,root)=>{
 const source=doc('title=uncertain desktop;count=1;steps=1;resolution=64*64'),b=freezeBatch(source,drawThingsPreset(),runContext('synthetic','1'),{random:()=>.5,id:randomUUID}),store=await ReportStore.create(root,b);
 const report=structuredClone(await store.load());report.records[0].status='unknown';report.records[0].attempts=1;report.records[0].error='Disconnected';await store.save(report);
 const opened=await s.load(store.folder);assert.equal(opened.state.uncertain,true);assert.equal(opened.state.images[0].status,'unresolved');await assert.rejects(s.queue(source),/reconciled/);
 await s.setRuntime(syntheticRuntime(5));await s.queue(source);await s.idle();assert.equal(s.state().images[0].status,'unresolved');assert.equal(s.state().images[1].status,'completed');
}));
test('a viewer variant rebases an outstanding preview without rerolling its frozen choices',async()=>session(async(s)=>{
 const original=doc('title=preview rebase;count=1;steps=1;seed=7;shift=1.75;resolution=64*64');await s.queue(original);await s.idle();const first=s.state().images[0].id;
 const draft=doc('title=preview rebase;count=1;steps=1;seed=_;shift=1.5..2;resolution=64*64');const preview=await s.preview(draft);
 await s.queueVariant(first,{steps:4});await s.idle();await s.queue(draft);await s.idle();
 const job=s.recipe(s.state().images[2].id).job;assert.equal(job.id,preview.images[0].id);assert.equal(job.number,3);assert.equal(job.seed,preview.images[0].seed);assert.equal(job.shift,preview.images[0].shift);assert.equal(job.prompt,preview.images[0].prompt);
}));
test('stop during async preparation prevents later submission and permits a fresh request',async()=>{
 const root=await mkdtemp(join(tmpdir(),'story-prepare-stop-')),s=new DesktopSession(root),runtime=syntheticRuntime(5);
 let ready!:()=>void;const gate=new Promise<void>(resolve=>{ready=resolve;});runtime.context=async()=>{await gate;return runContext('synthetic','1');};
 try{
  await s.setRuntime(runtime);const source=doc('title=prepare stop;count=1;steps=1;resolution=64*64'),queued=s.queue(source);
  for(let i=0;i<100&&!s.state().busy;i++)await delay(1);assert.equal(s.state().busy,true);assert.equal(s.state().activeId,null);
  const stopped=s.stop();ready();await queued;await stopped;assert.equal(s.state().images.length,0);assert.equal(s.state().busy,false);
  await s.queue(source);await s.idle();assert.equal(s.state().images[0].status,'completed');
 }finally{ready();await s.stop();s.close();await rm(root,{recursive:true,force:true});}
});
test('rapid continuations cannot regress completed statuses or lose already-published jobs',async()=>session(async(s)=>{
 const terminal=new Map<string,string>();let previousCount=0;const regressions:string[]=[];
 const unsubscribe=s.subscribe(state=>{
  if(state.images.length<previousCount)regressions.push('Image list shrank');previousCount=state.images.length;
  for(const image of state.images){const old=terminal.get(image.id);if(old&&old!==image.status)regressions.push(`${old} -> ${image.status}`);if(['completed','cancelled','failed'].includes(image.status))terminal.set(image.id,image.status);}
 });
 try{
  const source=doc('title=concurrent publications;count=2;steps=1;resolution=64*64');await s.queue(source);
  await Promise.all(Array.from({length:8},()=>s.queue(source)));await s.idle();assert.equal(s.state().images.length,18);assert.ok(s.state().images.every(i=>i.status==='completed'));assert.deepEqual(regressions,[]);
 }finally{unsubscribe();}
},1));

import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,readFile,writeFile,rm,readdir,access} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {setTimeout as delay} from 'node:timers/promises';
import {DesktopSession} from '../src/node/desktop-session';
import {syntheticRuntime} from '../src/node/runtime';
import {ReportStore} from '../src/node/storage';
import {DraftStore,emptyDraft} from '../src/node/draft-store';
import {sortedImages,galleryImages} from '../src/core/gallery';
import {replaceParameter} from '../src/core/editor-values';
import {compile} from '../src/core/prompt';
async function session(run:(s:DesktopSession,root:string)=>Promise<void>):Promise<void>{const root=await mkdtemp(join(tmpdir(),'story-iteration-')),s=new DesktopSession(root);await s.setRuntime(syntheticRuntime(10));try{await run(s,root);}finally{await s.stop();s.close();await rm(root,{recursive:true,force:true});}}
const source=(params='count=4;seed=10,20,30,40;shift=1,2,3,4',steps=25)=>`title=iteration;${params};steps=${steps};resolution=64*64\nA synthetic shape.`;
async function running(s:DesktopSession):Promise<void>{for(let i=0;i<200;i++){if(s.state().images.some(i=>i.status==='running'))return;await delay(2);}throw new Error('Image did not start.');}
test('queue reorder and removal preserve frozen pairing; collectors follow execution order, not gallery order',async()=>session(async(s)=>{
 await s.queue(source());await running(s);const original=s.state().images,ids=original.map(i=>i.id),jobs=ids.map(id=>s.recipe(id).job);
 await s.reorder(ids[3],'next');assert.deepEqual(s.state().waiting,[ids[3],ids[1],ids[2]]);
 await s.reorder(ids[2],'up');assert.deepEqual(s.state().waiting,[ids[3],ids[2],ids[1]]);
 await s.reorder(ids[2],'down');await s.cancelQueued(ids[1]);await s.idle();
 const report=await ReportStore.open(s.state().folder!).load();assert.deepEqual(report.batch.jobs,jobs);
 const used=report.records.filter(r=>r.status==='completed').sort((a,b)=>a.executionIndex!-b.executionIndex!);assert.deepEqual(used.map(r=>r.jobId),[ids[0],ids[3],ids[2]]);
 const edited=source('count=3;seed=1;shift=1',3),seeds=await s.collect(edited,'seeds'),shifts=await s.collect(edited,'shift');
 assert.deepEqual(compile(seeds).parameters.seeds,[10,40,30]);assert.deepEqual(compile(shifts).parameters.shifts.map(x=>x.kind==='fixed'?x.value:null),['1','4','3']);
 assert.equal(report.records.find(r=>r.jobId===ids[1])!.attempts,0);assert.deepEqual(report.queueOrder,[]);
 await assert.rejects(s.reorder(ids[0],'next'),/started/);await assert.rejects(s.cancelQueued(ids[0]),/started/);
}));
test('skip cancels one running image; stop after current clears waiting work and allows an explicit continuation',async()=>session(async(s)=>{
 await s.queue(source());await running(s);const first=s.state().activeId!;await s.skip(first);
 for(let i=0;i<200;i++){if(s.state().activeId&&s.state().activeId!==first)break;await delay(2);}
 await assert.rejects(s.skip(first),/current image changed/);await s.stopAfter();await s.idle();
 assert.deepEqual(s.state().images.map(i=>i.status),['cancelled','completed','cancelled','cancelled']);
 const report=await ReportStore.open(s.state().folder!).load();assert.equal(report.records[0].attempts,1);assert.equal(report.records[1].attempts,1);assert.equal(report.records[2].attempts,0);
 await s.queue(source('count=1;seed=99;shift=2',1));await s.idle();assert.equal(s.state().images.at(-1)?.number,5);assert.equal(s.state().images.at(-1)?.status,'completed');
}));
test('cancel before first completion removes only a newly created empty batch and archives its report',async()=>session(async(s,root)=>{
 await s.queue(source());await running(s);const state=s.state(),folder=state.folder!,id=state.batchId!;await s.stop();
 assert.equal(s.state().folder,null);await assert.rejects(access(folder),/ENOENT/);const saved=await ReportStore.open(join(root,'.attempts','cancelled-batches',id)).load();assert.ok(saved.records.every(r=>r.status==='cancelled'));
 await s.queue(source('count=1;seed=1;shift=1',1));await s.idle();const kept=s.state().folder!;await s.queue(source());await running(s);await s.stop();assert.equal(s.state().folder,kept);await access(kept);
}));
test('shortlist/reject are independent, survive rendering and reload; shortlist variants include running placeholders',async()=>session(async(s)=>{
 await s.queue(source('count=1;seed=7;shift=2',1));await s.idle();const id=s.state().images[0].id;
 await s.toggleSelection(id,'shortlisted');await s.toggleSelection(id,'rejected');assert.equal(galleryImages(s.state(),'images','seeded').length,0);assert.equal(galleryImages(s.state(),'shortlist','seeded').length,1);
 await s.queueVariant(id,{steps:8},true);const child=s.state().images[1].id;assert.ok(galleryImages(s.state(),'shortlist','seeded').some(i=>i.id===child&&i.status!=='completed'));
 await s.toggleSelection(id,'rejected');await s.idle();await s.load(s.state().folder!);assert.ok(s.state().images.every(i=>i.shortlisted));assert.ok(s.state().images.every(i=>!i.rejected));
 await s.toggleSelection(id,'shortlisted');assert.deepEqual(galleryImages(s.state(),'shortlist','seeded').map(i=>i.id),[child]);
}));
test('Favorites copies artwork and provenance; directory edits and external images are authoritative',async()=>session(async(s,root)=>{
 await s.queue(source('count=1;seed=7;shift=2',1));await s.idle();const id=s.state().images[0].id,folder=s.state().folder!,bytes=await s.image(id),recipe=s.recipe(id);
 await s.toggleFavorite(id);let favorite=s.state().favorites[0];assert.equal(favorite.hasRecipe,true);assert.equal(favorite.inBatch,true);assert.deepEqual(await s.image(favorite.id),bytes);assert.deepEqual(s.recipe(favorite.id),recipe);
 const favoritePath=join(root,'_favorites',favorite.filename);const {PNG}=await import('pngjs');const altered=PNG.sync.read(Buffer.from(bytes));altered.data[0]^=255;await writeFile(favoritePath,PNG.sync.write(altered));await s.refreshFavorites();assert.equal(s.state().favorites[0].hasRecipe,false);await writeFile(favoritePath,bytes);await s.refreshFavorites();assert.equal(s.state().favorites[0].hasRecipe,true);
 const external=join(root,'_favorites','external.png');await writeFile(external,bytes);await s.refreshFavorites();assert.equal(s.state().favorites.length,2);const unknown=s.state().favorites.find(i=>i.filename==='external.png')!;assert.equal(unknown.seed,null);assert.equal(unknown.hasRecipe,false);assert.throws(()=>s.recipe(unknown.id),/No saved recipe/);
 await s.toggleFavorite(unknown.id);await assert.rejects(access(external),/ENOENT/);assert.ok((await readdir(join(root,'_favorites','.removed'))).length);await access(join(folder,recipe.job.filename));
 await s.queue('title=other;count=1;steps=1;resolution=64*64\nOther shape.');await s.idle();assert.equal(s.state().favorites[0].inBatch,false);await assert.rejects(s.toggleSelection(favorite.id,'shortlisted'),/Open the source/);
 const opened=await s.openFavoriteSource(favorite.id);assert.equal(opened.imageId,id);assert.equal(opened.state.folder,folder);
 await s.toggleFavorite(id);assert.equal(s.state().favorites.length,0);await access(join(folder,recipe.job.filename));
 await s.toggleFavorite(id);favorite=s.state().favorites[0];await rm(folder,{recursive:true});assert.deepEqual(await s.image(favorite.id),bytes);assert.deepEqual(s.recipe(favorite.id),recipe);await assert.rejects(s.openFavoriteSource(favorite.id),/ENOENT/);
 await rm(join(root,'_favorites',favorite.filename));await s.refreshFavorites();assert.equal(s.state().favorites.length,0);
}));
test('three gallery sorts are numeric, stable, scoped, and separate from job numbering',async()=>session(async(s)=>{
 await s.queue(source('count=4;seed=7;shift=2,10,1.9,2',1));await s.idle();await s.queueVariant(s.state().images[0].id,{steps:6});await s.idle();const state=s.state();
 assert.deepEqual(sortedImages(state.images,'seeded').map(i=>i.number),[3,1,4,5,2]);assert.deepEqual(sortedImages(state.images,'seeded-step').map(i=>i.number),[3,1,4,2,5]);assert.equal(sortedImages(state.images,'newest')[0].number,5);
 await s.toggleSelection(state.images[0].id,'rejected');assert.ok(!galleryImages(s.state(),'images','seeded').some(i=>i.id===state.images[0].id));assert.equal(galleryImages(s.state(),'rejected','seeded').length,1);
}));
test('draft store preserves invalid work in progress, view state and last batch without restoring a queue',async()=>{
 const root=await mkdtemp(join(tmpdir(),'story-draft-')),file=join(root,'session.json');try{
  const store=new DraftStore(file);assert.deepEqual(await store.load(),emptyDraft());const draft={...emptyDraft(),source:'count=\nUnclosed {',lastBatch:'/saved/batch',scope:'shortlist' as const,sort:'seeded-step' as const};store.save(draft);await store.flush();assert.deepEqual(await new DraftStore(file).load(),draft);
  await writeFile(file,'corrupt original');const broken=new DraftStore(file);await assert.rejects(broken.load());broken.save(draft);await broken.flush();const backup=(await readdir(root)).find(f=>f.includes('.invalid-'))!;assert.equal(await readFile(join(root,backup),'utf8'),'corrupt original');
  assert.throws(()=>broken.save({...draft,sort:'wrong' as never}),/Invalid/);
 }finally{await rm(root,{recursive:true,force:true});}
});
test('collect replaces seed aliases without changing prompt/fields or other parameters',()=>{
 const input='title="A; B";seed=1;count=2;shift=1..2\nA [X].\n%%FIELDS%%\nX={red|blue}';const changed=replaceParameter(input,'seeds',['20','3']);assert.ok(changed.includes('seeds=20,3'));assert.ok(changed.endsWith('X={red|blue}'));assert.equal(compile(changed).parameters.title,'A; B');assert.throws(()=>replaceParameter(input,'shift',[]),/No completed/);
});

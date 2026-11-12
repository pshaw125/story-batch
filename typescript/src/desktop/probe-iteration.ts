import {BrowserWindow} from 'electron';
import {readFile,writeFile,access} from 'node:fs/promises';
import {join} from 'node:path';
import {DesktopSession} from '../node/desktop-session';
export async function iterationProbe(window:BrowserWindow,desktop:DesktopSession,root:string):Promise<object>{
 const checks=await window.webContents.executeJavaScript(`(async()=>{
  const $=s=>document.querySelector(s),wait=async(test)=>{for(let i=0;i<500;i++){if(await test())return;await new Promise(r=>setTimeout(r,10));}throw new Error('Iteration UI condition timed out');};
  const edit=(id,value)=>{const el=$(id);el.value=value;el.dispatchEvent(new Event('input',{bubbles:true}));};
  edit('#parameters','title=Iteration UI;count=3;steps=1;seed=30,10,20;shift=2,3,1;resolution=64*128');edit('#prompt','Hair hair [COLOR].');$('#new-batch').click();await wait(async()=>{const s=await window.storyBatch.state();return !s.busy&&s.title==='Iteration UI'&&s.images.length===3;});
  let state=await window.storyBatch.state();const ids=state.images.map(i=>i.id);
  const card=id=>$('[data-image-id="'+id+'"]');
  for(const id of ids)card(id).querySelector('[data-action="shortlisted"]').click();await wait(async()=>(await window.storyBatch.state()).images.every(i=>i.shortlisted));
  $('[data-tab="shortlist"]').click();await wait(()=>document.querySelectorAll('.image-card').length===3);card(ids[2]).querySelector('.frame button').click();await wait(()=>$('#viewer-image').src.startsWith('data:'));
  if($('#viewer-index').textContent!=='2 / 3')throw new Error('Shortlist sorting failed');
  $('#viewer-actions [data-action="shortlisted"]').click();await wait(()=>$('#viewer-name').textContent===state.images[0].filename);if($('#viewer-index').textContent!=='2 / 2')throw new Error('Unshortlist did not choose adjacent image');
  const src=$('#viewer-image').src;$('#viewer-sort').value='newest';$('#viewer-sort').dispatchEvent(new Event('change'));if($('#viewer-name').textContent!==state.images[0].filename||$('#viewer-image').src!==src)throw new Error('Sort changed viewed identity');
  $('#viewer-sort').value='seeded-step';$('#viewer-sort').dispatchEvent(new Event('change'));$('#absolute-shift').value='2.125';$('#set-shift').click();await wait(async()=>(await window.storyBatch.state()).images.length===4);
  state=await window.storyBatch.state();const child=state.images[3];if(!child.shortlisted)throw new Error('Shortlist variant lost membership');if(card(child.id).querySelector('.frame').style.aspectRatio!=='64 / 128')throw new Error('Placeholder aspect ratio lost');
  await wait(async()=>!(await window.storyBatch.state()).busy);$('#close-viewer').click();$('[data-tab="images"]').click();await wait(()=>document.querySelectorAll('.image-card').length===4);
  card(ids[0]).querySelector('[data-action="rejected"]').click();await wait(()=>!card(ids[0]));$('[data-tab="rejected"]').click();await wait(()=>document.querySelectorAll('.image-card').length===1);card(ids[0]).querySelector('[data-action="rejected"]').click();await wait(()=>document.querySelectorAll('.image-card').length===0);
  $('[data-tab="images"]').click();await wait(()=>!!card(ids[0]));card(ids[0]).querySelector('[data-action="favorite"]').click();await wait(async()=>(await window.storyBatch.state()).favorites.length===1);$('[data-tab="favorites"]').click();await wait(()=>document.querySelectorAll('.image-card').length===1);
  document.dispatchEvent(new KeyboardEvent('keydown',{key:'f',metaKey:true,bubbles:true}));edit('#find-input','hair');if($('#find-count').textContent!=='1 / 2')throw new Error('Find count failed');if(getComputedStyle($('.find-mirror')).position!=='absolute'||getComputedStyle($('.find-mirror')).color!=='rgba(0, 0, 0, 0)')throw new Error('Find mirror layout invalid');if(document.querySelectorAll('.find-mirror mark').length!==2)throw new Error('Find highlights missing');$('#find-next').click();if($('#find-count').textContent!=='2 / 2')throw new Error('Find next failed');if(document.querySelectorAll('.active-match').length!==1)throw new Error('Active highlight missing');$('#find-close').click();
  // Collection values come from the latest logical run (the one-image variant), not the gallery sort.
  $('#collect-seeds').click();await wait(()=>$('#parameters').value.includes('seeds=30'));$('#collect-shifts').click();await wait(()=>$('#parameters').value.includes('shift=2.125'));
  edit('#parameters','title=Iteration UI;count=4;steps=40;seed=1,2,3,4;shift=1,2,3,4;resolution=64*128');$('#queue').click();await wait(async()=>{const s=await window.storyBatch.state();return s.activeId&&s.images.some(i=>i.id===s.activeId&&i.status==='running')&&s.waiting.length===3;});$('[data-tab="queue"]').click();
  state=await window.storyBatch.state();const last=state.waiting[2];$('[data-id="'+last+'"] button[title="Run next"]').click();await wait(async()=>(await window.storyBatch.state()).waiting[0]===last);
  const remove=(await window.storyBatch.state()).waiting[2];$('[data-id="'+remove+'"] button[title="Remove waiting image"]').click();await wait(async()=>!(await window.storyBatch.state()).waiting.includes(remove));
  $('#stop-after').click();await wait(async()=>(await window.storyBatch.state()).waiting.length===0);await wait(async()=>!(await window.storyBatch.state()).busy);
  // An invalid unfinished draft is retained without modifying already-frozen jobs.
  edit('#prompt','An unfinished {draft');$('[data-tab="shortlist"]').click();await new Promise(r=>setTimeout(r,300));
  const draft=await window.storyBatch.draft();if(!draft.source.includes('unfinished {draft')||draft.scope!=='shortlist')throw new Error('Draft did not save');
  return {queueReorder:true,queueRemoval:true,stopAfter:true,shortlist:true,shortlistVariant:true,adjacentUnshortlist:true,rejectRestore:true,diskFavorites:true,viewerSortIdentity:true,searchHighlights:true,collectors:true,draft:true};
 })()`);
 const draft=JSON.parse(await readFile(join(root,'session.json'),'utf8'));if(!draft.draft.source.includes('unfinished {draft'))throw new Error('Draft not durable');
 const state=desktop.state(),favorite=state.favorites[0];await access(join(state.favoriteFolder,favorite.filename));
 const external=join(state.favoriteFolder,'external.png');await writeFile(external,await desktop.image(favorite.id));
 await window.webContents.executeJavaScript("document.querySelector('[data-tab=\"favorites\"]').click()");
 for(let i=0;i<100&&desktop.state().favorites.length!==2;i++)await new Promise(r=>setTimeout(r,10));if(desktop.state().favorites.length!==2)throw new Error('External favorite not rescanned');
 const loaded=new Promise<void>(resolve=>window.webContents.once('did-finish-load',()=>resolve()));window.webContents.reload();await loaded;
 await window.webContents.executeJavaScript(`(async()=>{for(let i=0;i<200;i++){if(document.querySelector('#prompt').value.includes('unfinished {draft'))break;await new Promise(r=>setTimeout(r,10));}if(!document.querySelector('#prompt').value.includes('unfinished {draft'))throw new Error('Draft restore failed');const s=await window.storyBatch.state();if(s.busy)throw new Error('Reload resumed work');})()`);
 return {...checks,externalFavorites:true,reloadWithoutResume:true};
}

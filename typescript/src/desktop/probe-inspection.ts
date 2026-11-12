import {app,BrowserWindow} from 'electron';
import {writeFile} from 'node:fs/promises';
export async function inspectionProbe(window:BrowserWindow):Promise<object>{
 const checks=await window.webContents.executeJavaScript(`(async()=>{
 const $=s=>document.querySelector(s),pane=$('.viewer-image-pane'),wait=async(test)=>{for(let i=0;i<400;i++){if(await test())return;await new Promise(r=>setTimeout(r,10));}throw new Error('Inspection UI condition timed out');};
 const edit=(s,value)=>{const el=$(s);el.value=value;el.dispatchEvent(new Event('input',{bubbles:true}));};
 const key=(value,code='',repeat=false)=>{const event=new KeyboardEvent('keydown',{key:value,code,repeat,bubbles:true,cancelable:true});document.dispatchEvent(event);return event;};
 const zoom=()=>Number(pane.dataset.zoom),center=()=>[Number(pane.dataset.centerX),Number(pane.dataset.centerY)];
 edit('#parameters','title=Inspection UI;count=5;steps=1;seed=10,10,10,20,20;shift=1,2,3,1,2;resolution=64*64');edit('#prompt','A synthetic inspection image.');$('#new-batch').click();await wait(async()=>{const s=await window.storyBatch.state();return s.title==='Inspection UI'&&!s.busy;});
 const state=await window.storyBatch.state(),ids=state.images.map(i=>i.id),card=id=>$('[data-image-id="'+id+'"]');card(ids[0]).querySelector('.frame button').click();await wait(()=>!$('#viewer-image').hidden);pane.focus();
 key('Unidentified','NumpadAdd');if(zoom()!==1.25)throw new Error('Numpad Add failed');key('Unidentified','NumpadSubtract');if(zoom()!==1)throw new Error('Numpad Subtract failed');key('+','Equal');if(zoom()!==1.25)throw new Error('Regular plus failed');key('-','Minus');if(zoom()!==1)throw new Error('Regular minus failed');
 const text=$('#absolute-shift');text.focus();const typed=new KeyboardEvent('keydown',{key:'+',code:'NumpadAdd',bubbles:true,cancelable:true});text.dispatchEvent(typed);if(typed.defaultPrevented||zoom()!==1)throw new Error('Viewer stole text input');text.blur();pane.focus();
 const rectangle=()=>{const image=$('#viewer-image');return {left:parseFloat(image.style.left),top:parseFloat(image.style.top),width:parseFloat(image.style.width),height:parseFloat(image.style.height)};};
 const wheel=(x,y,ctrl=false,alt=false,shift=false)=>{const bounds=pane.getBoundingClientRect();const event=new WheelEvent('wheel',{deltaX:x,deltaY:y,ctrlKey:ctrl,altKey:alt,shiftKey:shift,clientX:bounds.left+bounds.width/2,clientY:bounds.top+bounds.height/2+20,bubbles:true,cancelable:true});pane.dispatchEvent(event);return {x:event.clientX-bounds.left,y:event.clientY-bounds.top};};
 const before=rectangle(),point=wheel(0,-120,true),after=rectangle(),px=(point.x-before.left)/before.width,py=(point.y-before.top)/before.height;if(Math.abs((point.x-after.left)/after.width-px)>1e-5||Math.abs((point.y-after.top)/after.height-py)>1e-5)throw new Error('Pointer anchored zoom drifted: '+JSON.stringify({before,after,px,py,point}));const ctrlZoom=zoom();wheel(0,-120,false,true);if(zoom()<=ctrlZoom)throw new Error('Alt wheel zoom failed');wheel(0,-240,true);const initial=center();wheel(0,30,false,false,true);if(center()[0]===initial[0]||center()[1]!==initial[1])throw new Error('Horizontal wheel pan failed');const horizontal=center();wheel(0,30);if(center()[1]===horizontal[1]||center()[0]!==horizontal[0])throw new Error('Vertical wheel pan failed');
 const retainedZoom=zoom(),retainedCenter=center();key('ArrowRight');await wait(()=>$('#viewer-name').textContent===state.images[1].filename&&!$('#viewer-image').hidden);if(zoom()!==retainedZoom||JSON.stringify(center())!==JSON.stringify(retainedCenter))throw new Error('Same-seed viewport lost');key('ArrowRight');await wait(()=>$('#viewer-name').textContent===state.images[2].filename);const index=$('#viewer-index').textContent;
 key('ArrowRight');if($('#viewer-index').textContent!==index||$('#seed-notice').hidden)throw new Error('Seed boundary did not guard');key('ArrowRight','ArrowRight',true);if($('#viewer-index').textContent!==index)throw new Error('Key repeat crossed seed');key('ArrowRight');await wait(()=>$('#viewer-name').textContent===state.images[3].filename);if(zoom()!==1||center()[0]!==.5||center()[1]!==.5)throw new Error('New seed did not reset fit');
 key('+');key('ArrowLeft');if($('#seed-notice').textContent!=='Previous seed; press again to proceed')throw new Error('Previous seed notice missing');key('0');if(!$('#seed-notice').hidden)throw new Error('Fit did not clear seed confirmation');key('ArrowLeft');await wait(()=>$('#viewer-name').textContent===state.images[2].filename);if(zoom()!==1)throw new Error('Returning remembered an old viewport');
 for(let i=0;i<7;i++)key('+');const name=$('#viewer-name').textContent,saved=zoom();$('#viewer-sort').value='newest';$('#viewer-sort').dispatchEvent(new Event('change'));if($('#viewer-name').textContent!==name||zoom()!==saved)throw new Error('Sorting changed inspection state');$('#viewer-sort').value='seeded';$('#viewer-sort').dispatchEvent(new Event('change'));$('#fit-image').click();pane.focus();
 for(let i=0;i<10;i++)key('-');if(zoom()!==1)throw new Error('Zoom went below fit');key('ArrowLeft');key('ArrowLeft');const edge=$('#viewer-index').textContent;key('ArrowLeft');if($('#viewer-index').textContent!==edge)throw new Error('Navigation wrapped');
 for(let i=0;i<6;i++)key('+');pane.focus();return {numpadZoom:true,regularZoom:true,textFocus:true,ctrlAltWheel:true,cursorAnchor:true,wheelPan:true,sameSeedRetention:true,seedGuard:true,repeatGuard:true,fitFloor:true,sortRetention:true,noSeedHistory:true};
 })()`);
 // Mouse injection targets this WebContents, never the desktop/global pointer.
 const position=await window.webContents.executeJavaScript(`(()=>{const r=document.querySelector('.viewer-image-pane').getBoundingClientRect();return {x:Math.round(r.left+r.width/2),y:Math.round(r.top+r.height/2),center:document.querySelector('.viewer-image-pane').dataset.centerX};})()`);
 window.webContents.focus();
 for(const modifier of ['control','alt'] as const){
  const before=await window.webContents.executeJavaScript("Number(document.querySelector('.viewer-image-pane').dataset.zoom)");
  window.webContents.sendInputEvent({type:'mouseWheel',x:position.x,y:position.y,deltaX:0,deltaY:80,modifiers:[modifier]});
  await new Promise(r=>setTimeout(r,100));
  const after=await window.webContents.executeJavaScript("Number(document.querySelector('.viewer-image-pane').dataset.zoom)");
  if(before===after||window.webContents.getZoomFactor()!==1)throw new Error('Native '+modifier+' wheel did not zoom only the image');
 }
 const beforeDrag=await window.webContents.executeJavaScript("document.querySelector('.viewer-image-pane').dataset.centerX");
 window.webContents.sendInputEvent({type:'mouseMove',x:position.x,y:position.y});
 window.webContents.sendInputEvent({type:'mouseDown',x:position.x,y:position.y,button:'left',clickCount:1});
 window.webContents.sendInputEvent({type:'mouseMove',x:position.x+60,y:position.y+35});
 window.webContents.sendInputEvent({type:'mouseUp',x:position.x+60,y:position.y+35,button:'left',clickCount:1});
 await new Promise(r=>setTimeout(r,100));
 const dragged=await window.webContents.executeJavaScript("document.querySelector('.viewer-image-pane').dataset.centerX");
 if(dragged===beforeDrag)throw new Error('Mouse drag did not pan');
 window.webContents.sendInputEvent({type:'mouseDown',x:position.x,y:position.y,button:'middle',clickCount:1});window.webContents.sendInputEvent({type:'mouseMove',x:position.x-35,y:position.y-20});window.webContents.sendInputEvent({type:'mouseUp',x:position.x-35,y:position.y-20,button:'middle',clickCount:1});await new Promise(r=>setTimeout(r,100));
 const middle=await window.webContents.executeJavaScript("({center:document.querySelector('.viewer-image-pane').dataset.centerX,dragging:document.querySelector('.viewer-image-pane').classList.contains('dragging')})");if(middle.center===dragged||middle.dragging)throw new Error('Middle drag or pointer release failed');
 if(process.env.STORYBATCH_PROBE_NATIVE_FULLSCREEN!=='1'){await window.webContents.executeJavaScript("document.querySelector('#close-viewer').click()");return {...checks,mouseDrag:true,middleDrag:true,nativeCtrlAltWheel:true,nativeFullscreen:'not-requested'};}
 // Native fullscreen requires a visible window on macOS. This isolated test window
 // has temporary state and synthetic images; no user application is restarted.
 window.show();app.focus({steal:true});window.focus();await new Promise(r=>setTimeout(r,300));
 if(process.env.STORYBATCH_INSPECTION_SCREENSHOT)await writeFile(process.env.STORYBATCH_INSPECTION_SCREENSHOT+'-normal.png',(await window.webContents.capturePage()).toPNG());
 const full=await window.webContents.executeJavaScript(`(async()=>{const wait=async(test)=>{for(let i=0;i<600;i++){if(await test())return;await new Promise(r=>setTimeout(r,20));}throw new Error('Native fullscreen condition timed out');};const $=s=>document.querySelector(s),key=value=>document.dispatchEvent(new KeyboardEvent('keydown',{key:value,bubbles:true,cancelable:true}));
 const pane=$('.viewer-image-pane'),before=Number(pane.dataset.zoom);$('#fullscreen').click();await wait(async()=>await window.storyBatch.fullscreenState());if(!$('#viewer').classList.contains('image-only')||getComputedStyle($('.viewer-toolbar')).display!=='none'||getComputedStyle($('.viewer-footer')).display!=='none')throw new Error('Fullscreen chrome visible');
 key('ArrowRight');await new Promise(r=>setTimeout(r,80));if(Number(pane.dataset.zoom)!==before)throw new Error('Fullscreen same-seed navigation lost zoom');key('ArrowRight');key('ArrowRight');if($('#fullscreen-seed-notice').hidden)throw new Error('Fullscreen seed warning missing');
 const notice=$('#fullscreen-seed-notice');if(!notice.textContent||getComputedStyle(notice).visibility==='hidden'||notice.getBoundingClientRect().height<=0)throw new Error('Fullscreen warning not rendered');await new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)));return {nativeFullscreen:true,imageOnly:true,fullscreenArrows:true,fullscreenSeedGuard:true};})()`);
 if(process.env.STORYBATCH_INSPECTION_SCREENSHOT)await writeFile(process.env.STORYBATCH_INSPECTION_SCREENSHOT+'-fullscreen.png',(await window.webContents.capturePage()).toPNG());
 const returned=await window.webContents.executeJavaScript(`(async()=>{const wait=async(test)=>{for(let i=0;i<600;i++){if(await test())return;await new Promise(r=>setTimeout(r,20));}throw new Error('Fullscreen return timed out');};const $=s=>document.querySelector(s),key=value=>document.dispatchEvent(new KeyboardEvent('keydown',{key:value,bubbles:true,cancelable:true}));key('Escape');await wait(async()=>!(await window.storyBatch.fullscreenState()));await wait(()=>!$('#viewer').classList.contains('image-only')&&!$('#fullscreen').disabled);if(!$('#viewer').open)throw new Error('Escape closed viewer instead of fullscreen');
 key('f');await wait(async()=>await window.storyBatch.fullscreenState());await wait(()=>!$('#fullscreen').disabled);key('f');await wait(async()=>!(await window.storyBatch.fullscreenState()));key('0');$('#close-viewer').click();return {nativeFullscreen:true,imageOnly:true,fullscreenArrows:true,fullscreenSeedGuard:true,escapeReturnsViewer:true,fToggle:true};})()`);
 window.hide();
 return {...checks,mouseDrag:true,middleDrag:true,nativeCtrlAltWheel:true,...full,...returned};
}

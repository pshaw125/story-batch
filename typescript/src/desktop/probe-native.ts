import {BrowserWindow} from 'electron';
import {DesktopSession} from '../node/desktop-session';
/** Explicit native smoke mode only. Outputs are kept in the supplied local root. */
export async function runNativeDesktopProbe(window:BrowserWindow,desktop:DesktopSession):Promise<object>{
  const checks=await window.webContents.executeJavaScript(`(async()=>{
    const wait=async(test)=>{for(let i=0;i<1200;i++){if(await test())return;await new Promise(r=>setTimeout(r,100));}throw new Error('Native UI condition timed out');};
    const edit=(id,value)=>{const el=document.querySelector(id);el.value=value;el.dispatchEvent(new Event('input',{bubbles:true}));};
    await wait(()=>(document.querySelector('#renderer-label').textContent.includes('Draw Things')));
    edit('#parameters','title=phase 3 native UI smoke;count=1;steps=3;seed=1234;shift=1.75;resolution=512*512');edit('#fields','COLOR={red}');edit('#prompt','A [COLOR] ceramic teacup on a wooden table, soft window light, softly shaded illustration.');
    document.querySelector('#preview').click();await wait(()=>document.querySelectorAll('.preview-card').length===1);
    document.querySelector('#queue').click();await wait(async()=>!!(await window.storyBatch.state()).activeId);
    edit('#prompt','An unqueued later edit.');
    await wait(async()=>{const s=await window.storyBatch.state();return !s.busy&&s.images.length===1;});
    const state=await window.storyBatch.state();if(state.images[0].status!=='completed')throw new Error('Native image failed: '+JSON.stringify(state));
    const recipe=await window.storyBatch.recipe(state.images[0].id);if(!recipe.job.prompt.startsWith('A red ceramic'))throw new Error('Native queued prompt changed with editor');
    document.querySelector('.frame button').click();await wait(()=>document.querySelector('#viewer-image').src.startsWith('data:'));
    if(getComputedStyle(document.querySelector('#viewer-image')).objectFit!=='contain')throw new Error('Native viewer fit failed');
    return {nativeImage:true,frozenEditor:true,gallery:true,viewer:true,environment:recipe.environment.framework};
  })()`);
  return {...checks,folder:desktop.state().folder};
}

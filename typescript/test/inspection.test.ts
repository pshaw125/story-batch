import {test} from 'node:test';
import assert from 'node:assert/strict';
import {EventEmitter} from 'node:events';
import {ImageViewport,SeedBoundaryGuard,retainViewport} from '../src/core/inspection';
import {viewerKey,wheelPixels,wheelMagnification} from '../src/desktop/ui/viewer-input';
import {NativeFullscreen} from '../src/desktop/fullscreen';
const near=(a:number,b:number)=>assert.ok(Math.abs(a-b)<1e-8,`${a} differs from ${b}`);
test('fit preserves aspect ratio, centers letterboxing, and is the lower zoom bound',()=>{
 const v=new ImageViewport();v.resize(1000,600);v.image(400,400);assert.deepEqual(v.rect,{left:200,top:0,width:600,height:600});v.pan(300,-300);assert.deepEqual(v.rect,{left:200,top:0,width:600,height:600});v.magnify(.1,100,200);assert.equal(v.zoom,1);assert.equal(v.zoomed,false);
 v.image(1600,400);assert.deepEqual(v.rect,{left:0,top:175,width:1000,height:250});
});
test('pointer-anchored zoom retains the pixel under the pointer and bounds panning',()=>{
 const v=new ImageViewport();v.resize(1000,600);v.image(1000,600);const x=600,y=400,before=v.rect,px=(x-before.left)/before.width,py=(y-before.top)/before.height;v.magnify(2,x,y);const after=v.rect;near((x-after.left)/after.width,px);near((y-after.top)/after.height,py);
 v.pan(1e9,-1e9);assert.ok(v.rect.left<=0&&v.rect.left+v.rect.width>=1000);assert.ok(v.rect.top<=0&&v.rect.top+v.rect.height>=600);
 v.magnify(1e9);assert.equal(v.zoom,16);v.magnify(1e-20);assert.equal(v.zoom,1);near(v.centerX,.5);near(v.centerY,.5);
});
test('resize and same-seed dimensions preserve normalized focus without per-seed history',()=>{
 const v=new ImageViewport();v.resize(800,600);v.image(800,600);v.magnify(4);v.pan(100,-50);const cx=v.centerX,cy=v.centerY;v.resize(1600,900);near(v.centerX,cx);near(v.centerY,cy);assert.equal(v.zoom,4);v.image(1600,1200);near(v.centerX,cx);near(v.centerY,cy);
 assert.equal(retainViewport({id:'a',seed:7},{id:'b',seed:7}),true);assert.equal(retainViewport({id:'a',seed:7},{id:'b',seed:8}),false);assert.equal(retainViewport({id:'a',seed:null},{id:'b',seed:null}),false);assert.equal(retainViewport({id:'a',seed:null},{id:'a',seed:null}),true);assert.equal(retainViewport(null,{id:'a',seed:7}),false);
 v.fit();v.image(800,600);assert.equal(v.zoom,1);assert.equal(v.centerX,.5);
});
test('nonfinite gesture data cannot corrupt the viewport',()=>{
 const v=new ImageViewport();const before=v.rect;v.resize(NaN,1);v.image(Infinity,5);v.magnify(NaN);v.magnify(0);v.magnify(2,NaN,0);v.pan(NaN,Infinity);assert.deepEqual(v.rect,before);
});
test('seed crossing requires a second fresh press; key repeat never confirms, target/direction changes invalidate it',()=>{
 const guard=new SeedBoundaryGuard();assert.equal(guard.allow('a','b',7,8,true,1),false);assert.equal(guard.notice,'Next seed; press again to proceed');for(let i=0;i<5;i++)assert.equal(guard.allow('a','b',7,8,true,1,true),false);assert.equal(guard.allow('a','b',7,8,true,1),true);assert.equal(guard.notice,null);
 assert.equal(guard.allow('a','b',7,8,true,1),false);assert.equal(guard.allow('a','c',7,9,true,1),false);assert.equal(guard.allow('a','d',7,6,true,-1),false);assert.equal(guard.notice,'Previous seed; press again to proceed');assert.equal(guard.allow('a','d',7,6,true,-1),true);
});
test('fit, same seed and unknown seed navigation need no extra press; clearing removes stale confirmation',()=>{
 const g=new SeedBoundaryGuard();assert.equal(g.allow('a','b',7,8,false,1),true);assert.equal(g.allow('a','b',7,7,true,1),true);assert.equal(g.allow('a','b',null,7,true,1),true);assert.equal(g.allow('a','b',7,null,true,1),true);g.allow('a','b',7,8,true,1);g.clear();assert.equal(g.allow('a','b',7,8,true,1),false);
});
test('regular and numpad plus/minus are accepted, including legacy key values, without taking modified text shortcuts',()=>{
 const event=(key:string,code='')=>({key,code,ctrlKey:false,altKey:false,metaKey:false});
 for(const e of [event('+','Equal'),event('=','Equal'),event('+','NumpadAdd'),event('Add'),event('Unidentified','NumpadAdd')])assert.equal(viewerKey(e),'zoom-in');
 for(const e of [event('-','Minus'),event('-','NumpadSubtract'),event('Subtract'),event('Unidentified','NumpadSubtract')])assert.equal(viewerKey(e),'zoom-out');
 for(const modifier of ['ctrlKey','altKey','metaKey'])assert.equal(viewerKey({...event('+'),[modifier]:true}),null);
 assert.equal(viewerKey(event('0','Numpad0')),'fit');assert.equal(viewerKey(event('F','KeyF')),'fullscreen');assert.equal(viewerKey(event('ArrowRight')),'next');assert.equal(viewerKey(event('ArrowLeft')),'previous');assert.equal(viewerKey(event('Escape')),'escape');
});
test('wheel normalization handles pixel/line/page devices and clamps extreme zoom deltas',()=>{
 assert.deepEqual(wheelPixels({deltaX:1,deltaY:2,deltaMode:0},600),{x:1,y:2});assert.deepEqual(wheelPixels({deltaX:1,deltaY:2,deltaMode:1},600),{x:16,y:32});assert.deepEqual(wheelPixels({deltaX:0,deltaY:1,deltaMode:2},600),{x:0,y:600});assert.ok(wheelMagnification(-100)>1);assert.ok(wheelMagnification(100)<1);near(wheelMagnification(-1e9),wheelMagnification(-240));
});
class WindowPort extends EventEmitter {
 fullscreen=false;destroyed=false;requests:boolean[]=[];
 isDestroyed(){return this.destroyed;}isFullScreen(){return this.fullscreen;}
 setFullScreen(flag:boolean){this.requests.push(flag);setTimeout(()=>{this.fullscreen=flag;this.emit(flag?'enter-full-screen':'leave-full-screen');},5);}
}
test('native fullscreen awaits OS events and serializes enter/exit without racing state',async()=>{
 const w=new WindowPort(),notifications:boolean[]=[],host=new NativeFullscreen(w,flag=>notifications.push(flag),100);const entered=host.set(true),exited=host.set(false);assert.equal(host.state(),false);assert.equal(await entered,true);assert.equal(await exited,false);assert.deepEqual(w.requests,[true,false]);assert.deepEqual(notifications,[true,false]);assert.equal(await host.set(false),false);assert.equal(w.requests.length,2);
 const closing=new WindowPort(),pendingHost=new NativeFullscreen(closing,()=>{},100),pending=pendingHost.set(true);await Promise.resolve();closing.destroyed=true;closing.emit('closed');await assert.rejects(pending,/closed during/);assert.equal(closing.listenerCount('closed'),0);
});
test('fullscreen timeouts and destroyed windows fail explicitly and release queued requests',async()=>{
 const w=new WindowPort();w.setFullScreen=()=>{};const host=new NativeFullscreen(w,()=>{},10);await assert.rejects(host.set(true),/not confirmed/);assert.equal(await host.set(false),false);w.destroyed=true;await assert.rejects(host.set(true),/closed/);
});

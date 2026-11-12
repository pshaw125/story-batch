export type ViewerKey='zoom-in'|'zoom-out'|'fit'|'fullscreen'|'escape'|'previous'|'next'|'space'|null;
export function viewerKey(event:Pick<KeyboardEvent,'key'|'code'|'ctrlKey'|'altKey'|'metaKey'>):ViewerKey {
 if(event.ctrlKey||event.altKey||event.metaKey)return null;
 if(event.code==='NumpadAdd'||event.key==='+'||event.key==='='||event.key==='Add')return 'zoom-in';
 if(event.code==='NumpadSubtract'||event.key==='-'||event.key==='Subtract')return 'zoom-out';
 if(event.key==='0')return 'fit';if(event.key.toLowerCase()==='f')return 'fullscreen';if(event.key==='Escape')return 'escape';if(event.key==='ArrowLeft')return 'previous';if(event.key==='ArrowRight')return 'next';if(event.key===' '||event.code==='Space')return 'space';return null;
}
export function wheelPixels(event:Pick<WheelEvent,'deltaX'|'deltaY'|'deltaMode'>,height:number):{x:number;y:number}{const scale=event.deltaMode===1?16:event.deltaMode===2?height:1;return {x:event.deltaX*scale,y:event.deltaY*scale};}
export function wheelMagnification(delta:number):number{return Math.exp(-Math.max(-240,Math.min(240,delta))*.0025);}

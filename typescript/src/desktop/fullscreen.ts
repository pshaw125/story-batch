export interface FullscreenWindow {
 isDestroyed():boolean;isFullScreen():boolean;setFullScreen(flag:boolean):void;
 on(event:string,callback:()=>void):unknown;removeListener(event:string,callback:()=>void):unknown;
}
/** Await OS confirmation; macOS fullscreen transitions are asynchronous. */
export class NativeFullscreen {
 private confirmed:boolean;private tail:Promise<unknown>=Promise.resolve();
 constructor(private window:FullscreenWindow,notify:(flag:boolean)=>void,private timeoutMs=10000){this.confirmed=window.isFullScreen();window.on('enter-full-screen',()=>{this.confirmed=true;notify(true);});window.on('leave-full-screen',()=>{this.confirmed=false;notify(false);});}
 state():boolean{return this.confirmed;}
 set(flag:boolean):Promise<boolean>{const result=this.tail.then(()=>this.transition(flag));this.tail=result.catch(()=>{});return result;}
 private async transition(flag:boolean):Promise<boolean>{if(this.window.isDestroyed())throw new Error('Viewer window is closed.');if(this.confirmed===flag)return flag;
  return new Promise<boolean>((resolve,reject)=>{
   const cleanup=()=>{clearTimeout(timer);this.window.removeListener('enter-full-screen',check);this.window.removeListener('leave-full-screen',check);this.window.removeListener('closed',closed);};
   const check=()=>{if(this.confirmed===flag){cleanup();resolve(flag);}},closed=()=>{cleanup();reject(new Error('Viewer window closed during fullscreen transition.'));};
   const timer=setTimeout(()=>{cleanup();reject(new Error('Fullscreen transition was not confirmed. Bring the app window to the front and try again.'));},this.timeoutMs);
   this.window.on('enter-full-screen',check);this.window.on('leave-full-screen',check);this.window.on('closed',closed);
   try{this.window.setFullScreen(flag);}catch(error){cleanup();reject(error);}
  });
 }
}

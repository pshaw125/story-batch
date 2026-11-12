import { PNG } from 'pngjs';
import { ImageJob } from '../core/planning';
import { validateJob } from '../core/reports';
import { Capabilities } from '../core/renderer';
import {validateInput} from './canvas';
import { validateOutputSize } from './png';
import { Adapter, Entry } from './renderers/base';
/** Explicit test renderer. Produces dimension-correct color swatches, never model output. */
export class SyntheticRenderer extends Adapter {
  readonly capabilities: Capabilities = { backend:'fake',textToImage:true,imageToImage:true,loras:true,cancellation:true,progress:true,nativeControls:['seed','shift','steps','dimensions'] };
  private timers = new Map<string, NodeJS.Timeout>();
  constructor(private tickMs = 100) { super(); }
  async validate(job: ImageJob): Promise<void> { validateJob(job); validateOutputSize(job.width,job.height); await validateInput(job); }
  protected async launch(e: Entry): Promise<void> {
    this.transition(e,'running'); let step=0;
    const timer=setInterval(()=>{
      try {
        e.emit({jobId:e.job.id,type:'progress',completed:++step,total:e.job.steps});
        if(step<e.job.steps)return;
        clearInterval(timer);this.timers.delete(e.handle);
        const image=new PNG({width:e.job.width,height:e.job.height});
        for(let i=0;i<image.data.length;i+=4){image.data[i]=(e.job.seed%160)+40;image.data[i+1]=Math.min(240,40+Number(e.job.shift)*30);image.data[i+2]=120;image.data[i+3]=255;}
        e.result={jobId:e.job.id,bytes:PNG.sync.write(image),mediaType:'image/png',cached:false,effectiveJob:e.job,elapsedMs:performance.now()-e.started};
        this.transition(e,'completed');
      }catch(error){clearInterval(timer);this.timers.delete(e.handle);this.failed(e,error);}
    },this.tickMs);
    this.timers.set(e.handle,timer);
  }
  protected async refresh(_e:Entry):Promise<void>{}
  protected async interrupt(e:Entry):Promise<void>{const timer=this.timers.get(e.handle);if(timer)clearInterval(timer);this.timers.delete(e.handle);this.transition(e,'cancelled');}
}

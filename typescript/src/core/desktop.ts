import type { ImageJob, RunContext } from './planning';
import type { ImageRecord } from './reports';
export interface ImageSummary {
  id:string; number:number; filename:string; seed:number; shift:string; steps:number; width:number; height:number;
  status:ImageRecord['status']|'interrupted'|'unresolved'; elapsedMs:number|null; error:string|null; cached?:boolean;
}
export interface DesktopState {
  renderer:string; configured:boolean; busy:boolean; stopping:boolean; uncertain:boolean;
  batchId:string|null; title:string|null; folder:string|null; outputRoot:string;
  images:ImageSummary[]; activeId:string|null; progress:{completed:number;total:number}|null;
  activity:string[]; error:string|null;
}
export interface PreviewResult { images:ImageJob[]; startsNewBatch:boolean; title:string }
export interface RecipeSnapshot { job:ImageJob; environment:RunContext }
export type VariantChange={steps:number}|{shift:string}|{delta:string};

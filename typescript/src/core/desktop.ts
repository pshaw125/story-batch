import type { CanvasSelection, ImageJob, RunContext } from './planning';
import type {GalleryScope,ImageSort} from './gallery';
import type {LoRA,NativeRecipe} from './recipes';
import type { ImageRecord } from './reports';
export interface ImageSummary {
  id:string; number:number; filename:string; seed:number|null; shift:string|null; steps:number|null; width:number|null; height:number|null;
  recency:number;shortlisted:boolean;rejected:boolean;favorite:boolean;hasRecipe:boolean;inBatch:boolean;hasSource:boolean;
  historical?:boolean;
  status:ImageRecord['status']|'interrupted'|'unresolved'; elapsedMs:number|null; error:string|null; cached?:boolean;
}
export interface DesktopState {
  tools?:{backend:NativeRecipe['backend'];loras:LoRA[];canvas:CanvasSelection|null};
  renderer:string; configured:boolean; busy:boolean; stopping:boolean; uncertain:boolean;
  batchId:string|null; title:string|null; folder:string|null; outputRoot:string;
  images:ImageSummary[];favorites:ImageSummary[];favoriteFolder:string;waiting:string[];lastRunCount:number; activeId:string|null; progress:{completed:number;total:number}|null;
  activity:string[]; error:string|null;
}
export interface PreviewResult { images:ImageJob[]; startsNewBatch:boolean; title:string }
export interface RecipeSnapshot { job:ImageJob; environment:RunContext }
export type VariantChange={steps:number}|{shift:string}|{delta:string};

export interface DraftSnapshot {tools?:DesktopState['tools'];source:string;lastBatch:string|null;scope:GalleryScope;sort:ImageSort}

export interface SwiftImportPreview {folder:string;originalFolder:string;reportFilename:string;title:string;images:number;warnings:string[]}

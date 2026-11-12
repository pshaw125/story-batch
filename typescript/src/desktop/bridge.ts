import type { DesktopState, PreviewResult, RecipeSnapshot, VariantChange, DraftSnapshot } from '../core/desktop';
export interface DesktopBridge {
  state():Promise<DesktopState>;
  preview(source:string):Promise<PreviewResult>;
  queue(source:string,newBatch:boolean):Promise<DesktopState>;
  stop():Promise<DesktopState>;
  skip(id:string):Promise<DesktopState>;
  stopAfter():Promise<DesktopState>;
  reorder(id:string,direction:'up'|'down'|'next'):Promise<DesktopState>;
  cancelQueued(id:string):Promise<DesktopState>;
  collect(source:string,kind:'seeds'|'shift'):Promise<string>;
  selection(id:string,kind:'shortlisted'|'rejected'):Promise<DesktopState>;
  favorite(id:string):Promise<DesktopState>;
  refreshFavorites():Promise<DesktopState>;
  openFavoriteSource(id:string):Promise<{source:string;state:DesktopState;imageId:string}>;
  draft():Promise<DraftSnapshot>;
  saveDraft(snapshot:DraftSnapshot):Promise<void>;
  variant(id:string,change:VariantChange,shortlist?:boolean):Promise<DesktopState>;
  recipe(id:string):Promise<RecipeSnapshot>;
  image(id:string,thumbnail:boolean):Promise<string>;
  copyRecipe(id:string):Promise<void>;
  openPrompt():Promise<{source:string;path:string}|null>;
  savePrompt(source:string,saveAs:boolean):Promise<string|null>;
  openBatch():Promise<{source:string;state:DesktopState}|null>;
  configureRenderer():Promise<DesktopState|null>;
  useSynthetic():Promise<DesktopState>;
  chooseOutput():Promise<DesktopState|null>;
  onState(callback:(state:DesktopState)=>void):()=>void;
  onCommand(callback:(command:string)=>void):()=>void;
}
declare global {interface Window {storyBatch:DesktopBridge;storyBatchDraft?:()=>DraftSnapshot}}

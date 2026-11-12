import type { DesktopState, PreviewResult, RecipeSnapshot, VariantChange } from '../core/desktop';
export interface DesktopBridge {
  state():Promise<DesktopState>;
  preview(source:string):Promise<PreviewResult>;
  queue(source:string,newBatch:boolean):Promise<DesktopState>;
  stop():Promise<DesktopState>;
  variant(id:string,change:VariantChange):Promise<DesktopState>;
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
declare global {interface Window {storyBatch:DesktopBridge}}

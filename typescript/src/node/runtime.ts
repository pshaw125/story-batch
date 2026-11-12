import { readFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { NativeRecipe, drawThingsPreset, validateRecipe } from '../core/recipes';
import { Renderer } from '../core/renderer';
import { RunContext } from '../core/planning';
import { runContext } from './environment';
import { comfyPreset } from './comfy-workflow';
import { ComfyAdapter } from './renderers/comfyui';
import { DrawThingsAdapter } from './renderers/draw-things';
import { SyntheticRenderer } from './synthetic-renderer';
export interface Runtime { renderer:Renderer; recipe:NativeRecipe; label:string; context:()=>Promise<RunContext>; close:()=>void }
export function syntheticRuntime(tickMs=100):Runtime {
  return {renderer:new SyntheticRenderer(tickMs),recipe:drawThingsPreset(),label:'Synthetic test renderer',context:async()=>runContext('synthetic-renderer','1'),close:()=>{}};
}
export async function configuredRuntime(file:string,workRoot:string):Promise<Runtime>{
  const config=JSON.parse(await readFile(file,'utf8'));
  if(config.schemaVersion!==1)throw new Error('Unsupported renderer configuration schema.');
  const adapter=config.backend==='draw-things'?new DrawThingsAdapter({executablePath:resolve(dirname(file),config.executablePath),modelsDirectory:config.modelsDirectory?resolve(dirname(file),config.modelsDirectory):undefined,workRoot})
    :config.backend==='comfyui'?new ComfyAdapter({baseUrl:config.baseUrl,dedicated:config.dedicated,workRoot}):null;
  if(!adapter)throw new Error('Choose draw-things or comfyui in renderer configuration.');
  const recipe:NativeRecipe=config.recipe??(config.backend==='draw-things'?drawThingsPreset():comfyPreset());validateRecipe(recipe);
  if(recipe.backend!==config.backend)throw new Error('Recipe backend differs from renderer configuration.');
  let template:RunContext|null=null;
  return {renderer:adapter,recipe,label:config.backend==='draw-things'?'Draw Things CLI':'ComfyUI',context:async()=>{
    template??=await adapter.context();return structuredClone(template);
  },close:()=>{if(adapter instanceof ComfyAdapter)adapter.close();}};
}

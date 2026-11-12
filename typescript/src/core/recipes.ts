import { requireThat } from './errors';
export interface Asset { id: string; precision: string; revision: string; hash: string }
export interface LoRA { asset: Asset; modelWeight: number; encoderWeight: number | null }
interface RecipeBase { model: Asset; loras: LoRA[]; guidance: number }
export interface DrawThingsRecipe extends RecipeBase {
  backend: 'draw-things'; sampler: number; seedMode: number; resolutionDependentShift: false;
}
export interface ComfyRecipe extends RecipeBase {
  backend: 'comfyui'; sampler: string; scheduler: string; noisePolicy: 'native';
  textEncoder: Asset; vae: Asset;
  workflow: { id: string; version: string; hash: string; nodes: Record<string, string> };
}
export type NativeRecipe = DrawThingsRecipe | ComfyRecipe;
export const unknownAsset = (id: string, precision = 'unknown'): Asset => ({ id, precision, revision: 'unknown', hash: 'unknown' });
export function drawThingsPreset(): DrawThingsRecipe {
  return { backend: 'draw-things', model: unknownAsset('z_image_turbo_1.0_q6p.ckpt', 'q6p'), sampler: 17, seedMode: 2, guidance: 1, resolutionDependentShift: false, loras: [] };
}
export function validateRecipe(recipe: NativeRecipe): void {
  const asset = (a: Asset) => { requireThat(a && [a.id, a.precision, a.revision, a.hash].every(s => typeof s === 'string' && s.trim()), 'Assets need identity and explicit precision/revision/hash (or unknown).'); };
  asset(recipe.model);
  requireThat(Number.isFinite(recipe.guidance) && recipe.guidance >= 0, 'Guidance must be finite and nonnegative.');
  requireThat(Array.isArray(recipe.loras), 'LoRAs must be a list.');
  for (const lora of recipe.loras) { asset(lora.asset); requireThat(Number.isFinite(lora.modelWeight) && (lora.encoderWeight === null || Number.isFinite(lora.encoderWeight)), 'Invalid LoRA weights.'); }
  if (recipe.backend === 'draw-things') {
    requireThat(Number.isSafeInteger(recipe.sampler) && recipe.sampler >= 0 && Number.isSafeInteger(recipe.seedMode) && recipe.seedMode >= 0, 'Invalid Draw Things native settings.');
    requireThat(recipe.resolutionDependentShift === false, 'Automatic shift is unsupported by this baseline.');
  } else {
    requireThat(recipe.backend === 'comfyui' && recipe.noisePolicy === 'native', 'Unknown backend/noise policy.');
    asset(recipe.textEncoder); asset(recipe.vae);
    requireThat([recipe.sampler, recipe.scheduler, recipe.workflow?.id, recipe.workflow?.version, recipe.workflow?.hash].every(s => typeof s === 'string' && s.trim()), 'ComfyUI requires native sampler/scheduler and a versioned workflow.');
    requireThat(recipe.workflow.nodes && Object.values(recipe.workflow.nodes).every(v => typeof v === 'string' && v.trim()), 'Workflow node versions must be recorded (or unknown).');
  }
}

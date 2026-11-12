import { compile, Random, randomUnit } from './prompt';
import { deepFreeze, requireThat } from './errors';
import { NativeRecipe, validateRecipe } from './recipes';
export interface RunContext {
  id: string; createdAt: string;
  os: { name: string; version: string; arch: string };
  framework: { name: string; version: string };
  hardware: string; driver: string; computeRuntime: string; applicationVersion: string;
}
export interface ImageJob {
  schemaVersion: 1; id: string; batchId: string; runId: string; number: number;
  title: string; source: string; notes: string; prompt: string; sharedFields: Readonly<Record<string, string>>;
  seed: number; shift: string; steps: number; width: number; height: number;
  filename: string; recipe: NativeRecipe;
}
export interface FrozenBatch { schemaVersion: 1; id: string; title: string; createdAt: string; run: RunContext; jobs: readonly ImageJob[] }
export function validateContext(run: RunContext): void {
  requireThat(run && [run.id, run.createdAt, run.os?.name, run.os?.version, run.os?.arch, run.framework?.name, run.framework?.version,
    run.hardware, run.driver, run.computeRuntime, run.applicationVersion].every(v => typeof v === 'string' && v.trim()), 'Run context requires OS/framework and explicit unknown values for unavailable details.');
  requireThat(!Number.isNaN(Date.parse(run.createdAt)), 'Invalid run timestamp.');
}
export function safeTitle(title: string, budget: number): string {
  let value = '';
  for (const c of title) {
    const safe = /[\u0000-\u001f\u007f/\\:<>"|?*]/.test(c) ? '_' : c;
    if (new TextEncoder().encode(value + safe).length > budget) break;
    value += safe;
  }
  value = value.replace(/[. ]+$/g, '');
  if (/^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)/i.test(value)) value = '_' + value.slice(0, -1);
  return value || 'untitled';
}
export function filename(title: string, seed: number, steps: number, shift: string, number: number): string {
  const suffix = `_${seed}_${steps}_${shift}_${number}.png`, budget = 250 - new TextEncoder().encode(suffix).length;
  requireThat(budget >= 8, 'Shift spelling is too long for an output filename.');
  return safeTitle(title, budget) + suffix;
}
export function freezeBatch(source: string, recipe: NativeRecipe, run: RunContext, options: {
  random: Random; id: () => string; now?: number; continuing?: { id: string; title: string; lastNumber: number };
}): FrozenBatch {
  validateRecipe(recipe); validateContext(run);
  const compiled = compile(source, { now: options.now, defaultTitle: options.continuing?.title });
  const p = compiled.parameters;
  requireThat(!options.continuing || options.continuing.title === p.title, 'A changed title must start a new batch.');
  const batchId = options.continuing?.id ?? options.id();
  const start = (options.continuing?.lastNumber ?? 0) + 1;
  requireThat(Number.isSafeInteger(start) && start >= 1 && Number.isSafeInteger(start + p.count), 'Image numbering exceeds supported limits.');
  const integer = (lo: number, hi: number) => lo + Math.floor(randomUnit(options.random) * (hi - lo + 1));
  const jobs = Array.from({ length: p.count }, (_, index): ImageJob => {
    const seed = p.seeds[index] ?? integer(0, 2147483647), shiftEntry = p.shifts[index];
    const shift = shiftEntry.kind === 'fixed' ? shiftEntry.value : (integer(shiftEntry.low, shiftEntry.high) / 1000).toFixed(3);
    const resolved = compiled.resolve(options.random), number = start + index;
    return { schemaVersion: 1, id: options.id(), batchId, runId: run.id, number, title: p.title, source, notes: p.notes,
      ...resolved, seed, shift, steps: p.steps, width: p.width, height: p.height,
      filename: filename(p.title, seed, p.steps, shift, number), recipe: structuredClone(recipe) };
  });
  requireThat(new Set(jobs.map(j => j.id)).size === jobs.length, 'ID source produced duplicate job identifiers.');
  return deepFreeze({ schemaVersion: 1, id: batchId, title: p.title, createdAt: run.createdAt, run: structuredClone(run), jobs });
}
export function variant(source: ImageJob, change: { steps?: number; shift?: string }, number: number, id: string, runId: string): ImageJob {
  requireThat((change.steps !== undefined) !== (change.shift !== undefined), 'Choose one step or shift adjustment.');
  const shift = change.shift ?? source.shift, steps = change.steps ?? source.steps;
  const compiled = compile(`steps=${steps};shift=${shift};count=1;resolution=64*64\n`);
  requireThat(compiled.parameters.shifts[0].kind === 'fixed', 'Variant shift must be fixed.');
  const value = compiled.parameters.shifts[0].value;
  requireThat(Number.isSafeInteger(number) && number > 0 && id.trim() && runId.trim(), 'Variant requires valid identity and numbering.');
  return deepFreeze({ ...structuredClone(source), id, runId, number, steps, shift: value, filename: filename(source.title, source.seed, steps, value, number) });
}

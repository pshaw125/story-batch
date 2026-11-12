import { D, scalar, shifts, splitTopLevel } from './arithmetic';
import { requireThat } from './errors';
export type Shift = { kind: 'fixed'; value: string } | { kind: 'range'; low: number; high: number; source: string };
export interface Parameters {
  title: string; seeds: (number | null)[]; shifts: Shift[]; steps: number; count: number;
  width: number; height: number; aspect?: string; pixelMax: number; notes: string;
}
const keys = new Set(['title', 'seed', 'shift', 'steps', 'count', 'resolution', 'aspect', 'pixel_max', 'notes']);
export function headerEntries(header: string): string[] {
  const parts: string[] = []; let part = '', quote = '', escaped = false;
  for (const c of header) {
    if (escaped) { part += c; escaped = false; continue; }
    if (c === '\\') { part += c; escaped = true; continue; }
    if (quote) { part += c; if (c === quote) quote = ''; continue; }
    if ((c === '"' || c === "'") && part.includes('=') && part.slice(part.indexOf('=') + 1).trim() === '') quote = c;
    if (c === ';' && !quote) { parts.push(part); part = ''; } else part += c;
  }
  requireThat(!quote, 'Unclosed quote in parameter line.');
  parts.push(part); return parts;
}
function unquote(s: string): string {
  if (!s.startsWith('"') && !s.startsWith("'")) return s;
  requireThat(s.length >= 2 && s.at(-1) === s[0], 'Unclosed quoted value.');
  return s.slice(1, -1).replace(/\\(.)/gs, (whole, c: string) => [s[0], '\\', ';'].includes(c) ? c : whole);
}
function integer(s: string, label: string, min = 1, max = Number.MAX_SAFE_INTEGER): number {
  const n = Number(s);
  requireThat(/^\d+$/.test(s) && Number.isSafeInteger(n) && n >= min && n <= max, `${label} must be an integer from ${min} to ${max}.`);
  return n;
}
function seed(s: string): number | null { return s.trim() === '_' ? null : integer(s.trim(), 'Seed', 0, 2147483647); }
function range(input: string): Shift {
  const parts = input.split('..');
  requireThat(parts.length === 2, 'Shift range must be lower..upper.');
  const a = scalar(parts[0]), b = scalar(parts[1]);
  requireThat(a.gt(0) && a.lte(b), 'Shift range bounds must be positive and ordered.');
  const low = a.times(1000).ceil().toNumber(), high = b.times(1000).floor().toNumber();
  requireThat(Number.isSafeInteger(low) && Number.isSafeInteger(high) && low >= 1 && low <= high && Number.isFinite(Math.fround(high / 1000)),
    'Shift range must contain a supported positive thousandth. Use a fixed shift for finer precision.');
  return { kind: 'range', low, high, source: input };
}
function shiftEntries(raw: string, count: number): Shift[] {
  if (!raw.includes('..')) {
    const values = shifts(raw).map(value => ({ kind: 'fixed' as const, value }));
    if (values.length === 1) return Array.from({ length: count }, () => values[0]);
    requireThat(values.length === count, `Shift list has ${values.length} values, but count is ${count}.`);
    return values;
  }
  const items = splitTopLevel(raw);
  if (items.length === 1 && !raw.trim().endsWith('*')) return Array.from({ length: count }, () => range(raw));
  const entries: Shift[] = [];
  items.forEach((item, index) => {
    let s = item.trim(); const fill = s.endsWith('*');
    if (fill) { requireThat(index === items.length - 1 && s.includes('..'), 'Only the final shift range may use range*.'); s = s.slice(0, -1); }
    const values: Shift[] = s.includes('..') ? [range(s)] : shifts(s).map(value => ({ kind: 'fixed', value }));
    if (fill) {
      requireThat(entries.length <= count, `Shift list has ${entries.length} entries before range*, but count is ${count}.`);
      while (entries.length < count) entries.push(values[0]);
    } else entries.push(...values);
  });
  requireThat(entries.length === count, `Shift list has ${entries.length} values, but count is ${count}.`);
  return entries;
}
export function aspectSize(text: string, pixelMax: number): { width: number; height: number; aspect: string } {
  const parts = text.split(':').map(s => s.trim());
  requireThat(parts.length === 2, 'aspect must be two positive integers.');
  const a = integer(parts[0], 'aspect'), b = integer(parts[1], 'aspect');
  let x = a, y = b; while (y) { const r = x % y; x = y; y = r; }
  const p = a / x, q = b / x;
  requireThat(p <= 65535 && q <= 65535, 'Aspect exceeds supported dimensions.');
  let k = Math.min(Math.floor(Math.sqrt(pixelMax / (4096 * p * q))), Math.floor(65535 / p), Math.floor(65535 / q));
  while (k > 0 && (64 * p * k) * (64 * q * k) > pixelMax) k--;
  requireThat(k > 0, `No exact 64-pixel size for aspect ${p}:${q} fits pixel_max=${pixelMax}.`);
  return { width: 64 * p * k, height: 64 * q * k, aspect: `${p}:${q}` };
}
export function parseParameters(header: string, options: { now?: number; defaultTitle?: string } = {}): Parameters {
  const f = new Map<string, string>();
  for (const entry of headerEntries(header).filter(s => s.trim())) {
    const eq = entry.indexOf('='); requireThat(eq >= 0, 'Header entries must be key=value separated by semicolons.');
    let key = entry.slice(0, eq).trim().toLowerCase(); if (key === 'seeds') key = 'seed';
    requireThat(keys.has(key), `Unknown parameter '${key}'.`);
    requireThat(!f.has(key), `Parameter '${key}' appears more than once.`);
    f.set(key, unquote(entry.slice(eq + 1).trim()));
  }
  const title = f.get('title') ?? options.defaultTitle ?? String(Math.floor((options.now ?? Date.now()) / 1000));
  requireThat(title.trim(), 'Title cannot be empty.');
  const count = integer(f.get('count') ?? '4', 'count');
  // Guard allocation without changing the language: enormous rounds must be split by callers.
  requireThat(count <= 100000, 'A single request supports at most 100000 images; split larger rounds.');
  const steps = integer(f.get('steps') ?? '3', 'steps', 1, 4294967295);
  let seeds: (number | null)[];
  const rawSeed = f.get('seed') ?? '_';
  if (rawSeed.includes(',') || rawSeed === '_*') {
    const items = rawSeed.split(',').map(s => s.trim()); const fill = items.at(-1) === '_*'; if (fill) items.pop();
    requireThat(!items.includes('_*'), 'Seed remainder marker _* must appear only as the final item.');
    seeds = items.map(seed);
    if (fill) { requireThat(seeds.length <= count, `Seed list has ${seeds.length} entries before _*, but count is ${count}.`); while (seeds.length < count) seeds.push(null); }
    requireThat(seeds.length === count, `Seed list has ${seeds.length} values, but count is ${count}.`);
  } else seeds = Array.from({ length: count }, () => seed(rawSeed));
  const shiftList = shiftEntries(f.get('shift') ?? '1.5..2.25', count);
  requireThat(!(f.has('resolution') && f.has('aspect')), 'Use either resolution or aspect, not both.');
  const cap = scalar(f.get('pixel_max') ?? '1048576');
  requireThat(cap.gt(0) && cap.isInteger() && cap.lte(new D(Number.MAX_SAFE_INTEGER)), 'pixel_max must be one positive whole safe integer.');
  const pixelMax = cap.toNumber();
  let width = 1024, height = 1024, aspect: string | undefined;
  if (f.has('aspect')) ({ width, height, aspect } = aspectSize(f.get('aspect')!, pixelMax));
  if (f.has('resolution')) {
    const parts = f.get('resolution')!.toLowerCase().split(/[*x×]/).map(s => s.trim());
    requireThat(parts.length === 2, 'Resolution must be width*height.');
    width = integer(parts[0], 'width', 64, 64 * 65535); height = integer(parts[1], 'height', 64, 64 * 65535);
    requireThat(width % 64 === 0 && height % 64 === 0, 'Resolution dimensions must be multiples of 64.');
  }
  requireThat(width * height <= pixelMax, `Resolution ${width}*${height} exceeds pixel_max=${pixelMax}.`);
  return { title, count, steps, seeds, shifts: shiftList, width, height, aspect, pixelMax, notes: f.get('notes') ?? '' };
}

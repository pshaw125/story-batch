import { PromptError, requireThat, deepFreeze } from './errors';
import { parseParameters, Parameters } from './parameters';
export interface PromptDocument { header: string; prompt: string; fieldsText: string; hasFieldsSection: boolean }
const fieldName = /^[A-Za-z_][A-Za-z0-9_]*$/;
export function parseDocument(source: string): PromptDocument {
  const clean = source.replace(/^\uFEFF/, '').replace(/\r\n/g, '\n');
  const newline = clean.indexOf('\n');
  requireThat(newline >= 0, 'Put parameters on the first line, then a newline and the prompt.');
  const header = clean.slice(0, newline), lines = clean.slice(newline + 1).split('\n');
  const marker = lines.indexOf('%%FIELDS%%');
  return { header, prompt: (marker < 0 ? lines : lines.slice(0, marker)).join('\n'), fieldsText: marker < 0 ? '' : lines.slice(marker + 1).join('\n'), hasFieldsSection: marker >= 0 };
}
export function documentSource(d: PromptDocument): string {
  return `${d.header}\n${d.prompt}${d.hasFieldsSection || d.fieldsText ? `\n%%FIELDS%%\n${d.fieldsText}` : ''}`;
}
type Node = { kind: 'text'; text: string } | { kind: 'field'; name: string; fresh: boolean } | { kind: 'choice'; options: { nodes: Node[]; weight: number }[] };
class FragmentParser {
  private i = 0;
  private depth = 0;
  constructor(private text: string, private firstLine = 2) {}
  private error(message: string, at = this.i): never {
    const before = this.text.slice(0, at).split('\n');
    throw new PromptError(message, this.firstLine + before.length - 1, [...before.at(-1)!].length + 1);
  }
  private weight(): boolean { return this.text.startsWith(':::', this.i); }
  parse(): Node[] { return this.sequence(false); }
  private sequence(inChoice: boolean): Node[] {
    const nodes: Node[] = []; let text = '';
    const flush = () => { if (text) { nodes.push({ kind: 'text', text }); text = ''; } };
    while (this.i < this.text.length) {
      const c = this.text[this.i];
      if (inChoice && (c === '|' || c === '}' || this.weight())) break;
      if (c === '}') this.error('Closing brace has no matching opening brace.');
      if (c === '\\' && '{}|:\\[]'.includes(this.text[this.i + 1] ?? '\0')) { text += this.text[this.i + 1]; this.i += 2; continue; }
      if (c === '{') { flush(); nodes.push(this.choice()); continue; }
      if (c === '[') {
        const opened = this.i++, end = this.text.indexOf(']', this.i);
        if (end < 0) this.error('Field reference is not closed.', opened);
        let name = this.text.slice(this.i, end); const fresh = name.endsWith('*'); if (fresh) name = name.slice(0, -1);
        if (!fieldName.test(name)) this.error('Use [NAME] or [NAME*] for a field.', opened);
        flush(); nodes.push({ kind: 'field', name, fresh }); this.i = end + 1; continue;
      }
      text += c; this.i++;
    }
    flush(); return nodes;
  }
  private choice(): Node {
    const opened = this.i++;
    if (++this.depth > 256) this.error('Fragment nesting exceeds 256.', opened);
    try {
      const options: { nodes: Node[]; weight: number }[] = [];
      if (this.text[this.i] === '}') { this.i++; return { kind: 'choice', options }; }
      while (true) {
        const nodes = this.sequence(true); let weight = 1;
        if (this.weight()) {
          this.i += 3; const start = this.i;
          while (this.i < this.text.length && !'|}'.includes(this.text[this.i])) this.i++;
          const raw = this.text.slice(start, this.i).trim(); weight = Number(raw);
          if (!raw || !Number.isFinite(weight) || weight < 0) this.error('Weight must be a finite nonnegative number.', start);
        }
        options.push({ nodes, weight });
        if (this.i >= this.text.length) this.error('Fragment opened here is not closed.', opened);
        if (this.text[this.i++] === '}') {
          if (!options.some(o => o.weight > 0)) this.error('A fragment needs a positive-weight term.', opened);
          return { kind: 'choice', options };
        }
      }
    } finally { this.depth--; }
  }
}
export type Random = () => number;
export function randomUnit(random: Random): number {
  const n = random(); requireThat(Number.isFinite(n) && n >= 0 && n < 1, 'Random source must return a number in [0, 1).'); return n;
}
export interface Resolution { prompt: string; sharedFields: Readonly<Record<string, string>> }
export interface CompiledPrompt {
  readonly source: string; readonly parameters: Readonly<Parameters>;
  resolve(random: Random): Resolution;
}
export function compile(source: string, options: { now?: number; defaultTitle?: string } = {}): CompiledPrompt {
  requireThat(new TextEncoder().encode(source).length <= 2_000_000, 'Source document exceeds 2 MB.');
  const doc = parseDocument(source), parameters = parseParameters(doc.header, options);
  const root = new FragmentParser(doc.prompt).parse(), fields = new Map<string, Node[]>();
  let name: string | undefined, value: string[] = [], started = 0;
  const firstLine = doc.prompt.split('\n').length + 3;
  const append = () => { if (name !== undefined) fields.set(name, new FragmentParser(value.join('\n').trim(), started).parse()); };
  for (const [offset, line] of doc.fieldsText.split('\n').entries()) {
    const match = /^([A-Za-z_][A-Za-z0-9_]*)[ \t]*=(.*)$/.exec(line);
    if (match) {
      append(); name = match[1]; requireThat(!fields.has(name), `Field ${name} is defined more than once.`);
      value = [match[2]]; started = firstLine + offset;
    } else if (name !== undefined) value.push(line);
    else requireThat(!line.trim(), 'Start a field with NAME=value at the beginning of a line.');
  }
  append();
  // Memoize both maximum size and dependency height: cached suffixes must not hide long chains.
  const summaries = new Map<string, { size: number; height: number }>();
  const summarize = (nodes: Node[], chain: string[]): { size: number; height: number } => {
    let size = 0, height = 0;
    for (const node of nodes) {
      let summary = { size: 0, height: 0 };
      if (node.kind === 'text') summary.size = new TextEncoder().encode(node.text).length;
      if (node.kind === 'choice') {
        for (const option of node.options) { const v = summarize(option.nodes, chain); summary.size = Math.max(summary.size, v.size); summary.height = Math.max(summary.height, v.height); }
      }
      if (node.kind === 'field') {
        requireThat(fields.has(node.name), `Unknown field [${node.name}].`);
        requireThat(!chain.includes(node.name), `Circular field reference: ${[...chain, node.name].join(' → ')}`);
        requireThat(chain.length < 64, 'Field references exceed nesting depth 64.');
        let cached = summaries.get(node.name);
        if (!cached) { const v = summarize(fields.get(node.name)!, [...chain, node.name]); cached = { size: v.size, height: v.height + 1 }; summaries.set(node.name, cached); }
        summary = cached;
        requireThat(chain.length + cached.height <= 64, 'Field references exceed nesting depth 64.');
      }
      size += summary.size; height = Math.max(height, summary.height);
      requireThat(size <= 1_000_000, 'Expanded prompt or field exceeds 1 MB.');
    }
    return { size, height };
  };
  for (const key of [...fields.keys()].sort()) summarize([{ kind: 'field', name: key, fresh: false }], []);
  summarize(root, []);
  return deepFreeze({ source, parameters, resolve(random: Random): Resolution {
    const shared = new Map<string, string>();
    const resolve = (nodes: Node[]): string => nodes.map(node => {
      if (node.kind === 'text') return node.text;
      if (node.kind === 'field') {
        if (!node.fresh && shared.has(node.name)) return shared.get(node.name)!;
        const text = resolve(fields.get(node.name)!); if (!node.fresh) shared.set(node.name, text); return text;
      }
      const positive = node.options.filter(o => o.weight > 0);
      if (!positive.length) return '';
      if (positive.length === 1) return resolve(positive[0].nodes);
      const scale = positive.reduce((n, o) => Math.max(n, o.weight), 0), total = positive.reduce((n, o) => n + o.weight / scale, 0);
      const pick = randomUnit(random) * total; let sum = 0;
      for (const o of positive) { sum += o.weight / scale; if (pick < sum) return resolve(o.nodes); }
      return resolve(positive.at(-1)!.nodes);
    }).join('');
    const prompt = resolve(root);
    return deepFreeze({ prompt, sharedFields: Object.fromEntries(shared) });
  } });
}

import Decimal from 'decimal.js';
import { PromptError, requireThat } from './errors';
// Isolated constructor: another module cannot change our expression precision.
export const D = Decimal.clone({ precision: 38, rounding: Decimal.ROUND_HALF_UP, maxE: 127, minE: -128 });
const literal = /^\+?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$/;
export function shiftValue(input: string): string {
  const raw = input.trim();
  const n = Number(raw);
  requireThat(literal.test(raw) && Number.isFinite(n) && n > 0 && Number.isFinite(Math.fround(n)) && Math.fround(n) > 0,
    'Shift must be a finite positive number supported by the renderer.');
  return raw;
}
// Recursive descent; lists are vectors, scalars broadcast, vector operations pair.
export function arithmetic(input: string): Decimal[] {
  requireThat(input.length <= 4096, 'Expression is too long.');
  let i = 0, depth = 0;
  type Value = { values: Decimal[]; vector: boolean };
  const fail = (s: string): never => { throw new PromptError(`Expression at character ${i + 1}: ${s}`); };
  const spaces = () => { while (/\s/.test(input[i] ?? '') && i < input.length) i++; };
  const take = (c: string) => { spaces(); if (input[i] === c) { i++; return true; } return false; };
  const calculate = (a: Value, b: Value, op: string): Value => {
    if (a.vector && b.vector && a.values.length !== b.values.length) fail('Lists must have equal lengths.');
    const length = a.vector ? a.values.length : b.values.length;
    const values = Array.from({ length }, (_, j) => {
      const x = a.values[a.vector ? j : 0], y = b.values[b.vector ? j : 0];
      if (op === '/' && y.isZero()) fail('Division by zero is not allowed.');
      const r = op === '+' ? x.plus(y) : op === '-' ? x.minus(y) : op === '*' ? x.times(y) : x.div(y);
      if (!r.isFinite() || (!x.isZero() && !y.isZero() && op !== '+' && op !== '-' && r.isZero())) fail('Arithmetic overflow or underflow.');
      return r;
    });
    return { values, vector: a.vector || b.vector };
  };
  function factor(): Value {
    if (++depth > 64) fail('Expression nesting exceeds 64.');
    try {
      if (take('+')) return factor();
      if (take('-')) return calculate({ values: [new D(0)], vector: false }, factor(), '-');
      if (take('(')) { const v = list(); if (!take(')')) fail('Missing closing parenthesis.'); return v; }
      spaces();
      const match = /^(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?/.exec(input.slice(i));
      requireThat(match, 'Expected a number.');
      i += match[0].length;
      const n = new D(match[0]);
      if (!n.isFinite() || (n.isZero() && /[1-9]/.test(match[0].split(/[eE]/)[0]))) fail('Number exceeds decimal limits.');
      return { values: [n], vector: false };
    } finally { depth--; }
  }
  function product(): Value {
    let a = factor();
    while (true) { if (take('*')) a = calculate(a, factor(), '*'); else if (take('/')) a = calculate(a, factor(), '/'); else return a; }
  }
  function sum(): Value {
    let a = product();
    while (true) { if (take('+')) a = calculate(a, product(), '+'); else if (take('-')) a = calculate(a, product(), '-'); else return a; }
  }
  function list(): Value {
    const first = sum();
    if (!take(',')) return first;
    const values = [...first.values];
    do { values.push(...sum().values); } while (take(','));
    return { values, vector: true };
  }
  const result = list(); spaces();
  if (i !== input.length) fail('Unexpected character; supported operations are + - * / and parentheses.');
  return result.values;
}
export function splitTopLevel(input: string): string[] {
  let depth = 0, start = 0;
  const parts: string[] = [];
  for (let i = 0; i < input.length; i++) {
    if (input[i] === '(') depth++;
    if (input[i] === ')') depth--;
    if (input[i] === ',' && depth === 0) { parts.push(input.slice(start, i)); start = i + 1; }
  }
  parts.push(input.slice(start));
  return parts;
}
export function shifts(input: string): string[] {
  const parts = splitTopLevel(input);
  if (parts.length > 1) return parts.flatMap(shifts);
  if (literal.test(input.trim())) return [shiftValue(input)];
  return arithmetic(input).map(n => shiftValue(n.toFixed()));
}
export function scalar(input: string): Decimal {
  const result = arithmetic(input);
  requireThat(result.length === 1, 'Expected one scalar value.');
  return result[0];
}

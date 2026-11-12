import { test } from 'node:test';
import assert from 'node:assert/strict';
import { arithmetic, shifts } from '../src/core/arithmetic';
import { parseParameters } from '../src/core/parameters';
import { compile, documentSource, parseDocument } from '../src/core/prompt';
const resolve = (text: string, r = () => 0) => compile('\n' + text).resolve(r).prompt;
test('defaults and quoted header transport', () => {
  const p = parseParameters('', { now: 1234000 });
  assert.equal(p.title, '1234'); assert.equal(p.count, 4); assert.equal(p.steps, 3);
  assert.equal(p.width, 1024); assert.equal(p.height, 1024); assert.deepEqual(p.seeds, [null,null,null,null]);
  assert.deepEqual(p.shifts[0], { kind: 'range', low: 1500, high: 2250, source: '1.5..2.25' });
  const q = parseParameters('title="a; b=2"; notes="don\'t; stop"; SEEDS=0001; shift=+04.55000');
  assert.equal(q.title, 'a; b=2'); assert.equal(q.notes, "don't; stop"); assert.deepEqual(q.seeds, [1,1,1,1]);
  assert.equal(q.shifts[0].kind === 'fixed' && q.shifts[0].value, '+04.55000');
  assert.equal(parseParameters('notes=person\'s hat').notes, "person's hat");
});
test('document BOM CRLF multiline and field round trip', () => {
  const s = '\uFEFFcount=1\r\n[A] [EMPTY] \\[literal\\]\r\n%%FIELDS%%\r\nA=First line\r\nSecond line [B]\r\nB={red}\r\nEMPTY=\r\n';
  const d = parseDocument(s); assert.equal(documentSource(d), s.slice(1).replace(/\r\n/g,'\n'));
  assert.equal(compile(s).resolve(() => 0).prompt, 'First line\nSecond line red  [literal]');
});
test('seed lists pair by usage order; remainder handles independent slots', () => {
  assert.deepEqual(parseParameters('count=4; seed=1234,_,_*').seeds, [1234,null,null,null]);
  assert.deepEqual(parseParameters('count=1; seed=7,_*').seeds, [7]);
  assert.deepEqual(parseParameters('count=2; seeds=_*').seeds, [null,null]);
  assert.deepEqual(parseParameters('count=3; seed=1234,_,_; shift=2,3.5,4.55').shifts.map(s => s.kind === 'fixed' && s.value), ['2','3.5','4.55']);
});
test('decimal math, precedence, scientific notation and preserved literals', () => {
  assert.deepEqual(shifts('2.25+0.5,2.25+0.5,2.4-0.1,2.1+2'), ['2.75','2.75','2.3','4.1']);
  assert.deepEqual(shifts('(2.25,2.25,2.4,2.1)+0.5'), ['2.75','2.75','2.9','2.6']);
  assert.deepEqual(shifts('0.5+(2.25,2.25,2.4,2.1)'), ['2.75','2.75','2.9','2.6']);
  assert.deepEqual(shifts('(2.25+0.5,2.4-0.1)*2'), ['5.5','4.6']);
  assert.deepEqual(shifts('(1,2)+(3,4)'), ['4','6']);
  assert.deepEqual(shifts('8/(1,2)'), ['8','4']);
  assert.deepEqual(shifts('0.1+0.2'), ['0.3']);
  assert.deepEqual(shifts('2*(1+2)-3/2'), ['4.5']);
  assert.deepEqual(shifts('4.550123,1e-1'), ['4.550123','1e-1']);
  assert.equal(arithmetic('1/3')[0].toFixed(), '0.33333333333333333333333333333333333333');
});
test('shift range endpoints are rounded inward; mixed remainder fills count', () => {
  const p = parseParameters('count=6; shift=1.3,2.4,1.3001..1.4009,1.3..2.0*');
  assert.equal(p.shifts.length, 6); assert.deepEqual(p.shifts[2], {kind:'range',low:1301,high:1400,source:'1.3001..1.4009'});
  assert.deepEqual(p.shifts[3], p.shifts[5]);
  assert.deepEqual(parseParameters('count=1; shift=2,1..2*').shifts, [{kind:'fixed',value:'2'}]);
  assert.equal(parseParameters('shift=(2+0.25)..(3-0.5)').shifts[0].kind, 'range');
});
test('aspect sizing uses normalized exact ratio and grid', () => {
  for (const aspect of ['9:7', '18:14']) {
    const p = parseParameters(`aspect=${aspect}`); assert.deepEqual([p.width,p.height,p.aspect], [1152,896,'9:7']);
  }
  assert.deepEqual([parseParameters('aspect=16:9').width,parseParameters('aspect=16:9').height],[1024,576]);
  const p = parseParameters('aspect=9:7; pixel_max=(2048*2048)'); assert.deepEqual([p.width,p.height],[2304,1792]);
  assert.equal(parseParameters('aspect=1:1;pixel_max=512*512').width,512);
  assert.equal(parseParameters('resolution=1152×896').width,1152);
});
for (const header of [
  'unknown=1','seed=1;seeds=2','count=0','steps=0','title=','seed=2147483648','seed=-1','seed=1,2;count=3',
  'seed=_*,1','seed=1,2,_*;count=1','seed=1,,2','shift=0','shift=-1','shift=NaN','shift=1e99',
  'shift=1/0','shift=1+','shift=(1,2)+(1,2,3)','shift=1..0','shift=.00001...00002',
  'shift=1.00001..1.00002','shift=1,2*','shift=1..2*,3;count=2','shift=1,2,1..2*;count=1',
  'shift=1,2;count=3','resolution=1024*1024;aspect=1:1','resolution=63*64','resolution=2048*2048',
  'aspect=0:1','aspect=999999:1','pixel_max=1024','pixel_max=1.5','pixel_max=(1,2)','pixel_max=2**3',
  'shift=process.exit()','title="unfinished','count=100001'
]) test(`parameter error: ${header}`, () => assert.throws(() => parseParameters(header)));
test('weighted/empty/duplicate alternatives and escaped literals', () => {
  assert.equal(resolve('{} {one} {a||b}', () => 0.5), ' one ');
  assert.equal(resolve('{red:::2|green:::3|red with a {worm|caterpillar}:::0.5}', () => .5),'green');
  assert.equal(resolve('{a:::0|b}', () => 0),'b');
  assert.equal(resolve('\\{red\\|green\\} \\[x\\] \\:'),'{red|green} [x] :');
  assert.equal(resolve('{a|a|b}', () => .5),'a');
  assert.equal(resolve('{a:::1e308|b:::1e308}', () => .75),'b');
});
test('nested choices are lazy, unused fields and deterministic alternatives draw nothing', () => {
  let calls = 0; const r = () => { calls++; return 0; };
  assert.equal(compile('\n{only} {} {yes|{no|never}}\n%%FIELDS%%\nUNUSED={x|y}').resolve(r).prompt, 'only  yes');
  assert.equal(calls, 1);
});
test('shared parent caches its complete result; fresh does not seed or overwrite shared cache', () => {
  const draws = [0, .75, .2]; let i = 0;
  const c = compile('\n[X*]|[X]|[X]|[X*]\n%%FIELDS%%\nX={a|b}');
  assert.equal(c.resolve(() => draws[i++]).prompt,'a|b|b|a'); assert.equal(i,3);
  assert.equal(c.resolve(() => 0).prompt, 'a|a|a|a');
  let j=0; const d=compile('\n[A]|[A]|[B]|[B]\n%%FIELDS%%\nA=[B*] {x|y}\nB={red|green}');
  const result=d.resolve(() => [0,.75,.75][j++]).prompt;
  assert.equal(result,'red y|red y|green|green'); assert.equal(j,3);
});
for (const text of ['{unclosed','{x|{y}','x}','{a:::NaN|b}','{a:::-1|b}','{a:::0|b:::0}', '[BAD', '[bad-name]', '[UNKNOWN]',
  'ok\n%%FIELDS%%\nUNUSED={[MISSING]:::0|ok}', '[A]\n%%FIELDS%%\nA=[B*]\nB=[A]', 'ok\n%%FIELDS%%\nA=x\nA=y',
  'ok\n%%FIELDS%%\nnot a definition']) test(`fragment/field error: ${text}`, () => assert.throws(() => compile('\n'+text)));
test('error locations and bounded nesting/expansion including cached chains', () => {
  assert.throws(() => compile('\nline\n{broken'), /Line 3, column 1/);
  assert.throws(() => compile('no newline'));
  assert.throws(() => resolve('{'.repeat(257)+'x'+'}'.repeat(257)), /256/);
  const chain = Array.from({length:66},(_,i)=>`F${i}=${i ? `[F${i-1}]` : 'end'}`).join('\n');
  assert.throws(() => compile('\n[F65]\n%%FIELDS%%\n'+chain), /64/);
  const expand='A='+ 'x'.repeat(1024)+'\n'+Array.from({length:11},(_,i)=>`F${i}=${(i ? `[F${i-1}]` : '[A]').repeat(2)}`).join('\n');
  assert.throws(() => compile('\n[F10]\n%%FIELDS%%\n'+expand), /1 MB/);
  assert.throws(() => shifts('('.repeat(65)+'1'+')'.repeat(65)), /64/);
});

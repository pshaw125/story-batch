const { readdirSync } = require('node:fs');
const { join } = require('node:path');
const { spawnSync } = require('node:child_process');
// Expand explicitly: Windows cmd.exe does not expand shell globs.
const folder = join(__dirname,'../dist/test');
const files = readdirSync(folder).filter(f=>f.endsWith('.test.js')).sort().map(f=>join(folder,f));
if (!files.length) throw new Error('No compiled tests found.');
const result = spawnSync(process.execPath,['--test',...files],{stdio:'inherit'});
if(result.error) throw result.error;
process.exitCode = result.status ?? 1;

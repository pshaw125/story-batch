const { readFileSync, existsSync } = require('node:fs');
const { join, resolve, relative } = require('node:path');
const { spawn } = require('node:child_process');
function installedElectron() {
  const root = join(__dirname, '../node_modules/electron');
  let name;
  try { name = readFileSync(join(root, 'path.txt'), 'utf8').trim(); } catch { throw new Error('Electron runtime missing. Explicitly run npm run setup:electron during dependency procurement.'); }
  const directory = resolve(root, 'dist'), executable = resolve(directory, name);
  if (!name || relative(directory, executable).startsWith('..') || !existsSync(executable)) throw new Error('Electron runtime missing/invalid. Run npm run setup:electron; launch never downloads it.');
  return executable;
}
module.exports = { installedElectron };
if (require.main === module) {
  try {
    const child = spawn(installedElectron(), [join(__dirname, '..'), ...process.argv.slice(2)], { stdio: 'inherit', windowsHide: false });
    child.on('error', e => { console.error(e); process.exitCode = 1; });
    child.on('exit', code => { process.exitCode = code ?? 1; });
    for (const signal of ['SIGINT','SIGTERM']) process.on(signal, () => child.kill(signal));
  } catch (e) { console.error(e.message); process.exitCode = 1; }
}

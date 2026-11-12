const { packager } = require('@electron/packager');
const { mkdtemp, mkdir, cp, writeFile, rm } = require('node:fs/promises');
const { join } = require('node:path');
const { tmpdir } = require('node:os');
// Inclusion-list staging excludes live prompts, reports, local config and dev tools.
(async () => {
  const staging = await mkdtemp(join(tmpdir(), 'story-batch-package-'));
  try {
    await cp(join(__dirname,'../dist/src'), join(staging,'dist/src'), {recursive:true});
    const p = require('../package.json');
    await writeFile(join(staging,'package.json'), JSON.stringify({name:p.name,version:p.version,main:p.main,dependencies:p.dependencies}));
    await mkdir(join(staging,'node_modules'), {recursive:true});
    for(const name of Object.keys(p.dependencies)) await cp(join(__dirname,'../node_modules',name), join(staging,'node_modules',name), {recursive:true});
    const paths = await packager({dir:staging,name:'Story Batch',out:join(__dirname,'../artifacts'),
      platform:process.platform,arch:process.arch,electronVersion:require('electron/package.json').version,overwrite:true,
      appBundleId:'local.storybatch.typescript',asar:true,prune:false});
    console.log(paths.join('\n'));
  } finally { await rm(staging,{recursive:true,force:true}); }
})().catch(e => {console.error(e);process.exitCode=1;});

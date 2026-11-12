const {copyFileSync}=require('node:fs');
const {join}=require('node:path');
const {buildSync}=require('esbuild');
for(const file of ['index.html','style.css'])copyFileSync(join(__dirname,'../src/desktop',file),join(__dirname,'../dist/src/desktop',file));
buildSync({entryPoints:[join(__dirname,'../src/desktop/ui/index.ts')],outfile:join(__dirname,'../dist/src/desktop/renderer.js'),bundle:true,platform:'browser',format:'iife',target:'es2022',logLevel:'warning'});

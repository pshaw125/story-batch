// Synthetic CLI fixture only. Never loads a model.
const fs=require('node:fs');const path=require('node:path');const {PNG}=require('pngjs');
const args=process.argv.slice(2),arg=k=>args[args.indexOf(k)+1];
if(args.includes('--version')){console.log('synthetic-cli-1');process.exit(0);}
const mode=arg('--test-mode'),output=arg('--output'),config=JSON.parse(fs.readFileSync(arg('--config-file'),'utf8'));
if(!args.includes('--local')||!args.includes('--offline')||!args.includes('--no-download-missing'))throw new Error('Missing offline flags');
if(mode==='missing'){console.error('Missing local model dependencies; not downloaded');process.exit(1);}
if(mode==='failure'){console.error('Synthetic transient render failure');process.exit(1);}
if(mode==='once'){
 const marker=path.join(path.dirname(path.dirname(output)),'failed-once');
 if(!fs.existsSync(marker)){fs.writeFileSync(marker,'1');fs.writeFileSync(output,'partial failed PNG');process.exit(1);}
}
if(mode==='hang'){setInterval(()=>{},1000);return;}
if(mode==='incomplete'){fs.writeFileSync(output,Buffer.from([137,80,78,71,13,10,26,10]));return;}
const png=new PNG({width:mode==='wrong-size'?128:config.width,height:config.height});png.data.fill(120);
console.log(`Sampling... 1 / ${config.steps}`);
setTimeout(()=>{fs.writeFileSync(output,PNG.sync.write(png));console.log(`Sampling... ${config.steps} / ${config.steps}`);console.log(`Sampling step time (${config.steps} steps): 0.1s`);console.log("Total generation time (including model loading): 1.25s");},20);

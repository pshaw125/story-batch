import { createServer, IncomingMessage, ServerResponse } from 'node:http';
import { randomUUID } from 'node:crypto';
import { WebSocketServer } from 'ws';
import { PNG } from 'pngjs';
import { comfyPreset, comfyWorkflow } from '../../src/node/comfy-workflow';
import { freezeBatch } from '../../src/core/planning';
import { runContext } from '../../src/node/environment';
export async function fakeComfy(mode='success') {
  const posts:any[]=[];const uploads:{name:string;bytes:Buffer}[]=[];const history:Record<string,any>={};let running:any[]=[],pending:any[]=[];let interrupts=0;
  const template=freezeBatch('count=1;resolution=64*64\nsynthetic',comfyPreset(),runContext('fake-comfy','1'),{random:()=>.5,id:randomUUID}).jobs[0];
  const info:Record<string,any>={};
  for(const node of Object.values(comfyWorkflow(template,'test'))){
    const required:Record<string,any>={};for(const [key,value]of Object.entries(node.inputs)){
      required[key]=[typeof value==='number'?'FLOAT':'STRING',{}];
      if(key==='sampler_name')required[key]=[['res_multistep','euler']];
      if(key==='scheduler')required[key]=[['simple']];
      if(key==='shift')required[key]=['FLOAT',{min:0,max:100}];
    }
    info[node.class_type]={input:{required}};
  }
  info.LoadImage={input:{required:{image:[['existing.png']]}}};info.VAEEncode={input:{required:{pixels:['IMAGE'],vae:['VAE']}}};info.LoraLoaderModelOnly={input:{required:{model:['MODEL'],lora_name:[['synthetic-style.safetensors','first.safetensors','second.safetensors']],strength_model:['FLOAT',{min:-100,max:100}]}}};
  if(mode==='missing-node')delete info.ModelSamplingAuraFlow;
  const image=new PNG({width:mode==='wrong-size'?128:64,height:64});image.data.fill(160);
  const bytes=mode==='incomplete'?Buffer.from('invalid image'):PNG.sync.write(image);
  const json=(res:ServerResponse,data:unknown,status=200)=>{res.writeHead(status,{'content-type':'application/json'});res.end(JSON.stringify(data));};
  const read=async(req:IncomingMessage)=>{let text='';for await(const b of req)text+=b;return JSON.parse(text);};
  const server=createServer((req,res)=>{void(async()=>{
    const url=new URL(req.url!,'http://127.0.0.1');
    if(url.pathname==='/upload/image'){if(mode==='upload-failed')return json(res,{error:'synthetic upload failure'},400);const chunks=[];for await(const chunk of req)chunks.push(Buffer.from(chunk));const form=await new Request(url,{method:'POST',headers:{'content-type':req.headers['content-type']!},body:new Uint8Array(Buffer.concat(chunks))}).formData();const image=form.get('image') as File;uploads.push({name:image.name,bytes:Buffer.from(await image.arrayBuffer())});return json(res,{name:image.name,subfolder:'story-batch',type:'input'});}
    if(url.pathname==='/view'&&url.searchParams.get('type')==='input'){res.writeHead(200,{'content-type':'image/png'});res.end(mode==='bad-upload'?bytes:uploads.find(u=>u.name===url.searchParams.get('filename'))?.bytes);return;}
    if(url.pathname==='/object_info')return json(res,info);
    if(url.pathname.startsWith('/models/'))return json(res,mode==='missing-model'||mode==='missing-lora'&&url.pathname==='/models/loras'?[]:['synthetic-style.safetensors','first.safetensors','second.safetensors',comfyPreset().model.id,comfyPreset().textEncoder.id,comfyPreset().vae.id]);
    if(url.pathname==='/system_stats')return json(res,{system:{comfyui_version:'synthetic-1',python_version:'test',pytorch_version:'test'},devices:[{name:'synthetic'}]});
    if(url.pathname==='/prompt'&&req.method==='POST'){
      const body=await read(req);posts.push(body);
      if(mode==='invalid-workflow')return json(res,{error:'synthetic invalid workflow',node_errors:{'7':'invalid'}},400);
      const id=mode==='lost-ack-assigned'?randomUUID():body.prompt_id;
      const item=[0,id,body.prompt,body.extra_data,['10']];
      if(mode==='queued')pending=[item];else if(mode!=='uncertain')running=[item];
      if(!['queued','hang','uncertain','foreign'].includes(mode))setTimeout(()=>{
        const failed=mode==='failure'||mode==='once'&&posts.length===1;
        history[id]={prompt:item,status:{completed:true,status_str:failed?'error':'success',messages:failed?[['execution_error',{exception_message:'synthetic failure'}]]:mode==='cached'?[['execution_cached',{nodes:['8']}]]:[['execution_success',{}]]},outputs:failed?{}:{'10':{images:[{filename:'synthetic.png',subfolder:'story-batch',type:'output'}]}}};running=[];
        for(const c of sockets.clients){if(mode==='lost-socket')c.terminate();else c.send(JSON.stringify({type:'progress',data:{prompt_id:id,value:1,max:3}}));}
      },30).unref();
      if(mode==='foreign')running.push([1,'foreign',{},{}]);
      if(mode.startsWith('lost-ack')||mode==='uncertain')return req.socket.destroy();
      return json(res,{prompt_id:id,number:0,node_errors:{}});
    }
    if(url.pathname==='/queue'&&req.method==='GET')return json(res,{queue_running:running,queue_pending:pending});
    if(url.pathname==='/queue'&&req.method==='POST'){const body=await read(req);pending=pending.filter(i=>!body.delete.includes(i[1]));res.end();return;}
    if(url.pathname==='/interrupt'){
      interrupts++;for(const item of running.filter(i=>i[1]!=='foreign'))history[item[1]]={prompt:item,status:{completed:false,status_str:'error',messages:[['execution_interrupted',{}]]},outputs:{}};
      running=[];return json(res,{});
    }
    if(url.pathname==='/history')return json(res,history);
    if(url.pathname.startsWith('/history/')){const id=decodeURIComponent(url.pathname.slice(9));return json(res,history[id]?{[id]:history[id]}:{});}
    if(url.pathname==='/view'){res.writeHead(200,{'content-type':'image/png'});res.end(bytes);return;}
    json(res,{error:'missing route'},404);
  })().catch(e=>json(res,{error:String(e)},500));});
  const sockets=new WebSocketServer({server});
  await new Promise<void>(resolve=>server.listen(0,'127.0.0.1',resolve));
  const address=server.address();if(!address||typeof address==='string')throw new Error('Missing fake port.');
  return {url:`http://127.0.0.1:${address.port}`,posts,uploads,get interrupts(){return interrupts;},async close(){for(const c of sockets.clients)c.terminate();await new Promise<void>(resolve=>sockets.close(()=>resolve()));server.closeAllConnections();await new Promise<void>(resolve=>server.close(()=>resolve()));}};
}

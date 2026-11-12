import { createHash } from 'node:crypto';
import { ImageJob } from '../core/planning';
import { ComfyRecipe, unknownAsset } from '../core/recipes';
import { RenderError } from '../core/renderer';
export const workflowVersion='story-batch/z-image-turbo-txt2img/1';
export const workflowNodes=['UNETLoader','CLIPLoader','VAELoader','CLIPTextEncode','ConditioningZeroOut','EmptySD3LatentImage','ModelSamplingAuraFlow','KSampler','VAEDecode','SaveImage'] as const;
export const workflowHash=createHash('sha256').update(JSON.stringify({version:workflowVersion,nodes:workflowNodes,clipType:'lumina2',batchSize:1,denoise:1,negative:'zero-conditioning',shift:'ModelSamplingAuraFlow',output:'SaveImage'})).digest('hex');
export function comfyPreset():ComfyRecipe {
  return {backend:'comfyui',model:unknownAsset('z_image_turbo_bf16.safetensors','bf16'),textEncoder:unknownAsset('qwen_3_4b.safetensors','unknown'),vae:unknownAsset('ae.safetensors'),
    loras:[],guidance:1,sampler:'res_multistep',scheduler:'simple',noisePolicy:'native',workflow:{id:workflowVersion,version:'1',hash:workflowHash,nodes:Object.fromEntries(workflowNodes.map(n=>[n,'comfy-core; installed version recorded in run context']))}};
}
export interface WorkflowNode { class_type:string; inputs:Record<string,unknown> }
export type Workflow=Record<string,WorkflowNode>;
export function comfyWorkflow(job:ImageJob, outputPrefix:string, uploadedImage?:string):Workflow {
  if(job.recipe.backend!=='comfyui'||!((job.recipe.workflow.id===workflowVersion&&job.recipe.workflow.hash===workflowHash)||(job.recipe.workflow.id===toolsVersion&&job.recipe.workflow.hash===toolsHash)))throw new RenderError('Unsupported ComfyUI workflow/LoRA recipe.','validation');
  const r=job.recipe;
  if((job.input||r.loras.length)&&r.workflow.id!==toolsVersion)throw new RenderError('Image inputs and LoRAs require the explicit tools/v2 native workflow.','validation');
  if(r.loras.some(l=>l.encoderWeight!==null&&l.encoderWeight!==0||l.nativeVersion!==undefined))throw new RenderError('Z-Image tools workflow supports model-only LoRAs; encoder weights must be null or zero.','validation');
  const graph:Workflow={
    '1':{class_type:'UNETLoader',inputs:{unet_name:r.model.id,weight_dtype:'default'}},
    '2':{class_type:'CLIPLoader',inputs:{clip_name:r.textEncoder.id,type:'lumina2',device:'default'}},
    '3':{class_type:'VAELoader',inputs:{vae_name:r.vae.id}},
    '4':{class_type:'CLIPTextEncode',inputs:{text:job.prompt,clip:['2',0]}},
    '5':{class_type:'ConditioningZeroOut',inputs:{conditioning:['4',0]}},
    '6':{class_type:'EmptySD3LatentImage',inputs:{width:job.width,height:job.height,batch_size:1}},
    '7':{class_type:'ModelSamplingAuraFlow',inputs:{model:['1',0],shift:Number(job.shift)}},
    '8':{class_type:'KSampler',inputs:{model:['7',0],seed:job.seed,steps:job.steps,cfg:r.guidance,sampler_name:r.sampler,scheduler:r.scheduler,positive:['4',0],negative:['5',0],latent_image:['6',0],denoise:1}},
    '9':{class_type:'VAEDecode',inputs:{samples:['8',0],vae:['3',0]}},
    '10':{class_type:'SaveImage',inputs:{images:['9',0],filename_prefix:outputPrefix}}
  };
  let model:unknown=['1',0];for(const [index,lora] of r.loras.entries()){const id=String(20+index);graph[id]={class_type:'LoraLoaderModelOnly',inputs:{model,lora_name:lora.asset.id,strength_model:lora.modelWeight}};model=[id,0];}graph['7'].inputs.model=model;
  if(job.input){graph['11']={class_type:'LoadImage',inputs:{image:uploadedImage??'story-batch-validation.png'}};graph['12']={class_type:'VAEEncode',inputs:{pixels:['11',0],vae:['3',0]}};graph['8'].inputs.latent_image=['12',0];graph['8'].inputs.denoise=job.input.strength;delete graph['6'];}
  return graph;
}

export const toolsVersion='story-batch/z-image-turbo-tools/2';
export const toolsNodes=[...workflowNodes,'LoadImage','VAEEncode','LoraLoaderModelOnly'] as const;
export const toolsHash=createHash('sha256').update(JSON.stringify({version:toolsVersion,nodes:toolsNodes,preprocessing:'bilinear-rgba-white-v1',loras:'model-only-ordered',denoise:'native'})).digest('hex');
export function withComfyTools(recipe:ComfyRecipe):ComfyRecipe {if(![workflowVersion,toolsVersion].includes(recipe.workflow.id))throw new RenderError('Cannot replace an unsupported custom workflow implicitly.','validation');return {...structuredClone(recipe),workflow:{id:toolsVersion,version:'2',hash:toolsHash,nodes:Object.fromEntries(toolsNodes.map(n=>[n,'comfy-core; installed version recorded in run context']))}};}

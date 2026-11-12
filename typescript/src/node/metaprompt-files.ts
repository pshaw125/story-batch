import {readFile,writeFile} from 'node:fs/promises';
import {parseDocument} from '../core/prompt';
export class MetapromptFiles {
  path:string|null=null;
  private validate(source:unknown):asserts source is string {if(typeof source!=='string'||Buffer.byteLength(source)>2_000_000)throw new Error('Metaprompt must be text up to 2 MB.');}
  async open(path:string):Promise<{source:string;path:string}>{
    const source=await readFile(path,'utf8');this.validate(source);parseDocument(source);this.path=path;return {source,path};
  }
  async save(source:string,path=this.path):Promise<string>{
    this.validate(source);if(!path)throw new Error('Choose a file before saving.');await writeFile(path,source);this.path=path;return path;
  }
}

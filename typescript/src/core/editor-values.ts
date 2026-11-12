import {headerEntries} from './parameters';
import {documentSource,parseDocument} from './prompt';
export function replaceParameter(source:string,key:'seeds'|'shift',values:readonly string[]):string{
  if(!values.length)throw new Error('No completed images are available to collect.');
  const document=parseDocument(source);let replaced=false;const entries:string[]=[];
  for(const entry of headerEntries(document.header)){
    const name=entry.slice(0,entry.indexOf('=')).trim().toLowerCase();
    if(key==='seeds'?name==='seed'||name==='seeds':name==='shift'){
      if(!replaced){entries.push(`${key}=${values.join(',')}`);replaced=true;}
    }else if(entry.trim())entries.push(entry);
  }
  if(!replaced)entries.push(`${key}=${values.join(',')}`);
  document.header=entries.join(';');return documentSource(document);
}

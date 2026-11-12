import {documentSource,parseDocument} from '../../core/prompt';
export class Editor {
  readonly parameters=document.querySelector<HTMLInputElement>('#parameters')!;
  readonly prompt=document.querySelector<HTMLTextAreaElement>('#prompt')!;
  readonly fields=document.querySelector<HTMLTextAreaElement>('#fields')!;
  private hasFields=false;
  constructor(){this.parameters.value='count=4; steps=3; aspect=1:1';}
  source():string {return documentSource({header:this.parameters.value,prompt:this.prompt.value,fieldsText:this.fields.value,hasFieldsSection:this.hasFields||!!this.fields.value});}
  load(source:string):void {const d=parseDocument(source);this.parameters.value=d.header;this.prompt.value=d.prompt;this.fields.value=d.fieldsText;this.hasFields=d.hasFieldsSection;}
  onChange(callback:()=>void):void {for(const e of [this.parameters,this.prompt,this.fields])e.addEventListener('input',callback);}
}

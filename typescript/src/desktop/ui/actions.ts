import type {ImageSummary} from '../../core/desktop';
export function imageActions(image:ImageSummary,run:(action:'shortlisted'|'favorite'|'rejected')=>void):HTMLElement{
  const root=document.createElement('div');root.className='toolbar image-actions';
  for(const action of ['shortlisted','favorite','rejected'] as const){
    const button=document.createElement('button');const selected=action==='favorite'?image.favorite:image[action];
    button.textContent=action==='shortlisted'?'📌':action==='favorite'?'⭐':selected?'↩':'🚫';
    button.title=action==='shortlisted'?(selected?'Remove from shortlist':'Add to shortlist'):action==='favorite'?(selected?'Remove from Favorites':'Add to Favorites'):selected?'Restore image':'Reject image';
    button.setAttribute('aria-label',button.title);button.setAttribute('aria-pressed',String(selected));button.dataset.action=action;
    button.disabled=image.status!=='completed'||action!=='favorite'&&!image.inBatch;button.addEventListener('click',event=>{event.stopPropagation();run(action);});root.append(button);
  }
  return root;
}

import {D} from './arithmetic';
import type {DesktopState,ImageSummary} from './desktop';
export type GalleryScope='images'|'shortlist'|'favorites'|'rejected';
export type ImageSort='seeded'|'seeded-step'|'newest';
export function sortedImages(images:readonly ImageSummary[],mode:ImageSort):ImageSummary[]{
  const number=(a:number|null,b:number|null)=>a===null?(b===null?0:1):b===null?-1:a-b;
  const shift=(a:string|null,b:string|null)=>a===null?(b===null?0:1):b===null?-1:new D(a).comparedTo(new D(b));
  return [...images].sort((a,b)=>{
    if(mode==='newest')return b.recency-a.recency||b.number-a.number||a.id.localeCompare(b.id);
    const seed=number(a.seed,b.seed);if(seed)return seed;
    const details=mode==='seeded-step'?number(a.steps,b.steps)||shift(a.shift,b.shift):shift(a.shift,b.shift)||number(a.steps,b.steps);
    return details||a.number-b.number||a.id.localeCompare(b.id);
  });
}
export function galleryImages(state:DesktopState,scope:GalleryScope,sort:ImageSort):ImageSummary[]{
  const images=scope==='favorites'?state.favorites:state.images.filter(image=>image.status!=='cancelled'&&(scope==='shortlist'?image.shortlisted:scope==='rejected'?image.rejected:!image.rejected));
  return sortedImages(images,sort);
}

import { PNG } from 'pngjs';
import { RenderError } from '../core/renderer';
export function validateOutputSize(width:number,height:number):void {
  if(width*height>64*1024*1024)throw new RenderError('Output exceeds the 64-megapixel decode limit.','validation');
}
export function validatePNG(bytes: Uint8Array, width: number, height: number): void {
  try {
    const b = Buffer.from(bytes);
    if (b.length < 33 || !b.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10]))) throw new Error('Missing PNG header.');
    if (b.readUInt32BE(16) !== width || b.readUInt32BE(20) !== height) throw new Error('Output dimensions differ from requested dimensions.');
    if (width * height > 64 * 1024 * 1024) throw new Error('Output exceeds the 64-megapixel decode limit.');
    // Full inflate, chunk/CRC and scanline validation, not just a magic-byte check.
    const image = PNG.sync.read(b, { checkCRC: true });
    if (image.width !== width || image.height !== height || image.data.length !== width * height * 4) throw new Error('Incomplete PNG pixels.');
  } catch (e) { throw new RenderError(`Invalid renderer output: ${String(e)}`, 'render'); }
}

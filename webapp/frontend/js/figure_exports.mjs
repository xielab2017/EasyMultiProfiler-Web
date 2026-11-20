// Physical size is a property of the saved figure, independent of browser zoom.
export const MM_PER_UNIT = Object.freeze({mm: 1, cm: 10, in: 25.4, pt: 25.4 / 72});
// Illustrator / PDF points use exactly 72 pt per inch.
export function convertFigureDimension(value, from, to) {
  if (!Object.hasOwn(MM_PER_UNIT, from) || !Object.hasOwn(MM_PER_UNIT, to) || !Number.isFinite(Number(value))) throw new Error('Invalid figure unit or dimension');
  return Number((Number(value) * MM_PER_UNIT[from] / MM_PER_UNIT[to]).toPrecision(15));
}
export function physicalSize(width, height, unit, dpi = 300) {
  const factor = MM_PER_UNIT[unit];
  const size = {width_mm: Number(width) * factor, height_mm: Number(height) * factor, dpi: Number(dpi)};
  if (![size.width_mm, size.height_mm].every(x => Number.isFinite(x) && x >= 10 && x <= 914.4) ||
      ![72, 150, 300, 600].includes(size.dpi) ||
      Math.ceil(size.width_mm / 25.4 * size.dpi) * Math.ceil(size.height_mm / 25.4 * size.dpi) > 40000000) {
    throw new Error('Choose 10–914.4 mm per side and at most 40 million pixels.');
  }
  return size;
}
export function pngGeometry(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  if (bytes.length < 24 || view.getUint32(0) !== 0x89504e47) throw new Error('Invalid PNG');
  let dpi = 300;
  for (let pos = 8; pos + 12 <= bytes.length;) {
    const length = view.getUint32(pos);
    if (pos + length + 12 > bytes.length) break;
    if (view.getUint32(pos + 4) === 0x70485973 && length === 9 && bytes[pos + 16] === 1) {
      const ppm = view.getUint32(pos + 8);
      if (ppm > 0) dpi = ppm * 0.0254;
      break;
    }
    pos += length + 12;
  }
  return {width: view.getUint32(16), height: view.getUint32(20), dpi};
}
export function jpegWithDpi(bytes, dpi) {
  // Browser-generated JPEGs use JFIF; insert our own header if absent.
  const density = Math.max(1, Math.min(65535, Math.round(dpi)));
  const out = bytes.slice();
  if (out[0] !== 255 || out[1] !== 216) throw new Error('Invalid JPEG');
  for (let i = 2; i + 18 <= out.length && out[i] === 255;) {
    const marker = out[i + 1];
    if (marker === 0xda || marker === 0xd9) break;
    const length = (out[i + 2] << 8) | out[i + 3];
    if (length < 2 || i + 2 + length > out.length) break;
    if (marker === 0xe0 && String.fromCharCode(...out.slice(i+4,i+9)) === 'JFIF\0') {
      out[i+11]=1; out[i+12]=density>>8; out[i+13]=density&255; out[i+14]=density>>8; out[i+15]=density&255;
      return out;
    }
    i += 2 + length;
  }
  const header = Uint8Array.from([255,224,0,16,74,70,73,70,0,1,1,1,density>>8,density&255,density>>8,density&255,0,0]);
  const result = new Uint8Array(out.length + header.length);
  result.set(out.slice(0,2)); result.set(header,2); result.set(out.slice(2),20);
  return result;
}
export function encodeTiff(rgba, width, height, dpi) {
  // Baseline RGB TIFF: a single uncompressed strip and physical-resolution tags.
  if (!Number.isInteger(width) || !Number.isInteger(height) || width < 1 || height < 1 || width * height > 40000000 || rgba.length !== width * height * 4) throw new Error('Invalid TIFF dimensions');
  const count = 12, extra = 8 + 2 + count * 12 + 4, pixels = extra + 6 + 16;
  const bytes = new Uint8Array(pixels + width * height * 3), view = new DataView(bytes.buffer);
  bytes.set([73,73,42,0]); view.setUint32(4,8,true); view.setUint16(8,count,true);
  const entry = (index, tag, type, n, value) => {
    const p=10+index*12; view.setUint16(p,tag,true); view.setUint16(p+2,type,true); view.setUint32(p+4,n,true);
    if(type===3 && n===1) view.setUint16(p+8,value,true); else view.setUint32(p+8,value,true);
  };
  [[256,4,1,width],[257,4,1,height],[258,3,3,extra],[259,3,1,1],[262,3,1,2],[273,4,1,pixels],[277,3,1,3],[278,4,1,height],[279,4,1,width*height*3],[282,5,1,extra+6],[283,5,1,extra+14],[296,3,1,2]].forEach((v,i)=>entry(i,...v));
  for(let i=0;i<3;i++) view.setUint16(extra+i*2,8,true);
  for(const offset of [extra+6,extra+14]) { view.setUint32(offset,Math.round(dpi*1000),true); view.setUint32(offset+4,1000,true); }
  for(let i=0,j=pixels;i<rgba.length;i+=4) {
    const alpha=rgba[i+3]/255;
    for(let k=0;k<3;k++) bytes[j++]=Math.round(rgba[i+k]*alpha+255*(1-alpha));
  }
  return bytes;
}
export function geometryFromSource(source) {
  return pngGeometry(Uint8Array.from(atob(source.split(',')[1]), c => c.charCodeAt(0)));
}
export async function downloadRaster(source, format, filename) {
  const {width,height,dpi}=geometryFromSource(source);
  const image=await new Promise((resolve,reject)=>{const i=new Image();i.onload=()=>resolve(i);i.onerror=reject;i.src=source;});
  const canvas=document.createElement('canvas'); canvas.width=width; canvas.height=height;
  const ctx=canvas.getContext('2d'); ctx.fillStyle='white';ctx.fillRect(0,0,width,height);ctx.drawImage(image,0,0);
  let bytes;
  if(format==='tiff') bytes=encodeTiff(ctx.getImageData(0,0,width,height).data,width,height,dpi);
  else {
    const blob=await new Promise(resolve=>canvas.toBlob(resolve,'image/jpeg',0.95));
    if(!blob) throw new Error('JPEG export failed');
    bytes=jpegWithDpi(new Uint8Array(await blob.arrayBuffer()),dpi);
  }
  const url=URL.createObjectURL(new Blob([bytes],{type:format==='tiff'?'image/tiff':'image/jpeg'}));
  const a=document.createElement('a');a.href=url;a.download=filename;a.click();
  setTimeout(()=>URL.revokeObjectURL(url),60000);
}

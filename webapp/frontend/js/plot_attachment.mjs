// Send only the explicitly selected result image, never the surrounding page.
export function plotImageDimensions(width,height,maxSide=1800){
 if(!Number.isFinite(width)||!Number.isFinite(height)||width<1||height<1)throw Error('图像尚未加载，请等待绘图完成。');
 const scale=Math.min(1,maxSide/Math.max(width,height));return {width:Math.max(1,Math.round(width*scale)),height:Math.max(1,Math.round(height*scale))};
}
export async function attachResultPlot(container,{doc=globalThis.document,upload=globalThis.fetch}={}){
 const images=[...container.querySelectorAll('img')].filter(n=>!n.closest('.ai-copilot')&&!n.closest('.agent-sent-attachment'));
 const img=images.find(n=>n.naturalWidth>100&&n.naturalHeight>100);
 if(!img)return null;
 if(img.decode)await img.decode();
 const size=plotImageDimensions(img.naturalWidth,img.naturalHeight),canvas=doc.createElement('canvas');canvas.width=size.width;canvas.height=size.height;
 const ctx=canvas.getContext('2d');ctx.fillStyle='#ffffff';ctx.fillRect(0,0,size.width,size.height);ctx.drawImage(img,0,0,size.width,size.height);
 const blob=await new Promise(resolve=>canvas.toBlob(resolve,'image/png'));if(!blob||blob.size>5*1024**2)throw Error('当前图像无法转为模型附件，请下载后上传。');
 const response=await upload('/api/public-data/agent/attachments',{method:'POST',headers:{'Content-Type':'image/png','X-Attachment-Name':'current-result-plot.png'},body:blob,credentials:'omit',redirect:'error'});
 const item=await response.json();if(!response.ok)throw Error(item.error||'当前图像读取失败');return {...item,width:size.width,height:size.height};
}

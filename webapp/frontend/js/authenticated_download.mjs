export async function fetchZip(url,headers,transport=fetch){
 const response=await transport(url,{method:'GET',headers,credentials:'omit',redirect:'error'});
 if(!response.ok)throw Error(response.status===401||response.status===403?'下载需要当前会话认证，请刷新主页面后重试。 / Download requires the current authenticated session; reload and retry.':`下载失败 / Download failed: HTTP ${response.status}`);
 const blob=await response.blob(),magic=new Uint8Array(await blob.slice(0,4).arrayBuffer());
 if(magic[0]!==0x50||magic[1]!==0x4b||!((magic[2]===3&&magic[3]===4)||(magic[2]===5&&magic[3]===6)||(magic[2]===7&&magic[3]===8)))throw Error('服务器未返回有效 ZIP 文件。 / The server did not return a valid ZIP file.');
 return blob;
}

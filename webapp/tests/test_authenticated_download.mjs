import test from 'node:test';
import assert from 'node:assert/strict';
import {fetchZip} from '../frontend/js/authenticated_download.mjs';
test('ZIP downloads carry authentication in headers and never follow redirects',async()=>{
 const value=await fetchZip('http://localhost/api/bundles/session/result.zip',{'Authorization':'Bearer synthetic-token','X-Session-Id':'session'},async(url,options)=>{
  assert.ok(!url.includes('synthetic-token'));assert.equal(options.headers.Authorization,'Bearer synthetic-token');assert.equal(options.redirect,'error');assert.equal(options.credentials,'omit');return{ok:true,blob:async()=>new Blob([new Uint8Array([80,75,3,4,0,0])])};
 });assert.equal(value.size,6);
});
test('unauthorized requests and JSON/HTML error responses are not saved as ZIP files',async()=>{
 await assert.rejects(fetchZip('/bundle',{},async()=>({ok:false,status:401})),/认证/);
 await assert.rejects(fetchZip('/bundle',{},async()=>({ok:true,blob:async()=>new Blob(['<html>unauthorized</html>'])})),/ZIP/);
});

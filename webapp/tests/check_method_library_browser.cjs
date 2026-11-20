const {chromium}=require('playwright'),assert=require('node:assert/strict'),fs=require('node:fs');
(async()=>{const [api,site,sid,output]=process.argv.slice(2),browser=await chromium.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true});try{
 const page=await browser.newPage({viewport:{width:1440,height:1100}}),errors=[];page.on('pageerror',e=>errors.push(e.message));
 const origins=new Set([new URL(api).origin,new URL(site).origin]);await page.route('**/*',r=>origins.has(new URL(r.request().url()).origin)?r.continue():r.abort());
 await page.addInitScript(({api,sid})=>{window.API_BASE=api;localStorage.setItem('emp_session_id',sid);localStorage.setItem('emp_ui_locale_mode','zh');},{api,sid});
 await page.goto(site);await page.locator('.nav-item[data-page="visualization"]').click();await page.waitForFunction(()=>window._emp?.currentExp);await page.locator('[data-tab="viz-de-significance"]').click();
 const button=page.locator('#de-significance-generate');await button.waitFor();await page.waitForFunction(()=>!document.getElementById('de-significance-generate').disabled);
 assert.match(await page.locator('#de-significance-status').textContent(),/已连接/);
 await page.locator('#de-significance-transform').selectOption('linear');await page.locator('#de-significance-exclude-na').check();
 const field=key=>page.locator('#figure-de_significance-'+key);async function set(key,v){await field(key).fill(String(v));await field(key).dispatchEvent('change');}
 await set('width',120);await set('height',110);await set('font',10);
 async function generate(){const pending=page.waitForResponse(r=>r.url().endsWith('/visualize/method-library'));await button.click();const res=await pending,data=await res.json();assert.equal(res.status(),200,JSON.stringify(data).slice(0,800));assert.equal(data.success,true);return data;}
 const data=await generate();assert.equal(data.n_rows,39);assert.equal(data.source.excluded_unavailable_p,1);assert.equal(data.figure_layout.canvas.width_mm,120);assert.equal(data.figure_layout.canvas.height_mm,110);assert.equal(data.figure_layout.font_pt,10);
 await page.locator('#de-significance-output img').waitFor();fs.writeFileSync(output+'/de-significance.png',Buffer.from(data.plot,'base64'));
 for(const format of ['pdf','svg','data','manifest']){const res=await page.request.get(new URL(data.download_urls[format],api).href);assert.equal(res.status(),200);fs.writeFileSync(output+'/de-significance.'+({data:'csv',manifest:'json'}[format]||format),await res.body());}
 await set('width',60);await set('height',60);await set('font',4);const small=await generate();assert.equal(small.figure_layout.font_pt,4);assert.equal(small.figure_layout.canvas.width_mm,60);
 await page.reload();await page.locator('.nav-item[data-page="visualization"]').click();await page.locator('[data-tab="viz-de-significance"]').click();await page.waitForFunction(()=>!document.getElementById('de-significance-generate').disabled);
 await page.locator('#de-significance-recheck').click();await page.waitForFunction(()=>!document.getElementById('de-significance-generate').disabled);assert.deepEqual(errors,[]);
 console.log('PASS method library browser: persisted connection without root env, enabled DE render button, 120 x 110 mm / 10 pt, 39 frozen rows + one audited NA exclusion, PDF / SVG / PNG, 60 mm / 4 pt, reload and recheck');
}finally{await browser.close()}})().catch(e=>{console.error(e);process.exitCode=1});

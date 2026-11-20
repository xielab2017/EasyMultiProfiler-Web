const {chromium}=require('playwright'),fs=require('node:fs'),assert=require('node:assert/strict');
(async()=>{const [api,site,sid,folder]=process.argv.slice(2),records=JSON.parse(fs.readFileSync(folder+'/sources.json')),browser=await chromium.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true});try{
 const page=await browser.newPage({viewport:{width:1440,height:1100}}),errors=[],analysis=[];page.on('pageerror',e=>errors.push(e.message));page.on('request',r=>{if(r.method()==='POST'&&(r.url().includes('/tasks/submit')||r.url().includes('/analyze/')))analysis.push(r.url());});
 const origins=new Set([new URL(api).origin,new URL(site).origin]);await page.route('**/*',r=>origins.has(new URL(r.request().url()).origin)?r.continue():r.abort());
 await page.addInitScript(({api,sid})=>{window.API_BASE=api;localStorage.setItem('emp_session_id',sid);localStorage.setItem('emp_ui_locale_mode','zh');},{api,sid});
 await page.goto(site);await page.waitForFunction(()=>window._emp?.currentExp);await page.locator('.nav-item[data-page="analysis"]').click();
 const tabs={dimension:'ana-dim',correlation:'ana-cor',cluster:'ana-cluster',marker:'ana-marker'},methods={dimension:'dim-method',correlation:'cor-method',cluster:'cluster-method',marker:'marker-method'};
 async function render(kind,action){const pending=page.waitForResponse(r=>r.url().endsWith('/visualize/analysis-result'),{timeout:90000});await action();const response=await pending,data=await response.json();assert.equal(response.status(),200,JSON.stringify(data).slice(0,800));assert.equal(data.analysis_recomputed,false);return data;}
 for(const record of records){
  const {kind,method,id}=record;await page.locator('[data-tab="'+tabs[kind]+'"]').click();await page.locator('#'+methods[kind]).selectOption(method);
  const source=page.locator('#analysis-'+kind+'-source');await page.waitForFunction(({kind,id})=>document.getElementById('analysis-'+kind+'-source')?.value==='snapshot:'+id,{kind,id});await page.waitForFunction(kind=>!document.getElementById('analysis-'+kind+'-generate').disabled,kind);
  const before=analysis.length,data=await render(kind,()=>page.locator('#analysis-'+kind+'-generate').click());assert.equal(analysis.length,before);assert.equal(data.source.requested_method,method);assert.equal(data.source.source_id,'snapshot:'+id);
  fs.writeFileSync(folder+'/'+kind+'-'+method+'.png',Buffer.from(data.plot,'base64'));
  if(method==='PCA'||method==='pearson'||method==='hclust'||method==='randomForest')for(const format of ['pdf','svg','data','manifest']){const r=await page.request.get(new URL(data.download_urls[format],api).href);assert.equal(r.status(),200);fs.writeFileSync(folder+'/'+kind+'.'+({data:'csv',manifest:'json'}[format]||format),await r.body());}
 }
 assert.equal(analysis.length,0,'Rendering saved outputs submitted an analysis');
 // Native Run must produce a new background result and automatically draw it.
 await page.locator('[data-tab="ana-dim"]').click();await page.locator('#dim-method').selectOption('PCA');await page.waitForFunction(()=>!document.getElementById('analysis-dimension-generate').disabled);
 const old=await page.locator('#analysis-dimension-source').inputValue();const fresh=await render('dimension',()=>page.locator('#btn-dim').click());assert.notEqual(fresh.source.source_id,old);assert.ok(analysis.length>0);assert.equal(fresh.source.source_job?.length>0,true);
 // Each plot has its own size / type options, independent from other analyses.
 await page.locator('#figure-analysis_dimension-width').fill('90');await page.locator('#figure-analysis_dimension-width').dispatchEvent('change');const resized=await render('dimension',()=>page.locator('#analysis-dimension-generate').click());assert.equal(resized.figure_layout.canvas.width_mm,90);
 assert.equal(await page.locator('#figure-analysis_marker-width').inputValue(),'180');
 await page.locator('#analysis-dimension-output [data-publication-settings]').click();assert.equal(await page.locator('#page-analysis').evaluate(e=>e.classList.contains('active')),true);
 await page.locator('[data-tab="ana-cor"]').click();await page.locator('#cor-method').selectOption('pearson');await page.waitForFunction(()=>!document.getElementById('analysis-correlation-generate').disabled);await page.locator('#analysis-correlation-view').selectOption('network');const network=await render('correlation',()=>page.locator('#analysis-correlation-generate').click());assert.equal(network.source.kind,'correlation');
 await page.locator('[data-tab="ana-cluster"]').click();await page.locator('#cluster-method').selectOption('pam');await page.waitForFunction(()=>!document.getElementById('analysis-cluster-generate').disabled);assert.equal(await page.locator('#analysis-cluster-view option[value="tree"]').isDisabled(),true);await page.locator('#analysis-cluster-view').selectOption('projection');await render('cluster',()=>page.locator('#analysis-cluster-generate').click());
 await page.setViewportSize({width:768,height:1100});assert.ok(await page.locator('#figure-analysis_cluster-width').evaluate(e=>e.getBoundingClientRect().width>0));assert.deepEqual(errors,[]);
 console.log('PASS all 16 method outputs in four analysis tabs; PNG/PDF/SVG and exact source selection; no model rerun for plots; native background Run -> immutable source -> automatic plot; independent sizing, settings navigation, correlation network and PAM projection');
}finally{await browser.close()}})().catch(e=>{console.error(e);process.exitCode=1});

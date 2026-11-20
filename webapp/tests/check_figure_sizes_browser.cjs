// Full browser + real R API acceptance, using synthetic fixtures only.
const {chromium}=require('playwright');
const assert=require('node:assert/strict');
const fs=require('node:fs');
(async()=>{
 const [api,site,sid,output]=process.argv.slice(2);
 const browser=await chromium.launch({executablePath:process.env.EMP_CHROME||'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true});
 try{
  const page=await browser.newPage({viewport:{width:1360,height:1000},acceptDownloads:true});
  const origins=new Set([new URL(api).origin,new URL(site).origin]);
  await page.route('**/*',r=>origins.has(new URL(r.request().url()).origin)?r.continue():r.abort());
  await page.addInitScript(({api,sid})=>{window.API_BASE=api;localStorage.setItem('emp_session_id',sid);localStorage.setItem('emp_ui_locale_mode','zh');localStorage.setItem('emp_last_page','visualization');},{api,sid});
  await page.goto(site,{waitUntil:'domcontentloaded'});
  await page.locator('.nav-item[data-page="visualization"]').click();
  await page.locator('[data-tab="viz-volcano"]').click();
  await page.waitForFunction(()=>window._emp?.currentExp);
  const requests=[];
  page.on('request',r=>{if(r.url().includes('/visualize/')&&r.method()==='POST') requests.push({url:r.url(),body:r.postDataJSON()});});
  async function render(kind,button,out,name){
   const pending=page.waitForResponse(r=>r.url().endsWith('/visualize/'+kind));
   await page.locator(button).click();const res=await pending;const data=await res.json();
   assert.equal(res.status(),200,JSON.stringify(data));assert.equal(data.success,true,data.error);
   await page.locator(out+' img').first().waitFor();
   fs.writeFileSync(output+'/'+name+'.png',Buffer.from(data.plot,'base64'));
   const a=page.locator(out+' a[download$=".pdf"]');
   const pdf=await page.request.get(await a.getAttribute('href'));
   assert.equal(pdf.status(),200);assert.match(pdf.headers()['content-type'],/pdf/);
   fs.writeFileSync(output+'/'+name+'.pdf',await pdf.body());
   return data;
  }
  await page.locator('#vol-width').fill('6');await page.locator('#vol-height').fill('4');
  await render('volcano','#btn-volcano','#volcano-out','volcano-local');
  assert.deepEqual([requests.at(-1).body.width,requests.at(-1).body.height],[6,4]);
  await page.locator('#vol-width').fill('');await page.locator('#btn-volcano').click();assert.equal(requests.length,1);await page.locator('#vol-width').fill('6');
  await page.locator('#viz-export-enabled').check();
  await page.locator('#viz-export-width').fill('180');await page.locator('#viz-export-height').fill('120');
  await page.locator('#viz-export-unit').selectOption('cm');
  assert.equal(await page.locator('#viz-export-width').inputValue(),'18');
  await page.locator('#viz-export-unit').selectOption('in');
  assert.ok(Math.abs(Number(await page.locator('#viz-export-width').inputValue())-180/25.4)<1e-7);
  await page.locator('#viz-export-unit').selectOption('mm');
  await page.locator('#viz-export-width').fill('180');await page.locator('#viz-export-height').fill('120');
  await page.locator('#viz-export-dpi').selectOption('150');await page.locator('#viz-figure-scale').fill('0.75');
  await render('volcano','#btn-volcano','#volcano-out','volcano-unified');
  assert.deepEqual(requests.at(-1).body.export_size,{width_mm:180,height_mm:120,dpi:150});
  assert.match(await page.locator('#volcano-out .figure-export-size').textContent(),/180.0 × 120.0 mm/);
  for(const [selector,ext] of [['#volcano-out-dl-jpg','jpg'],['#volcano-out-dl-tiff','tiff']]) {
   const dl=page.waitForEvent('download');await page.locator(selector).click();await (await dl).saveAs(output+'/volcano-unified.'+ext);
  }
  await page.locator('#viz-export-width').fill('0');await page.locator('#btn-volcano').click();assert.equal(requests.length,2);await page.locator('#viz-export-width').fill('180');
  await page.locator('[data-tab="viz-heatmap"]').click();
  await render('deg_heatmap','#btn-deg-heatmap','#deg-heatmap-out','deg-unified');
  await page.locator('[data-tab="viz-boxplot"]').click();
  await render('boxplot','#btn-boxplot','#boxplot-out','boxplot-unified');
  // The shared canvas is optional. Disabling it restores each plot's own size.
  await page.locator('#viz-export-enabled').uncheck();await page.locator('#viz-figure-scale').fill('1');
  await page.locator('[data-tab="viz-volcano"]').click();
  await render('volcano','#btn-volcano','#volcano-out','volcano-restored');
  assert.equal(requests.at(-1).body.export_size,undefined);
  await page.locator('#viz-export-enabled').check();
  await page.locator('#locale-select').selectOption('en');
  assert.equal(await page.locator('label[for="viz-export-width"]').textContent(),'Canvas width');
  await page.locator('#locale-select').selectOption('zh');
  assert.equal(await page.locator('label[for="viz-export-width"]').textContent(),'画布宽度');
  await page.locator('#viz-export-card').screenshot({path:output+'/figure-canvas-controls.png'});
  await page.setViewportSize({width:390,height:900});await page.locator('#viz-export-width').scrollIntoViewIfNeeded();
  assert.ok(await page.locator('#viz-export-width').evaluate(e=>e.getBoundingClientRect().right<=innerWidth));
  console.log('PASS browser: independent volcano sizes, unit conversion, global canvas override, disabled restore, invalid input blocking, real PDF downloads, JPEG/TIFF downloads, zh/en and mobile');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1});

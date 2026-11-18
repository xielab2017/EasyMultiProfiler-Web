// Run against smoke_count_workbench.py --serve using its synthetic six-sample CSV.
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const {chromium} = require('playwright-core');

async function main() {
  const [address, fixture, evidence] = process.argv.slice(2);
  const endpoint = new URL(address);
  assert(endpoint.hostname === '127.0.0.1' && endpoint.port && !['8000', '8080', '8081'].includes(endpoint.port));
  const browser = await chromium.launch({headless:true, executablePath:process.env.CHROME_BIN});
  try {
    const context = await browser.newContext({viewport:{width:390, height:844}, acceptDownloads:true});
    await context.route('**/*', route => {
      const url = new URL(route.request().url());
      return url.origin === endpoint.origin || ['blob:', 'data:'].includes(url.protocol) ? route.continue() : route.abort();
    });
    // Pin API traffic to the fixture gateway and replace the offline CDN icon renderer.
    await context.addInitScript(() => { window.API_BASE='/api'; window.lucide={createIcons(){}}; });
    const page = await context.newPage();
    await page.goto(address, {waitUntil:'domcontentloaded'});
    await page.locator('.nav-item[data-page=workbench]').click();
    const wb = name => page.locator('#wb-'+name);
    await wb('simple-start').waitFor();
    const toggle = page.locator('#code-lab-guide-collapse');
    assert.equal(await toggle.getAttribute('aria-expanded'), 'false');
    await toggle.click();
    const mobile = await page.evaluate(() => {
      const panel = document.querySelector('#code-lab-root').getBoundingClientRect();
      const workbench = document.querySelector('#page-workbench').getBoundingClientRect();
      return {viewport:innerWidth, pageWidth:workbench.width, pageTop:workbench.top, dockBottom:panel.bottom};
    });
    assert(mobile.pageWidth > 0 && mobile.pageTop >= mobile.dockBottom - 1);
    await toggle.click();
    await wb('upload').setInputFiles(fixture);
    await page.waitForFunction(() => document.querySelectorAll('#wb-samples [data-sample]').length === 6);
    for (const field of await wb('samples').locator('[data-sample]').all()) {
      await field.fill((await field.getAttribute('data-sample'))[0]);
    }
    await wb('evidence').fill('Synthetic unnormalized integer count matrix for software testing.');
    await fs.mkdir(evidence, {recursive:true});
    const runs = [];
    for (const [reference, test] of [['A','B'], ['B','A']]) {
      await wb('reference').fill(reference);
      await wb('test').fill(test);
      await wb('simple-consent').check();
      const [response] = await Promise.all([
        page.waitForResponse(r => r.ok() && /\/jobs\/[^/]+\/result$/.test(new URL(r.url()).pathname), {timeout:120000}),
        wb('simple-start').click(),
      ]);
      const value = await response.json();
      await page.waitForFunction(() => !document.querySelector('#wb-export-de').disabled);
      const de = value.artifacts.differential;
      const summary = await wb('result-summary').textContent();
      assert.equal(de.reference,reference); assert.equal(de.test,test);
      assert.equal(de.tested_features,400); assert.equal(de.alpha,0.05);
      for (const n of [de.tested_features,de.alpha,de.significant_features]) assert(summary.includes(String(n)));
      for (const k of ['simple-consent','group-reviewed','independent','confirm']) assert.equal(await wb(k).isChecked(),false,k);
      assert(await wb('run').isDisabled()); assert(await wb('export-plan').isEnabled());
      assert(!(await page.locator('.emp-jobtray-panel').isVisible()));
      assert(await wb('result-pca').count()); assert(await wb('result-heatmap').count());
      await wb('export-de').scrollIntoViewIfNeeded();
      const [file] = await Promise.all([page.waitForEvent('download'), wb('export-de').click()]);
      const filename = file.suggestedFilename();
      assert(filename.includes(test+'-vs-'+reference));
      await file.saveAs(path.join(evidence,filename));
      const lines = (await fs.readFile(path.join(evidence,filename),'utf8')).trimEnd().split('\n');
      assert.equal(lines.length,de.rows.length+1);
      const fc = lines[0].split('\t').indexOf('log2FoldChange');
      assert.equal(Number(lines[1].split('\t')[fc]),de.rows[0].log2FoldChange);
      runs.push({id:await wb('analysis-job').inputValue(),test,reference,summary,method:de.method,
        tested:de.tested_features,significant:de.significant_features,threshold:de.alpha,
        firstLog2FC:de.rows[0].log2FoldChange,download:filename});
    }
    assert.notEqual(runs[0].id,runs[1].id);
    assert(Math.abs(runs[0].firstLog2FC + runs[1].firstLog2FC)<1e-4);
    await wb('result-summary').scrollIntoViewIfNeeded();
    await page.screenshot({path:path.join(evidence,'mobile-result.png')});
    await fs.writeFile(path.join(evidence,'acceptance.json'),JSON.stringify({mobile,runs},null,2));
    console.log(JSON.stringify({mobile,runs},null,2));
  } finally {
    await browser.close();
  }
}
main().catch(error => {console.error(error); process.exitCode=1;});

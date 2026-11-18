// Invoked by check_platform_extensions_http.py --browser using its isolated fixture.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const {chromium} = require('playwright');

async function verify() {
    const [api, site, sessionId, manifestPath] = process.argv.slice(2);
    const browser = await chromium.launch({
        executablePath: process.env.EMP_TEST_CHROME || undefined,
        headless: true,
    });
    try {
        const page = await browser.newPage({serviceWorkers: 'block'});
        const origins = new Set([new URL(api).origin, new URL(site).origin]);
        const sample = fs.readFileSync(manifestPath);
        const hash = require('node:crypto').createHash('sha256').update(sample).digest('hex');
        const storeEntry = {id:'sample-quality',path:'examples/sample-quality',version:'1.0.0',minimum:'10.0.0',
            title:'Sample quality summary',summary:'Sample statistics',kind:'Analysis',permissions:['assay.read','job.result.write'],sha256:hash};
        let corrupt = false;
        await page.route('**/*', route => {
            const url = new URL(route.request().url());
            if (url.host === 'xielab2017.github.io') {
                const isCatalog = url.pathname.endsWith('/store-index.json');
                return route.fulfill({contentType:'application/json',headers:{'Access-Control-Allow-Origin':'*'},
                    body:isCatalog ? JSON.stringify([storeEntry]) : corrupt ? '{}' : sample});
            }
            if (!origins.has(url.origin) || url.pathname.endsWith('/runtime_auth.local.js')) {
                return route.abort();
            }
            return route.continue();
        });
        await page.addInitScript(({api, sessionId}) => {
            window.API_BASE = api;
            window.EMP_API_TOKEN = 'fixture-B';
            localStorage.setItem('emp_session_id', sessionId);
            localStorage.setItem('emp_sidebar_order_v1',JSON.stringify(['clinical','models','analysis','workbench']));
        }, {api, sessionId});
        await page.goto(site, {waitUntil: 'domcontentloaded'});
        await page.locator('.nav-item[data-page="models"] + .nav-item[data-page="plugins"]').click();
        await page.locator('#page-plugins.active #emp-extension-panel').waitFor();
        await page.locator('#ext-refresh').click();
        await page.locator('#emp-extension-panel > details > summary').click();
        for (const id of ['sample-quality', 'quality-bars']) {
            await page.locator('#ext-example').selectOption(id);
            await page.locator('#ext-install-example').click();
            await page.locator('[data-plugin="' + id + '"]').click();
            await page.waitForFunction(() => !document.querySelector('#ext-refresh').disabled);
        }
        const dock = page.locator('#code-lab-root');
        await dock.waitFor({state:'hidden'});
        const chatManifest = require('node:path').resolve(manifestPath, '../../zotero-style-chat/plugin.json');
        await page.locator('#ext-manifest').setInputFiles(chatManifest);
        const toggleChat = page.locator('[data-plugin="zotero-style-chat"]');
        await toggleChat.click();
        await page.locator('[data-open-chat="zotero-style-chat"]').click();
        await page.locator('#analysis-guide-question').waitFor({state:'visible'});
        await page.locator('[data-settings="zotero-style-chat"]').click();
        await page.locator('#ext-chat-startup').selectOption('collapsed');
        await page.locator('#ext-settings-save').click();
        await page.locator('#ext-settings').waitFor({state:'detached'});
        await page.reload();
        await toggleChat.waitFor();
        await dock.waitFor({state:'visible'});
        assert.equal(await dock.evaluate(n=>n.classList.contains('code-lab--open')), false);
        await toggleChat.click();
        await dock.waitFor({state:'hidden'});
        await page.reload();
        await toggleChat.waitFor();
        await dock.waitFor({state:'hidden'});
        console.log('PASS chat manifest upload, enable, open, startup setting, reload and disable');
        const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
        manifest.id = 'browser-import';
        manifest.name = 'Browser file plugin';
        manifest.definition.metrics = [{
            key: 'mean', expression: {op: 'multiply', left: {stat: 'mean'}, right: {constant: 2}}
        }];
        await page.locator('#ext-manifest').setInputFiles({
            name: 'plugin.json', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(manifest))
        });
        await page.locator('[data-plugin="browser-import"]').click();
        await page.locator('#ext-analysis').selectOption('browser-import');
        await page.locator('#ext-run').click();
        await page.waitForFunction(() => document.querySelectorAll('#ext-output tbody tr').length === 4, null, {timeout: 60000});
        const values = page.locator('#ext-output tbody tr td:nth-child(2)');
        assert.deepEqual(await values.allTextContents(), ['6','0','14','16']);
        await page.locator('#ext-view').selectOption('quality-bars');
        await page.locator('#ext-display').click();
        await page.waitForFunction(() => document.querySelectorAll('#ext-output tbody td div div').length === 4);
        assert.deepEqual(await values.allTextContents(), ['6','0','14','16']);
        await page.locator('[data-settings="quality-bars"]').click();
        await page.locator('#ext-settings-layout').selectOption('table');
        await page.locator('#ext-settings-limit').fill('2');
        await page.locator('#ext-settings-save').click();
        await page.locator('#ext-settings').waitFor({state:'detached'});
        await page.locator('#ext-display').click();
        await page.waitForFunction(() => document.querySelectorAll('#ext-output tbody tr').length === 2);
        assert.equal(await page.locator('#ext-output tbody td div div').count(),0);
        await page.reload();
        await page.locator('#workflow-stepper [data-wf="models"]').click();
        await page.locator('#page-models.active').waitFor();
        await page.locator('#workflow-stepper [data-wf="models"] + [data-wf="plugins"]').click();
        await page.locator('#page-plugins.active #emp-extension-panel').waitFor();
        await page.locator('[data-settings="quality-bars"]').click();
        assert.equal(await page.locator('#ext-settings-limit').inputValue(), '2');
        await page.locator('#ext-settings-reset').click();
        await page.locator('#ext-settings').waitFor({state:'detached'});
        if (process.env.EMP_TEST_SCREENSHOT) {
            await page.locator('#emp-extension-panel').screenshot({path: process.env.EMP_TEST_SCREENSHOT});
        }
        await page.goto(site+'/#plugins/sample-quality',{waitUntil:'domcontentloaded'});
        const card = page.locator('.ext-market-selected');
        await card.getByRole('link',{name:/GitHub/}).waitFor();
        await card.locator('[data-store-remove="sample-quality"]').click();
        const storeInstall = card.locator('[data-store-install="sample-quality"]');
        await storeInstall.waitFor();
        corrupt = true;
        await storeInstall.click();
        await page.waitForFunction(() => /刷新商店/.test(document.querySelector('#ext-status').textContent));
        corrupt = false;
        await storeInstall.click();
        await card.locator('[data-store-remove="sample-quality"]').waitFor();
        await card.locator('[data-settings="sample-quality"]').click();
        assert.ok(await page.locator('#ext-settings input:checked').count() > 0);
        await page.keyboard.press('Escape');
        await page.reload();
        await card.locator('[data-store-remove="sample-quality"]').waitFor();
        console.log('PASS store deep link, per-plugin GitHub link, uninstall, checksum rejection, one-click reinstall, settings and persistence');
        await page.locator('#ext-model-settings').click();
        await page.locator('#page-models.active').waitFor();
        console.log('PASS browser: settings saved and restored, layout and row limit applied, AI model settings opened');
        console.log('PASS browser: installed two examples, uploaded and ran independent plugin, verified four bar values');
    } finally {
        await browser.close();
    }
}

verify().catch(error => { console.error(error); process.exitCode = 1; });

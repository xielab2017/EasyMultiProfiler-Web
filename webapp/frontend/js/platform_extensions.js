import {selectedStoreId, storeCatalog, storeManifest, storeURL} from './plugin_store.js';
import { request, listExperiments } from './api.js?v=2026-07-22-script-fusion-v1';
import { publishChatPanels } from './chat_panel_plugins.mjs';
import { getLocale } from './locale.js?v=nav-language-20261108';
const root = document.getElementById('emp-extension-panel');
const tr = (zh, en) => ['zh', 'zh-TW'].includes(getLocale()) ? zh : en;
function el(tag, id) {
    const node = document.createElement(tag);
    if (id) node.id = id;
    return node;
}
function btn(id, variant = 'outline') {
    const node = el('button', id);
    node.type = 'button';
    node.className = 'btn btn-' + variant;
    return node;
}
const opt = (value, text) => new Option(text, value);
const api = (method, path, body) => request(method, '/extensions' + path, body || null, false, { skipSessionHeader: true });
const sampleMetricLabels = {
    observed: ['观测数', 'Observed values'],
    missing: ['缺失数', 'Missing values'],
    mean: ['均值', 'Mean'],
    sd: ['标准差', 'Standard deviation'],
    cv: ['变异系数', 'Coefficient of variation']
};
function mount() {
    const title = el('h2'), catalogBtn = btn('ext-refresh'), source = el('select', 'ext-example'), install = btn('ext-install-example');
    title.id = 'ext-title';
    root.setAttribute('aria-labelledby', title.id);
    const modelSettings = btn('ext-model-settings');
    modelSettings.onclick = () => document.querySelector('.nav-item[data-page="models"]').click();
    const file = el('input', 'ext-manifest');
    file.type = 'file';
    file.accept = '.json,application/json';
    const chooseFile = el('label'), fileText = el('span');
    chooseFile.append(fileText, file);
    const available = el('div', 'ext-installed'), status = el('p', 'ext-status');
    status.setAttribute('role', 'status');
    const experiment = el('select', 'ext-experiment'), method = el('select', 'ext-analysis'), run = btn('ext-run');
    const jobs = el('select', 'ext-job'), viewer = el('select', 'ext-view'), show = btn('ext-display'), output = el('div', 'ext-output');
    const heading = (node, zh, en) => () => node.textContent = tr(zh, en);
    const labels = [];
    function field(node, zh, en) {
        const label = el('label'), text = el('span');
        label.className = 'ext-field';
        labels.push(heading(text, zh, en));
        label.append(text, node);
        return label;
    }
    function line(...controls) {
        const row = el('div');
        row.className = 'ext-actions';
        row.append(...controls);
        return row;
    }
    const directory = el('a');
    directory.href = storeURL;
    directory.target = '_blank';
    directory.rel = 'noopener noreferrer';
    labels.push(heading(directory,'浏览插件商店','Browse plugin store'));
    const market = el('section','ext-market'), marketTitle = el('h3'), cards = el('div','ext-market-cards');
    const marketStatus = el('p', 'ext-market-status'), advanced = el('details'), advancedTitle = el('summary');
    const header = el('header'), workbench = el('div', 'ext-workbench');
    header.className = 'ext-header';
    advanced.className = 'ext-local-install';
    marketTitle.id = 'ext-market-title';
    market.setAttribute('aria-labelledby', marketTitle.id);
    labels.push(heading(marketTitle,'在线插件商店','Online plugin store'),
        heading(advancedTitle,'从文件或内置示例安装','Install from a file or bundled example'));
    marketStatus.setAttribute('role','status');
    header.append(title, line(modelSettings, directory, catalogBtn));
    market.append(marketTitle,marketStatus,cards);
    advanced.append(advancedTitle,line(field(source, '示例插件', 'Example plugin'), install, chooseFile));
    function workflowSection(zh, en, ...controls) {
        const section = el('section'), headingNode = el('h3');
        labels.push(heading(headingNode, zh, en));
        section.append(headingNode, line(...controls));
        return section;
    }
    workbench.append(
        workflowSection('插件分析', 'Plugin analysis', field(experiment, '实验与主 assay', 'Experiment and primary assay'),
            field(method, '分析插件', 'Analysis plugin'), run),
        workflowSection('结果展示', 'Result display', field(jobs, '插件结果', 'Plugin result'),
            field(viewer, '展示插件', 'Result view'), show)
    );
    root.append(
        header, status, market, available, advanced, workbench, output
    );
    let catalog = null, experiments = [], history = [], busy = false, epoch = 0, loadedSession = null;
    let entries = null, providers = [], marketPending = false, loadError = false;
    const providerPath = '/api/public-data/agent/plugins';
    async function reloadMarket() {
        if (marketPending) return;
        marketPending = true; loadError = false; renderMarket();
        try {
            const [index, models] = await Promise.all([storeCatalog().catch(() => null),
                fetch(providerPath,{credentials:'same-origin'}).then(r => r.ok ? r.json() : {}).catch(() => ({}))]);
            if (index) entries = index;
            else loadError = true;
            providers = models.plugins || [];
        } catch {
            loadError = true;
        } finally {
            marketPending = false; render();
        }
    }
    function removeButton(plugin, provider) {
        const button = btn();
        button.classList.add('ext-button-danger');
        button.dataset.storeRemove = plugin.id;
        button.disabled = busy;
        button.textContent = tr('卸载','Uninstall');
        button.onclick = () => act(async () => {
            if (provider) {
                const response = await fetch(providerPath+'/uninstall', {method:'POST',headers:{'Content-Type':'application/json'},
                    body:JSON.stringify({id:plugin.id,version:plugin.version})});
                const result = await response.json();
                if (!response.ok || !result.uninstalled) throw Error(result.error || 'Uninstall failed');
                providers = providers.filter(p => p.id !== plugin.id);
                window.dispatchEvent(new CustomEvent('emp:model-store-removed',{detail:result}));
            } else {
                await api('POST','/uninstall',{id:plugin.id,sha256:plugin.sha256});
                await refresh();
            }
            status.textContent = plugin.name + ' · ' + tr('已卸载','Uninstalled');
        });
        return button;
    }
    function showProviderSettings(provider) {
        modelSettings.click();
        const select = document.getElementById('code-lab-llm-provider');
        if (select) {
            select.value = provider;
            select.dispatchEvent(new Event('change',{bubbles:true}));
        }
    }
    function pluginDefinition(plugin, permissions = plugin.permissions) {
        const details = el('details'), summary = el('summary'), access = el('p');
        summary.textContent = plugin.definition ? tr('查看插件定义', 'Inspect plugin definition') : tr('访问权限', 'Access');
        access.textContent = tr('权限','Access') + ' · ' + permissions.join(', ');
        details.append(summary, access);
        if (plugin.definition) {
            const definition = el('pre');
            definition.textContent = JSON.stringify({ id: plugin.id, abi: plugin.abi, definition: plugin.definition }, null, 2);
            details.append(definition);
        }
        return details;
    }
    function installedControls(m) {
        const toggle = btn(), settings = btn();
        toggle.dataset.plugin = m.id;
        toggle.disabled = busy;
        toggle.textContent = m.enabled ? tr('停用', 'Disable') : tr('启用', 'Enable');
        toggle.onclick = () => act(async () => {
            await api('POST', '/enable', { id: m.id, sha256: m.sha256, enabled: !m.enabled });
            await refresh();
        });
        settings.dataset.settings = m.id;
        settings.textContent = tr('设置','Settings');
        settings.disabled = busy || !m.settings;
        settings.onclick = () => editSettings(m);
        const controls = [settings, toggle];
        if (m.abi === 'emp.chat-ui.v1' && m.enabled) {
            const open = btn(undefined, 'primary');
            open.dataset.openChat = m.id;
            open.textContent = tr('打开聊天','Open chat');
            open.onclick = () => window.dispatchEvent(new CustomEvent('emp:open-code-lab',{detail:{page:'plugins'}}));
            controls.unshift(open);
        }
        return controls;
    }
    function renderMarket() {
        cards.setAttribute('aria-busy', String(marketPending));
        catalogBtn.disabled = busy;
        marketStatus.textContent = loadError ? tr('未能连接 GitHub 商店，可重试或从文件安装。','GitHub store unavailable. Retry or install from a file.') :
            marketPending ? tr('正在读取 GitHub 插件目录…','Loading GitHub plugin catalog…') : '';
        const selected = selectedStoreId();
        cards.replaceChildren();
        for (const entry of [...(entries || [])].sort((a,b) => Number(b.id === selected)-Number(a.id === selected))) {
            const lang = ['zh','zh-TW'].includes(getLocale()) ? 'zh' : 'en';
            const copy = lang === 'en' && entry.en ? entry.en : entry;
            const provider = entry.path.startsWith('ai-providers/');
            const existing = provider ? providers.find(p => p.id === entry.id) : catalog?.installed.find(p => p.id === entry.id);
            const newer = existing && entry.version.localeCompare(existing.version,'en',{numeric:true}) > 0;
            const card = el('article'), name = el('h4'), description = el('p'), facts = el('small');
            const badge = el('span'), action = btn(undefined, existing ? 'outline' : 'primary'), details = el('a');
            card.className = 'ext-market-card';
            if (entry.id === selected) card.classList.add('ext-market-selected');
            name.textContent = copy.title;
            description.textContent = copy.summary;
            facts.textContent = copy.kind + ' · v' + (existing?.version || entry.version);
            if (existing) {
                badge.className = 'ext-badge';
                badge.dataset.inactive = String(!provider && !existing.enabled);
                badge.textContent = provider ? tr('已安装','Installed') :
                    existing.enabled ? tr('已启用','Enabled') : tr('已停用','Disabled');
            }
            details.href = 'https://github.com/xielab2017/EasyMultiProfiler-Web-Plugins/tree/main/'+entry.path + (lang === 'en' && entry.en ? '/README.en.md' : '');
            if (lang === 'en' && entry.en) details.href = details.href.replace('/tree/main/','/blob/main/');
            details.target = '_blank'; details.rel = 'noopener noreferrer'; details.textContent = tr('GitHub 介绍','GitHub details');
            action.dataset.storeInstall = entry.id;
            const active = existing && (provider || existing.enabled);
            action.textContent = provider && existing ? tr('设置','Settings') :
                newer ? tr('更新并启用','Update and enable') : active ? tr('已启用','Enabled') :
                existing ? tr('启用','Enable') : provider ? tr('安装','Install') : tr('安装并启用','Install and enable');
            action.disabled = busy || !catalog || (!provider && active && !newer);
            action.onclick = () => act(async () => {
                if (provider && existing) {
                    showProviderSettings(existing.provider);
                    return;
                }
                if (provider) {
                    const manifest = await storeManifest(entry);
                    const response = await fetch(providerPath+'/install', {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(manifest)});
                    const result = await response.json();
                    if (!response.ok || !result.installed) throw Error(result.error || 'Model plugin installation failed');
                    providers.push({...manifest,provider:result.provider});
                    window.dispatchEvent(new CustomEvent('emp:model-store-installed'));
                } else {
                    let sha256 = existing?.sha256;
                    if (!existing || newer) {
                        const manifest = await storeManifest(entry);
                        ({sha256} = await api('POST','/install',{manifest}));
                    }
                    await api('POST','/enable',{id:entry.id,sha256,enabled:true});
                    await refresh();
                }
                status.textContent = copy.title + ' · ' + tr('安装完成','Installation complete');
            });
            const compatible = (document.querySelector('.version-badge')?.textContent || '').replace(/^v/,'')
                .localeCompare(entry.minimum,'en',{numeric:true}) >= 0;
            const buttons = line();
            buttons.classList.add('ext-card-actions');
            if (provider || !existing || newer) {
                if (!compatible) {
                    action.disabled = true;
                    action.textContent = tr('需要 EMP ','Requires EMP ') + entry.minimum + '+';
                }
                buttons.append(action);
            }
            if (existing && !provider) buttons.append(...installedControls(existing));
            const footer = line(pluginDefinition(existing || entry, entry.permissions), details);
            footer.classList.add('ext-card-links');
            if (existing) footer.append(removeButton(existing, provider));
            if (copy.preview_alt) {
                const preview = el('img'), previewLink = el('a');
                preview.loading = 'lazy';
                preview.alt = copy.preview_alt;
                preview.src = new URL('assets/previews/'+entry.id+'-'+lang+'.svg',storeURL).href;
                preview.referrerPolicy = 'no-referrer';
                previewLink.href = new URL((lang === 'en' ? 'en/' : '')+entry.path+'/',storeURL).href;
                previewLink.target = '_blank'; previewLink.rel = 'noopener noreferrer';
                previewLink.className = 'ext-preview';
                previewLink.append(preview); card.append(previewLink);
            }
            const meta = line(facts);
            meta.classList.add('ext-card-meta');
            if (existing) meta.append(badge);
            card.append(meta,name,description,buttons,footer); cards.append(card);
        }
        if (selected && entries && !entries.some(e => e.id === selected)) marketStatus.textContent = tr('商店中没有此插件。','This plugin is unavailable.');
    }
    window.addEventListener('hashchange', renderMarket);
    function editSettings(plugin) {
        const dialog = el('dialog', 'ext-settings'), form = el('form'), heading = el('h3','ext-settings-title');
        const settingsHeader = el('header'), caption = el('p');
        caption.textContent = tr('插件设置','Plugin settings');
        const entry = entries?.find(item => item.id === plugin.id);
        heading.textContent = tr(entry?.title, entry?.en?.title) || plugin.name;
        dialog.setAttribute('aria-labelledby', heading.id);
        settingsHeader.append(caption, heading);
        form.append(settingsHeader);
        const fieldset = el('fieldset'), legend = el('legend'), error = el('p');
        fieldset.append(legend);
        error.setAttribute('role','alert');
        let read;
        if (plugin.abi === 'emp.analysis.v1') {
            legend.textContent = tr('要计算的指标','Metrics to compute');
            const options = el('div');
            options.className = 'ext-metric-options';
            for (const metric of plugin.definition.metrics) {
                const check = el('input'), label = el('label');
                check.type = 'checkbox';
                check.value = metric.key;
                check.checked = plugin.settings.metrics.includes(metric.key);
                const labelText = plugin.id === 'sample-quality' && Object.hasOwn(sampleMetricLabels, metric.key)
                    ? tr(...sampleMetricLabels[metric.key])
                    : metric.key;
                label.append(check, document.createTextNode(labelText));
                options.append(label);
            }
            fieldset.append(options);
            read = () => ({metrics:Array.from(fieldset.querySelectorAll('input:checked'), check => check.value)});
        } else if (plugin.abi === 'emp.chat-ui.v1') {
            legend.textContent = tr('打开网页时的聊天窗口','Chat panel on page load');
            const startup = el('select','ext-chat-startup');
            startup.setAttribute('aria-label', legend.textContent);
            startup.append(opt('adaptive',tr('随屏幕大小','Adapt to screen size')), opt('expanded',tr('展开','Expanded')), opt('collapsed',tr('收起','Collapsed')));
            startup.value = plugin.settings.startup;
            fieldset.append(startup);
            read = () => ({startup:startup.value});
        } else {
            legend.textContent = tr('结果展示','Result display');
            const layout = el('select','ext-settings-layout'), limit = el('input','ext-settings-limit');
            layout.append(opt('table',tr('表格','Table')), opt('bars',tr('条形图','Bars')));
            layout.value = plugin.settings.layout;
            limit.type = 'number'; limit.min = '1'; limit.max = '200'; limit.required = true;
            limit.value = plugin.settings.limit;
            const layoutLabel = el('label'), limitLabel = el('label');
            layoutLabel.className = limitLabel.className = 'ext-field';
            const layoutText = el('span'), limitText = el('span');
            layoutText.textContent = tr('显示方式','Layout');
            limitText.textContent = tr('最多显示行数','Maximum rows');
            layoutLabel.append(layoutText,layout);
            limitLabel.append(limitText,limit);
            fieldset.append(layoutLabel,limitLabel);
            read = () => ({layout:layout.value, limit:limit.valueAsNumber});
        }
        const save = btn('ext-settings-save', 'primary'), reset = btn('ext-settings-reset'), cancel = btn();
        save.type = 'submit'; save.textContent = tr('保存','Save');
        reset.textContent = tr('恢复默认设置','Restore defaults');
        cancel.textContent = tr('取消','Cancel');
        async function commit(settings) {
            save.disabled = reset.disabled = cancel.disabled = true;
            try {
                const saved = await api('POST','/settings',{id:plugin.id,sha256:plugin.sha256,settings});
                plugin.settings = saved.settings;
                publishChatPanels(catalog.installed);
                dialog.close();
                status.textContent = plugin.name + ' · ' + tr('设置已保存','Settings saved');
            } catch (e) {
                error.textContent = e.message;
            } finally {
                save.disabled = reset.disabled = cancel.disabled = false;
            }
        }
        form.onsubmit = event => {
            event.preventDefault();
            const settings = read();
            if (settings.metrics?.length === 0) {
                error.textContent = tr('请至少选择一项指标。','Select at least one metric.');
                return;
            }
            commit(settings);
        };
        reset.onclick = () => commit(null);
        cancel.onclick = () => dialog.close();
        dialog.oncancel = event => { if (save.disabled) event.preventDefault(); };
        const dialogActions = line(reset,cancel,save);
        dialogActions.classList.add('ext-settings-actions');
        form.append(fieldset,error,dialogActions);
        dialog.append(form); root.append(dialog);
        dialog.onclose = () => dialog.remove();
        dialog.showModal();
    }
    const sid = () => localStorage.getItem('emp_session_id');
    function fill(node, options, empty) {
        const old = node.value;
        node.replaceChildren(...options);
        if (!options.length)
            node.append(opt('', empty));
        else if ([...node.options].some(o => o.value === old))
            node.value = old;
    }
    function render() {
        renderMarket();
        directory.href = new URL(tr('index.html','en/index.html'),storeURL).href;
        modelSettings.textContent = tr('AI 模型插件设置','AI model plugin settings');
        for (const fn of labels)
            fn();
        title.textContent = tr('插件管理', 'Plugin manager');
        catalogBtn.textContent = tr('刷新插件', 'Refresh plugins');
        install.textContent = tr('安装示例', 'Install example');
        fileText.textContent = tr('安装 plugin.json', 'Install plugin.json');
        run.textContent = tr('运行分析', 'Run analysis');
        show.textContent = tr('展示结果', 'Show result');
        if (!catalog) {
            install.disabled = file.disabled = run.disabled = show.disabled = true;
            return;
        }
        const installed = catalog.installed || [], examples = (catalog.examples || []).filter(m => !installed.some(x => x.id === m.id));
        fill(source, examples.map(m => opt(m.id, m.name)), tr('示例均已安装', 'All examples installed'));
        available.replaceChildren();
        for (const m of installed) {
            if (entries?.some(e => e.id === m.id && !e.path.startsWith('ai-providers/'))) continue;
            const row = line(), text = el('span');
            text.textContent = m.name + ' · ' + m.version;
            row.append(text, ...installedControls(m), removeButton(m, false), pluginDefinition(m));
            available.append(row);
        }
        for (const provider of providers) {
            if (entries?.some(e => e.path === 'ai-providers/'+provider.id)) continue;
            const name = el('span'), settings = btn();
            name.textContent = provider.name + ' · ' + provider.version;
            settings.textContent = tr('设置','Settings');
            settings.onclick = () => showProviderSettings(provider.provider);
            available.append(line(name,settings,removeButton(provider,true)));
        }
        for (const invalid of catalog.invalid || []) {
            const row = el('p');
            row.textContent = invalid.id + ' · ' + invalid.reason;
            available.append(row);
        }
        fill(experiment, experiments.map(e => opt(e.name, e.name + ' · ' + e.assay)), tr('先在导入页添加实验矩阵', 'Import an experiment matrix first'));
        fill(method, installed.filter(m => m.enabled && m.abi === 'emp.analysis.v1').map(m => opt(m.id, m.name)), tr('先启用分析插件', 'Enable an analysis plugin'));
        fill(viewer, installed.filter(m => m.enabled && m.abi === 'emp.view.v1').map(m => opt(m.id, m.name)), tr('先启用展示插件', 'Enable a result view'));
        fill(jobs, history.map(j => opt(j.id, j.id + ' · ' + j.status)), tr('尚无插件结果', 'No plugin results'));
        file.disabled = busy;
        install.disabled = busy || !source.value;
        run.disabled = busy || !method.value || !experiment.value;
        show.disabled = busy || !viewer.value || !jobs.value;
    }
    async function act(fn) {
        if (busy)
            return;
        busy = true;
        status.textContent = '';
        render();
        try {
            await fn();
        }
        catch (error) {
            status.textContent = error.message;
        }
        finally {
            busy = false;
            render();
        }
    }
    async function refresh() {
        const generation = ++epoch, session = sid();
        if (loadedSession !== session) {
            experiments = [];
            history = [];
            output.replaceChildren();
            render();
        }
        const next = await api('GET', '');
        if (generation !== epoch)
            return;
        catalog = next;
        publishChatPanels(next.installed);
        render();
        const data = session ? await Promise.all([listExperiments(), api('GET', '/jobs/' + encodeURIComponent(session))]) : [[], { jobs: [] }];
        if (generation !== epoch || session !== sid())
            return;
        experiments = data[0];
        history = data[1].jobs;
        loadedSession = session;
        render();
    }
    install.onclick = () => act(async () => {
        await api('POST', '/install', { example_id: source.value });
        await refresh();
    });
    file.onchange = () => act(async () => {
        const f = file.files[0];
        file.value = '';
        if (!f)
            return;
        if (f.size > 32768)
            throw Error(tr('清单上限 32 KiB', 'Manifest limit is 32 KiB'));
        await api('POST', '/install', { manifest: JSON.parse(await f.text()) });
        await refresh();
    });
    catalogBtn.onclick = () => {
        act(refresh);
        reloadMarket();
    };
    run.onclick = () => act(async () => {
        const m = catalog.installed.find(x => x.id === method.value), e = experiments.find(x => x.name === experiment.value);
        const session = sid(), receipt = await api('POST', '/run', { id: m.id, sha256: m.sha256, session_id: session, experiment: e.name, assay: e.assay });
        for (let n = 0; n < 120; n++) {
            if (session !== sid())
                return;
            const { job } = await request('GET', '/jobs/' + encodeURIComponent(receipt.job_id), null, false, { skipSessionHeader: true });
            status.textContent = receipt.job_id + ' · ' + job.status;
            if (['done', 'error', 'cancelled'].includes(job.status)) {
                await refresh();
                jobs.value = receipt.job_id;
                if (job.status !== 'done')
                    throw Error(job.error || job.message || job.status);
                const result = await request('GET', '/jobs/' + encodeURIComponent(receipt.job_id) + '/result', null, false, { skipSessionHeader: true });
                draw(result.rows.slice(0, 30), result.columns);
                return;
            }
            await new Promise(resolve => setTimeout(resolve, 750));
        }
        await refresh();
        status.textContent = tr('任务仍在后台运行，可刷新查看。', 'Job continues in background; refresh to check.');
    });
    function draw(rows, columns, metric = null) {
        const table = el('table');
        table.className = 'data-table';
        const header = table.createTHead().insertRow();
        for (const key of columns) {
            const cell = el('th');
            cell.textContent = key;
            header.append(cell);
        }
        const body = table.createTBody(), values = metric ? rows.map(r => r[metric]).filter(Number.isFinite) : [];
        const min = Math.min(0, ...values), max = Math.max(0, ...values), range = max - min || 1;
        for (const row of rows) {
            const tr = body.insertRow();
            for (const key of columns) {
                const td = tr.insertCell(), v = row[key];
                td.textContent = v == null ? '—' : String(v);
                if (key === metric && Number.isFinite(v)) {
                    const track = el('div'), bar = el('div');
                    track.style.cssText = 'position:relative;width:9em;height:.5em;background:#e2e8f0';
                    bar.style.cssText = 'position:absolute;height:100%;background:' + (v < 0 ? '#aa4a36' : '#32719a');
                    bar.style.left = ((Math.min(v, 0) - min) / range * 100) + '%';
                    bar.style.width = (Math.abs(v) / range * 100) + '%';
                    track.append(bar);
                    td.append(track);
                }
            }
        }
        output.replaceChildren(table);
    }
    show.onclick = () => act(async () => {
        const m = catalog.installed.find(x => x.id === viewer.value);
        const data = await api('POST', '/display', { id: m.id, sha256: m.sha256, session_id: sid(), job_id: jobs.value });
        draw(data.rows, ['item', data.metric], data.layout === 'bars' ? data.metric : null);
        status.textContent = data.job_id + ' · ' + data.rows.length + ' / ' + data.total;
    });
    window.addEventListener('emp:locale-change', render);
    window.addEventListener('emp:experiment-change', () => {
        if (root.closest('.page.active')) act(refresh);
    });
    async function syncChatGrant() {
        const generation = epoch;
        try {
            const latest = await api('GET', '');
            if (generation === epoch) publishChatPanels(latest.installed);
        } catch {
            if (generation === epoch) publishChatPanels([]);
        }
    }
    syncChatGrant();
    document.addEventListener('visibilitychange', () => {
        if (document.visibilityState !== 'visible') return;
        if (root.closest('.page.active')) act(refresh);
        else syncChatGrant();
    });
    new IntersectionObserver(entries => {
        if (!entries.some(e => e.isIntersecting)) return;
        if (!catalog || loadedSession !== sid()) act(refresh);
        if (!cards.children.length && !loadError) reloadMarket();
    }).observe(root);
    render();
}
if (root)
    mount();

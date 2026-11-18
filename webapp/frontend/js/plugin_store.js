// Only the public catalog and manifest are fetched from GitHub. Installation goes to this EMP instance.
export const storeURL = 'https://xielab2017.github.io/EasyMultiProfiler-Web-Plugins/';
const safePath = /^(examples|ai-providers)\/([a-z][a-z0-9_-]{0,47})$/;

async function readStore(path, maxBytes) {
    const response = await fetch(new URL(path, storeURL), {
        credentials:'omit', cache:'no-store', redirect:'error', referrerPolicy:'no-referrer', signal:AbortSignal.timeout(12000),
    });
    if (!response.ok) throw Error('GitHub HTTP ' + response.status);
    const data = await response.arrayBuffer();
    if (data.byteLength > maxBytes) throw Error('Plugin file exceeds the size limit');
    return data;
}

export async function storeCatalog() {
    const entries = JSON.parse(new TextDecoder().decode(await readStore('store-index.json?format=2', 262144)));
    if (!Array.isArray(entries) || entries.some(entry => !safePath.test(entry.path) ||
        entry.path.split('/')[1] !== entry.id || !/^[a-f0-9]{64}$/.test(entry.sha256) ||
        !Array.isArray(entry.permissions))) throw Error('Invalid plugin catalog');
    return entries;
}

export async function storeManifest(entry) {
    if (!safePath.test(entry.path)) throw Error('Invalid plugin path');
    const bytes = await readStore(entry.path+'/plugin.json?v='+entry.sha256, 32768);
    const digest = await crypto.subtle.digest('SHA-256', bytes);
    const hex = Array.from(new Uint8Array(digest), n => n.toString(16).padStart(2, '0')).join('');
    if (hex !== entry.sha256) throw Error('插件已更新，请刷新商店后再安装。');
    const manifest = JSON.parse(new TextDecoder().decode(bytes));
    if (manifest.id !== entry.id || manifest.version !== entry.version) throw Error('Plugin identity mismatch');
    return manifest;
}
export const selectedStoreId = () => /^#plugins\/([a-z][a-z0-9_-]{0,47})$/.exec(location.hash)?.[1];

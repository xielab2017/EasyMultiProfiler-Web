import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
const source = readFileSync(new URL('../frontend/js/api.js', import.meta.url), 'utf8');
const resolver = source.slice(source.indexOf('function resolveApiBase()'), source.indexOf('function resolveApiCandidates()'));
const apiBase = () => vm.runInNewContext(`${resolver}; resolveApiBase()`, {window:globalThis.window});
globalThis.window = {location:{hostname:'localhost',port:'18888'}, EMP_RUNTIME_PORTS:{api:18800,web:18888}};
assert.equal(apiBase(),'http://localhost:18800/api');
window.location.port='8090'; assert.equal(apiBase(),'/api');
window.location.port='18888'; window.EMP_RUNTIME_PORTS.api='18800'; assert.equal(apiBase(),'/api');
window.EMP_RUNTIME_PORTS.api=70000; assert.equal(apiBase(),'/api');
window.API_BASE='/explicit'; assert.equal(apiBase(),'/explicit');
delete window.API_BASE; delete window.EMP_RUNTIME_PORTS; window.location.port='8080'; assert.equal(apiBase(),'http://localhost:8000/api');
console.log('runtime port discovery assertions passed');

const html = readFileSync(new URL('../frontend/index.html', import.meta.url), 'utf8');
assert.ok(!/window\.API_BASE\s*=/.test(html),'HTML bootstrap must not override configured API ports');
window.location.port='8080';window.EMP_RUNTIME_PORTS={api:8003,web:8080};assert.equal(apiBase(),'http://localhost:8003/api');

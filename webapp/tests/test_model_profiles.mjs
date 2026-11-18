import test from 'node:test';
import assert from 'node:assert/strict';
import {connectionBody,namedProfiles,profileChoices,saveNamedProfile,removeNamedProfile} from '../frontend/js/model_profiles.mjs';

test('edit and remove named connections independently, only send selected fields',()=>{
  const map=new Map(),storage={getItem:k=>map.get(k),setItem:(k,v)=>map.set(k,v)};
  const a={name:'Local',provider:'custom',model:'test',base_url:'http://localhost:11434/v1',id:'profile-a'};
  const b={...a,id:'profile-b',base_url:'https://test.example/v1',name:'Team',api_key:'second-key'};
  saveNamedProfile(a,storage);saveNamedProfile(b,storage);saveNamedProfile({...a,temperature:0},storage);
  const rows=namedProfiles(storage);assert.equal(rows.length,2);
  const options=profileChoices([],rows,{profile_id:b.id},()=>true);
  assert.equal(JSON.parse(options.at(-1).id)[2],b.id);assert.ok(!JSON.stringify(options).includes('second-key'));
  const payload=connectionBody({provider:a.provider,config:{...rows.find(x=>x.id===a.id),profiles:rows,max_tokens_output:200}});
  assert.equal(payload.temperature,0);assert.equal(payload.max_tokens_output,200);assert.equal(payload.api_key,'');assert.ok(!JSON.stringify(payload).includes('second-key'));
  removeNamedProfile(b.id,storage);assert.deepEqual(namedProfiles(storage).map(x=>x.id),[a.id]);
});
test('MiniMax preserves region and protocol and omits unspecified sampling fields',()=>{
  const c=connectionBody({provider:'minimax',config:{region:'international',protocol:'anthropic',model:'MiniMax-M3.1'}});
  assert.equal(c.protocol,'anthropic');assert.equal(c.region,'international');assert.ok(!Object.hasOwn(c,'temperature'));
});

import {zoteroProfileGroups, importedProfiles} from '../frontend/js/zotero_profiles.mjs';
test('Zotero model groups preserve row protocol, per-model caps, local endpoints and explicit secret opt-in',()=>{
  const groups=[{id:'m',authMode:'api_key',apiBase:'https://api.minimax.cn/anthropic',apiKey:'fixture',
    providerProtocol:'responses_api',models:[{id:'a',model:'MiniMax-M3.1',providerProtocol:'anthropic_messages',
    temperature:0.7,outputTokenLimit:{mode:'custom',tokens:1500}}, {id:'b',model:'ignored'}]},
    {id:'l',authMode:'api_key',apiBase:'http://localhost:11434/v1',providerProtocol:'openai_chat_compat',
      models:[{id:'b',model:'qwen:8b',temperature:0,outputTokenLimit:{mode:'auto'}}]},
    {id:'w',authMode:'webchat',models:[{model:'gpt'}]}];
  for(const wrapped of [groups,{modelProviderGroups:JSON.stringify(groups)},
      {'extensions.zotero.llmforzotero.modelProviderGroups':groups}])assert.deepEqual(zoteroProfileGroups(wrapped),groups);
  const {profiles,messages}=importedProfiles(groups,false);
  assert.equal(profiles.length,2);assert.equal(profiles[0].max_tokens_output,1500);
  assert.equal(profiles[0].region,'china');assert.equal(profiles[0].protocol,'anthropic');
  assert.ok(!Object.hasOwn(profiles[0],'temperature'));assert.equal(profiles[1].temperature,0);
  assert.ok(messages.some(x=>x.includes('responses_api')));assert.ok(messages.some(x=>x.includes('webchat')));
  assert.ok(!JSON.stringify({profiles,messages}).includes('fixture'));
  assert.equal(importedProfiles(groups,true).profiles[0].api_key,'fixture');
  assert.equal(importedProfiles(groups,false,profiles).profiles.length,0);
});
test('Zotero bare and explicitly suffixed endpoints preserve the effective chat URL',()=>{
  for(const [base,expected,provider] of [
    ['https://llm.example/gateway','https://llm.example/gateway/v1','custom'],
    ['https://llm.example/api/v2/responses','https://llm.example/api/v2','custom'],
    ['https://api.openai.com/v1/chat/completions','https://api.openai.com/v1','chatgpt'],
    ['https://generativelanguage.googleapis.com','https://generativelanguage.googleapis.com/v1beta/openai','gemini'],
    ['https://api.anthropic.com/v1/messages','https://api.anthropic.com/v1','claude']
  ]){
    const group={apiBase:base,authMode:'api_key',providerProtocol:provider==='claude'?'anthropic_messages':'openai_chat_compat',models:[{model:'demo'}]};
    const [first]=importedProfiles([group],false).profiles;assert.equal(first.base_url,expected);assert.equal(first.provider,provider);
  }
});

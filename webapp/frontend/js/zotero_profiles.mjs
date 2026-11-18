// Source format: llm-for-zotero src/utils/modelProviders.ts, modelProviderGroups.
const prefKey='extensions.zotero.llmforzotero.modelProviderGroups';
export function zoteroProfileGroups(value) {
  let groups=Array.isArray(value)||typeof value==='string'?value:value?.modelProviderGroups??value?.[prefKey];
  if(typeof groups==='string')groups=JSON.parse(groups);
  if(!Array.isArray(groups))throw Error('Expected a modelProviderGroups JSON array');
  return groups;
}
function resolveConnection(group, protocol) {
  if(typeof group.apiBase!=='string')throw Error('Missing apiBase');
  const url=new URL(group.apiBase);
  if(!['http:','https:'].includes(url.protocol)||url.username||url.password||url.search||url.hash)throw Error('Invalid API base URL');
  const host=url.hostname, path=url.pathname.replace(/\/+$/,'');
  const official=url.protocol==='https:'&&!url.port;
  const minimax=official&&['api.minimax.cn','api.minimax.io'].includes(host);
  if(minimax&&['openai_chat_compat','anthropic_messages'].includes(protocol)){
    const anthropic=protocol==='anthropic_messages';
    const allowed=anthropic?['','/anthropic','/anthropic/v1','/anthropic/v1/messages']:['','/v1','/v1/chat/completions'];
    if(!allowed.includes(path))throw Error('MiniMax protocol does not match its endpoint');
    return {provider:'minimax',region:host.endsWith('.cn')?'china':'international',protocol:anthropic?'anthropic':'openai',base_url:url.origin+(anthropic?'/anthropic':'/v1')};
  }
  if(protocol==='anthropic_messages'&&official&&host==='api.anthropic.com'&&['','/v1','/v1/messages'].includes(path))
    return {provider:'claude',base_url:url.origin+'/v1'};
  if(protocol==='anthropic_messages')throw Error('Custom Anthropic Messages endpoint is unsupported');
  if(protocol!=='openai_chat_compat')throw Error('Unsupported protocol: '+protocol);
  if(official&&host==='api.openai.com'&&['','/v1','/v1/chat/completions'].includes(path))
    return {provider:'chatgpt',base_url:url.origin+'/v1'};
  if(official&&host==='generativelanguage.googleapis.com'&&['','/v1beta','/v1beta/openai','/v1beta/openai/chat/completions'].includes(path))
    return {provider:'gemini',base_url:url.origin+'/v1beta/openai'};
  // Zotero appends /v1/chat/completions when the supplied prefix has no API version.
  let prefix=path;
  if(/\/(chat\/completions|responses|embeddings|files)$/.test(path))prefix=path.replace(/\/(chat\/completions|responses|embeddings|files)$/,'');
  else if(!/\/v\d+(?:beta)?\b/.test(path))prefix+='/v1';
  return {provider:'custom',base_url:url.origin+prefix};
}

export function importedProfiles(groups, includeKeys, existing=[]) {
  const seen=new Set(existing.map(row=>row.zotero_source).filter(Boolean));
  const profiles=[], messages=[];
  let total=0;
  for(const [index,group] of groups.entries()){
    const prefix='Group '+(index+1);
    if(!group||!Array.isArray(group.models)){messages.push(prefix+' · missing model list');continue;}
    if(typeof group.authMode!=='undefined'&&group.authMode!=='api_key'){
      messages.push(prefix+' · unsupported authentication: '+String(group.authMode).slice(0,40));continue;
    }
    for(const [n,row] of group.models.entries()){
      const label=prefix+' / '+(n+1);
      if(++total>500)throw Error('At most 500 model entries per import');
      try {
        if(typeof row?.model!=='string'||!/^[a-z\d][a-z\d._:/-]{0,199}$/i.test(row.model)||['auto','mixed','fusion'].includes(row.model))throw Error('Invalid chat model name');
        const protocol=row.providerProtocol||group.providerProtocol;
        const conn=resolveConnection(group,protocol);
        const source=JSON.stringify([group.id||conn.base_url,row.id||row.model]);
        if(seen.has(source)){messages.push(label+' · already imported');continue;}
        const host=new URL(conn.base_url).hostname;
        const entry={...conn,name:(host+' / '+row.model).slice(0,80),model:row.model,zotero_source:source,
          api_key:includeKeys&&typeof group.apiKey==='string'?group.apiKey:''};
        if(row.temperature!=null){
          const supported=conn.provider!=='minimax'&&!(conn.provider==='chatgpt'&&/^(gpt-[56]|o[134](?:-|$))/i.test(row.model))
            &&!(conn.provider==='claude'&&/claude-(?:opus-4[.-][7-9]|(?:opus|sonnet|haiku)-[5-9]|mythos|fable)/i.test(row.model));
          if(supported&&Number.isFinite(row.temperature)&&row.temperature>=0&&row.temperature<=(conn.provider==='claude'?1:2))entry.temperature=row.temperature;
          else messages.push(label+' · temperature omitted for this model or value');
        }
        if(row.outputTokenLimit?.mode==='custom'){
          const cap=row.outputTokenLimit.tokens;
          if(Number.isInteger(cap)&&cap>0&&cap<=65536)entry.max_tokens_output=cap;
          else messages.push(label+' · output limit outside EMP range; using default');
        }
        if(row.inputMode||row.inputTokenCap||row.profileOverride)messages.push(label+' · Zotero input/override settings are not imported');
        profiles.push(entry);seen.add(source);
      }catch(error){messages.push(label+' · '+(error instanceof TypeError?'Invalid API base URL':error.message));}
    }
  }
  return {profiles,messages};
}

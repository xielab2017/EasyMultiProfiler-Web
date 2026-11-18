import {zoteroProfileGroups, importedProfiles} from './zotero_profiles.mjs';
// Named connection profiles are local to the browser. Only the selected connection
// is copied to an API request. The profile directory never enters a chat payload.
const storageKey = 'emp_named_model_profiles_v1';
export function namedProfiles(storage = localStorage) {
  try {
    const rows = JSON.parse(storage.getItem(storageKey) || '[]');
    return Array.isArray(rows) ? rows.filter(row => row?.id && row.name && row.provider && row.model) : [];
  } catch { return []; }
}
function uniqueId() {
  return 'profile-'+Date.now().toString(36)+'-'+Math.random().toString(36).slice(2);
}
export function saveNamedProfile(profile, storage = localStorage) {
  const current = namedProfiles(storage);
  const source = current.find(row=>row.id===profile.id)?.zotero_source;
  const rows = current.filter(row => row.id !== profile.id);
  storage.setItem(storageKey, JSON.stringify([...rows, {...profile,...(source?{zotero_source:source}:{})}]));
}
export function removeNamedProfile(id, storage = localStorage) {
  storage.setItem(storageKey, JSON.stringify(namedProfiles(storage).filter(row => row.id !== id)));
}
export function connectionBody({provider, config}) {
  return {
    provider: provider === 'chatgpt' ? 'openai' : provider, model: config.model,
    base_url: config.base_url || '', api_key: config.api_key || '', enabled: true,
    ...(provider === 'minimax' ? {region: config.region, protocol: config.protocol} : {}),
    ...Object.fromEntries(['temperature', 'max_tokens_output', 'profile_id'].filter(k => config[k] != null).map(k => [k,config[k]])),
  };
}
export function profileChoices(regularRows, profiles, active, available) {
  const rows = profiles.filter(available).map(p => ({
    id: JSON.stringify([p.provider,p.model,p.id]), provider:p.provider, model:p.model, label:p.name+' · '+p.model,
  }));
  const selected = rows.find(row => JSON.parse(row.id)[2] === active?.profile_id);
  return [...rows.filter(row => row !== selected), ...regularRows, ...(selected ? [selected] : [])];
}

export function mountProfileEditor(root, {readConfiguration, applyProfile, available, translate}) {
  const doc = root.ownerDocument;
  const make = tag => doc.createElement(tag);
  const details = make('details'), summary = make('summary'), group = make('div');
  group.className = 'models-form';
  const field = (tag,id) => {
    const label=make('label'), text=make('span'), control=make(tag);
    control.id=id; label.append(text,control); group.append(label);
    return {text,control};
  };
  const picker=field('select','models-profile-id'), name=field('input','models-profile-name');
  name.control.maxLength=80;
  const temp=field('input','models-temperature'), limit=field('input','models-max-tokens');
  Object.assign(temp.control,{type:'number',min:'0',max:'2',step:'any'});
  Object.assign(limit.control,{type:'number',min:'1',max:'65536',step:'1'});
  const actions=make('div'), save=make('button'), remove=make('button'), status=make('p');
  status.setAttribute('role','status'); actions.className='wb-actions';
  for(const button of [save,remove]){button.type='button';button.className='btn btn-outline';actions.append(button);}
  const keyField=field('input','models-zotero-keys');
  keyField.control.type='checkbox';keyField.control.checked=false;
  const fileField=field('input','models-zotero-import');
  fileField.control.type='file';fileField.control.accept='.json,application/json';
  const importReport=make('pre');importReport.setAttribute('role','status');
  fileField.control.onchange=async()=>{
    const file=fileField.control.files?.[0],withKeys=keyField.control.checked;
    keyField.control.checked=false;
    if(!file)return;
    try{
      if(file.size>1024*1024)throw Error('JSON exceeds 1 MiB');
      const groups=zoteroProfileGroups(JSON.parse(await file.text()));
      const current=namedProfiles(),result=importedProfiles(groups,withKeys,current);
      if(result.profiles.length){
        const rows=result.profiles.map(profile=>({...profile,id:uniqueId()}));
        localStorage.setItem(storageKey,JSON.stringify([...current,...rows]));
        render();window.dispatchEvent(new CustomEvent('emp:model-profiles-change'));
      }
      importReport.textContent=[tx('已导入方案：','Profiles imported: ')+result.profiles.length,...result.messages].join('\n');
    }catch(error){
      importReport.textContent=tx('导入失败。','Import failed. ')+(error instanceof SyntaxError?'Invalid JSON':error.message);
    }finally{fileField.control.value='';}
  };
  group.append(actions,status,importReport); details.append(summary,group); root.append(details);
  const tx=translate;
  function render(id=picker.control.value) {
    fileField.text.textContent=tx('导入 Zotero modelProviderGroups JSON','Import Zotero modelProviderGroups JSON');
    keyField.text.textContent=tx('导入时保留文件中的 API Key','Include API keys when importing');
    summary.textContent=tx('模型配置方案','Model profiles');
    picker.text.textContent=tx('选择方案','Select profile'); name.text.textContent=tx('方案名称','Profile name');
    temp.text.textContent=tx('Temperature（可选）','Temperature (optional)');
    limit.text.textContent=tx('最大输出 token（可选）','Maximum output tokens (optional)');
    for(const node of [temp.control,limit.control]) node.placeholder=tx('模型默认值','Model default');
    save.textContent=tx('保存方案','Save profile');remove.textContent=tx('删除方案','Delete profile');
    const first=make('option');first.value='';first.textContent=tx('新建方案','New profile');picker.control.replaceChildren(first);
    for(const row of namedProfiles()){
      const opt=make('option');opt.value=row.id;opt.textContent=row.name+' · '+row.model;opt.disabled=!available(row);
      picker.control.append(opt);
    }
    picker.control.value=[...picker.control.options].some(o=>o.value===id&&!o.disabled)?id:'';
    remove.disabled=!picker.control.value;
    if(picker.control.value)name.control.value=namedProfiles().find(row=>row.id===picker.control.value)?.name||'';
  }
  function select(id) {
    const row=namedProfiles().find(p=>p.id===id);
    if(!row||!available(row))return false;
    applyProfile(row);
    render(id); name.control.value=row.name;
    return true;
  }
  picker.control.onchange=()=>{
    status.textContent='';
    if(!select(picker.control.value)){name.control.value='';render('');}
  };
  save.onclick=()=>{
    const title=name.control.value.trim();
    if(!title){name.control.focus();status.textContent=tx('请输入方案名称。','Enter a profile name.');return;}
    if(![temp.control,limit.control].every(el=>el.reportValidity()))return;
    const {provider,config}=readConfiguration();
    if(!config.model||['auto','remote'].includes(provider)||['auto','mixed','fusion','__custom__'].includes(config.model)){
      status.textContent=tx('请选择一个具体对话模型。','Select one chat model.');return;
    }
    const id=picker.control.value||uniqueId();
    const {enabled,profile_id,...connection}=connectionBody({provider,config});
    try {saveNamedProfile({...connection,provider,id,name:title});}
    catch {status.textContent=tx('浏览器未能保存方案。','Browser could not save profile.');return;}
    render(id);status.textContent=tx('方案已保存在此浏览器。','Profile saved in this browser.');
    window.dispatchEvent(new CustomEvent('emp:model-profiles-change'));
  };
  remove.onclick=()=>{
    try{removeNamedProfile(picker.control.value);}catch{status.textContent=tx('删除失败。','Could not delete profile.');return;}
    name.control.value='';render('');status.textContent=tx('方案已删除。','Profile deleted.');
    window.dispatchEvent(new CustomEvent('emp:model-profiles-change'));
  };
  window.addEventListener('emp:locale-change',()=>render());
  const provider=doc.getElementById('code-lab-llm-provider');
  provider.addEventListener('change',()=>{
    render('');name.control.value='';status.textContent='';
    const last=readConfiguration().config.profiles?.[provider.value];
    temp.control.value=last?.temperature??'';limit.control.value=last?.max_tokens_output??'';
  });
  render();return {select,render};
}

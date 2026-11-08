import test from 'node:test';import assert from 'node:assert/strict';
import {navigationEntries} from '../frontend/js/navigation_sync.mjs';
import {buildUIIndex,uiTranslation,localizeUI} from '../frontend/js/ui_language.mjs';
const item=(page,label,hidden=false)=>({dataset:{page},hidden,classList:{contains:()=>false},querySelector:()=>({textContent:label})});
test('navigation projects the current sidebar order and omits retired or hidden entries',()=>{
 const rows=[item('course','Course'),item('models','Models'),item('matrix','Matrices'),item('prompts','AI prompts'),item('analysis','Analyze',true)];
 assert.deepEqual(navigationEntries(rows).map(x=>x.page),['models','matrix']);
 rows.splice(1,2,rows[2],rows[1]);assert.deepEqual(navigationEntries(rows).map(x=>x.page),['matrix','models']);
});
test('UI labels translate back and forth without touching sample values or result data',()=>{
 const bank={en:{run:'Run'},zh:{run:'运行'},ja:{run:'実行'}};
 const index=buildUIIndex(bank,{'Axis X':'X 轴'}),tr=(key,locale)=>bank[locale]?.[key]||bank.en[key];
 assert.equal(uiTranslation(' Run ','zh',index,tr),' 运行 ');assert.equal(uiTranslation('运行','ja',index,tr),'実行');
 assert.equal(uiTranslation('Axis X','zh',index,tr),'X 轴');assert.equal(uiTranslation('X 轴','en',index,tr),'Axis X');
 assert.equal(uiTranslation('Patient-运行-01','en',index,tr),'Patient-运行-01');
 const text={nodeType:3,textContent:'Run'},data={nodeType:3,textContent:'Run'};
 const safe={childNodes:[text],closest:()=>null,hasAttribute:()=>false};const result={childNodes:[data],closest:()=>({}),hasAttribute:()=>false};
 const root={querySelectorAll:()=>[safe,result],value:'Run',checked:true};localizeUI(root,{locale:'zh',index,translate:tr});
 assert.equal(text.textContent,'运行');assert.equal(data.textContent,'Run');assert.equal(root.value,'Run');assert.equal(root.checked,true);
});
test('release labels update their web version and leave unrelated text intact',async()=>{
 const {versionText}=await import('../frontend/js/app_version.mjs');
 assert.equal(versionText('Welcome EasyMultiProfiler v9.1.0','9.3.1'),'Welcome EasyMultiProfiler v9.3.1');
 assert.equal(versionText('Download CSV','9.3.1'),'Download CSV');
});
test('repeated DOM localization retains original source and stable whitespace across locales',()=>{
 const bank={'Run':{zh:' 运行 ',de:'Ausführen'},'Filters':{zh:'筛选',de:'Filter'},'Filter':{zh:'过滤',de:'Filtern'}};
 const index=buildUIIndex({}, {},bank),text={nodeType:3,textContent:' Run '},ambiguous={nodeType:3,textContent:'Filters'};
 const element=node=>({childNodes:[node],closest:()=>null,hasAttribute:()=>false});
 const root={querySelectorAll:()=>[element(text),element(ambiguous)]};
 for(let i=0;i<20;i++)localizeUI(root,{locale:'de',index,translate:()=>''});
 assert.equal(text.textContent,' Ausführen ');assert.equal(ambiguous.textContent,'Filter');
 localizeUI(root,{locale:'zh',index,translate:()=>''});assert.equal(text.textContent,' 运行 ');assert.equal(ambiguous.textContent,'筛选');
 localizeUI(root,{locale:'en',index,translate:()=>''});assert.equal(text.textContent,' Run ');assert.equal(ambiguous.textContent,'Filters');
});
test('full locale rows and bilingual aliases round trip through the selected language',()=>{
 const index=buildUIIndex({}, {'Thinking depth':'思考深度'}, {'Thinking depth':{ru:'Глубина размышления',ja:'思考の深さ',zh:'思考深度','zh-TW':'思考深度'}},{'思考深度 / Thinking depth':'Thinking depth'});
 assert.equal(uiTranslation('思考深度 / Thinking depth','ru',index,()=>''),'Глубина размышления');
 assert.equal(uiTranslation('Глубина размышления','ja',index,()=>''),'思考の深さ');
 assert.equal(uiTranslation('思考の深さ','zh',index,()=>''),'思考深度');
});
test('the shipped UI catalog covers all 11 locales and preserves every placeholder',async()=>{
 const {UI_LOCALES_FULL}=await import('../frontend/js/ui_locales_full.mjs');
 const locales=['zh','zh-TW','ja','ko','ar','es','fr','de','pt','ru'];assert(Object.keys(UI_LOCALES_FULL).length>=2700);
 for(const [source,row]of Object.entries(UI_LOCALES_FULL))for(const locale of locales){assert.equal(typeof row[locale],'string',source+' '+locale);assert(row[locale].trim());assert.deepEqual([...row[locale].matchAll(/\{[^{}]+\}/g)].map(m=>m[0]).sort(),[...source.matchAll(/\{[^{}]+\}/g)].map(m=>m[0]).sort());}
 for(const row of Object.values(UI_LOCALES_FULL))for(const locale of ['ko','ar','es','fr','de','pt','ru'])assert(!/[\u4e00-\u9fff]/.test(row[locale]),'Chinese text leaked into '+locale);
 assert.match(UI_LOCALES_FULL['Models and API'].ru,/Модел/i);
 assert.match(UI_LOCALES_FULL['Thinking depth'].ja,/[\u3040-\u30ff\u4e00-\u9fff]/);
});

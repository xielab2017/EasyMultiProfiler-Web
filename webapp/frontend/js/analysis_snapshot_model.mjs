// Plot only values retained in an immutable job result; never re-run an assay.
export function resultRows(value){
 if(typeof value==='string'){try{return resultRows(JSON.parse(value));}catch{return [];}}
 if(Array.isArray(value))return value.filter(row=>row&&typeof row==='object'&&!Array.isArray(row));
 if(!value||typeof value!=='object')return [];
 if(value.data!==undefined)return resultRows(value.data);
 const keys=Object.keys(value);if(!keys.length)return [];
 if(keys.every(key=>Array.isArray(value[key]))&&keys.every(key=>value[key].length===value[keys[0]].length))return value[keys[0]].map((_,i)=>Object.fromEntries(keys.map(key=>[key,value[key][i]])));
 return [value];
}
const numeric=value=>(typeof value==='number'||typeof value==='string')&&String(value).trim()!==''&&Number.isFinite(Number(value));
const column=(keys,names)=>keys.find(key=>names.includes(key));
const fraction=value=>{if(numeric(value))return Number(value);if(typeof value!=='string'||!/^\d+\s*\/\s*\d+$/.test(value))return NaN;const [a,b]=value.split('/').map(Number);return b>0?a/b:NaN;};
export function availableSnapshotPlots(kind,value){
 const rows=resultRows(value),keys=Object.keys(rows[0]||{}),choices=[];
 if(/dimension/.test(kind))choices.push({id:'default',label:'降维散点图'});
 if(/correlation/.test(kind))choices.push({id:'default',label:'相关矩阵热图'},{id:'network',label:'相关网络图（探索性）'});
 if(/cluster/.test(kind))choices.push({id:'default',label:'各聚类样本数条形图'});
 if(/enrich/.test(kind)){choices.push({id:'default',label:'富集条目基因数条形图'});if(column(keys,['GeneRatio','gene_ratio'])&&column(keys,['Count','count']))choices.push({id:'bubble',label:'富集气泡图'});}
 if(column(keys,['log2FoldChange','avg_log2FC','log2FC','logFC'])&&column(keys,['padj','p_adj','FDR','pvalue','p_value','p.value']))choices.push({id:'volcano',label:'火山图'},{id:'effect_bar',label:'差异效应条形图'});
 return choices;
}
export function snapshotPlot(kind,value,mode='default'){
 const rows=resultRows(value);if(!rows.length)throw Error('此快照没有可绘制的结果表。');
 const keys=Object.keys(rows[0]);
 if(mode==='volcano'||mode==='effect_bar'){
  const effect=column(keys,['log2FoldChange','avg_log2FC','log2FC','logFC']),p=column(keys,['padj','p_adj','FDR','pvalue','p_value','p.value']),feature=column(keys,['feature','symbol','gene','Name','name','ID','primary']);
  if(!effect||!p)throw Error('此快照缺少差异效应或 P/FDR 数值。');
  const data=rows.map((row,i)=>({x:Number(row[effect]),p:Number(row[p]),valid:numeric(row[effect])&&numeric(row[p]),label:feature?String(row[feature]):`行 ${i+1}`})).filter(row=>row.valid&&row.p>=0&&row.p<=1);
  if(!data.length)throw Error('没有可绘制的有限差异统计量。');
  const note=`使用列 ${effect} 与 ${p}；不替换缺失统计量；P=0 的显示值封顶为 −log10(P)=300。`;
  if(mode==='effect_bar')return {type:'bars',bars:[...data].sort((a,b)=>a.p-b.p).slice(0,20).map(row=>({label:row.label,value:row.x})),title:'按 P/FDR 排序的前 20 个差异效应',note};
  return {type:'scatter',points:data.map(row=>({x:row.x,y:row.p===0?300:-Math.log10(row.p),color:row.p<.05?(row.x>=0?'#b91c1c':'#1d4ed8'):'#94a3b8'})),xLabel:effect,yLabel:`−log10(${p})`,title:'差异结果火山图',note};
 }
 if(mode==='bubble'){
  const ratio=column(keys,['GeneRatio','gene_ratio']),count=column(keys,['Count','count']),label=column(keys,['Description','term','ID']),p=column(keys,['p.adjust','padj','p_adj','FDR','pvalue','p.value']);
  if(!ratio||!count||!label)throw Error('气泡图需要条目名称、GeneRatio 和 Count。');
  const dots=rows.slice(0,20).filter(row=>Number.isFinite(fraction(row[ratio]))&&numeric(row[count])&&Number(row[count])>=0).map(row=>({label:String(row[label]),ratio:fraction(row[ratio]),count:Number(row[count]),p:p&&numeric(row[p])?Number(row[p]):null}));
  if(!dots.length)throw Error('没有有效的条目比例和基因数。');
  return {type:'bubble',dots,title:'富集气泡图',note:`结果顺序前 20 个条目；横轴 GeneRatio，气泡面积表示 Count；${p?'颜色按 '+p+'（<0.05 红色，其余灰色）':'未保存显著性列，统一着色'}。`};
 }
 if(/dimension/.test(kind)){
  const axes=keys.filter(key=>/^(PC|PCoA|UMAP|MDS|tSNE|Dim|Axis|Comp)[._ -]?\d+$/i.test(key));
  if(axes.length<2)throw Error('此快照未保存两个可识别的降维坐标轴，不能用其他元数据代替。');
  const points=rows.filter(row=>numeric(row[axes[0]])&&numeric(row[axes[1]])).map(row=>({x:Number(row[axes[0]]),y:Number(row[axes[1]])}));
  if(!points.length)throw Error('此快照没有有限坐标。');
  return {type:'scatter',points,xLabel:axes[0],yLabel:axes[1],title:'已保存的降维坐标',note:`绘制 ${points.length} 个有限坐标；未重算降维。`};
 }
 if(/correlation/.test(kind)){
  const find=names=>keys.find(key=>names.includes(key))||keys.find(key=>names.some(name=>key===`cor_p.${name}`));
  const a=find(['feature_1','var1']),b=find(['feature_2','var2']),r=find(['coefficient','correlation','r']);
  if(!a||!b||!r)throw Error('此快照缺少相关性变量对和系数列。');
  const pairs=rows.filter(row=>row[a]!=null&&row[b]!=null&&numeric(row[r])&&Math.abs(Number(row[r]))<=1).map(row=>({a:String(row[a]),b:String(row[b]),r:Number(row[r])}));
  const labels=[...new Set(pairs.flatMap(row=>[row.a,row.b]))].slice(0,24);
  return {type:mode==='network'?'network':'correlation',labels,pairs:pairs.filter(row=>labels.includes(row.a)&&labels.includes(row.b)),title:mode==='network'?'已保存变量对的相关网络':'相关系数矩阵',note:'最多显示结果中前 24 个变量；仅绘制保存的变量对，不追加显著性筛选。网络为确定性圆形布局，节点位置不代表生物学距离。'};
 }
 if(/cluster/.test(kind)){
  const key=keys.find(key=>key==='cluster');if(!key)throw Error('此快照未保存聚类标签。');
  const counts=new Map();for(const row of rows){if(row[key]==null||String(row[key])==='')continue;const label=String(row[key]);counts.set(label,(counts.get(label)||0)+1);}
  return {type:'bars',bars:[...counts].map(([label,value])=>({label,value})),title:'各聚类的样本数量',note:'根据已保存的聚类标签计数；不是重新计算的聚类或树状图。'};
 }
 if(/enrich/.test(kind)){
  const desc=keys.find(key=>/^(Description|term|ID)$/i.test(key)),count=keys.find(key=>/^Count$/i.test(key));
  if(!desc||!count)throw Error('此快照缺少富集条目名称或基因数。');
  return {type:'bars',bars:rows.slice(0,20).filter(row=>numeric(row[count])&&Number(row[count])>=0).map(row=>({label:String(row[desc]),value:Number(row[count])})),title:'富集条目涉及的基因数',note:'显示结果顺序的前 20 个条目；显著性和背景基因集请核对完整结果表。'};
 }
 throw Error('此类型暂未接入结果表绘图。可下载完整结果 JSON，或使用该任务已有的图形。');
}

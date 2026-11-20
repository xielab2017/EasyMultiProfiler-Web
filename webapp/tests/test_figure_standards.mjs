import test from 'node:test';import assert from 'node:assert/strict';
import {FIGURE_STANDARDS,figureKindForRequest,figureStandardOptions} from '../frontend/js/figure_standards.mjs';
test('each plot has an independent A4-compatible physical and typography standard',()=>{
 assert.deepEqual([FIGURE_STANDARDS.deg_heatmap.width,FIGURE_STANDARDS.deg_heatmap.height],[180,220]);
 assert.deepEqual([FIGURE_STANDARDS.volcano.width,FIGURE_STANDARDS.volcano.height],[120,100]);
 for(const kind of Object.keys(FIGURE_STANDARDS)){const value=figureStandardOptions(kind);assert.ok(value.export_size.width_mm<=210);assert.ok(value.export_size.height_mm<=297);assert.equal(value.publication.font_pt,10);assert.equal(value.publication.min_font_pt,8);}
 const custom=figureStandardOptions('volcano',{width:110,height:90,font:10,minimum:10});assert.equal(custom.export_size.width_mm,110);assert.equal(figureStandardOptions('deg_heatmap').export_size.width_mm,180);
 assert.equal(figureStandardOptions('deg_heatmap',{width:11,height:8,font:3}).export_size.width_mm,11);assert.equal(figureStandardOptions('deg_heatmap',{width:300,height:300,dpi:150}).export_size.width_mm,300);assert.equal(figureStandardOptions('deg_heatmap',{font:3}).publication.label_mode,'manual');
});
test('registered endpoints choose the matching figure profile',()=>{
 assert.equal(figureKindForRequest('/visualize/deg_heatmap'),'deg_heatmap');assert.equal(figureKindForRequest('/visualize/volcano'),'volcano');
 assert.equal(figureKindForRequest('/visualize/enrichment/dotplot'),'enrichment');assert.equal(figureKindForRequest('/workbench/figure',{kind:'pca'}),'scatter');
 assert.equal(figureKindForRequest('/session'),null);
});

test('figure units preserve physical size; legacy profiles remain millimetres',async()=>{
 const {convertFigureDimension}=await import('../frontend/js/figure_exports.mjs');
 assert.equal(convertFigureDimension(180,'mm','cm'),18);
 assert.equal(convertFigureDimension(1,'in','pt'),72);
 assert.equal(convertFigureDimension(72,'pt','mm'),25.4);
 for(const unit of ['mm','cm','in','pt']){
  const options=figureStandardOptions('deg_heatmap',{unit,width:convertFigureDimension(180,'mm',unit),height:convertFigureDimension(220,'mm',unit)});
  assert.deepEqual(options.export_size,{width_mm:180,height_mm:220,dpi:300});
 }
 const pt=figureStandardOptions('deg_heatmap',{unit:'pt',width:360,height:432});
 assert.deepEqual(pt.export_size,{width_mm:127,height_mm:152.4,dpi:300});
 assert.equal(figureStandardOptions('deg_heatmap',{unit:'cm'}).export_size.width_mm,180);
 assert.equal(figureStandardOptions('deg_heatmap',{width:'180',height:'220'}).export_size.width_mm,180);
 assert.throws(()=>figureStandardOptions('deg_heatmap',{unit:'px'}));
 let width=180;for(let i=0;i<25;i++)for(const [from,to]of [['mm','cm'],['cm','in'],['in','pt'],['pt','mm']])width=convertFigureDimension(width,from,to);
 assert.ok(Math.abs(width-180)<1e-9);
});

test('font controls adjust in half-point steps and support arbitrary positive point sizes',async()=>{
 const {adjustFigureFont}=await import('../frontend/js/figure_standards.mjs');
 assert.deepEqual(adjustFigureFont(8,8,'font',.5),{font:8.5,minimum:8});
 assert.deepEqual(adjustFigureFont(8,8,'font',-.5),{font:7.5,minimum:7.5});
 assert.deepEqual(adjustFigureFont(10,10,'minimum',.5),{font:10.5,minimum:10.5});
 assert.deepEqual(adjustFigureFont(24,8,'font',.5),{font:24.5,minimum:8});
 assert.deepEqual(adjustFigureFont(10,8,'minimum',-.5),{font:10,minimum:7.5});
});

test('positive fonts have no fixed lower or upper limit, and appearance is per type',()=>{
 for(const font of [.25,1,4,7.25,30,96,1000])assert.equal(figureStandardOptions('volcano',{font,minimum:font}).publication.font_pt,font);
 for(const font of [0,-1,NaN,Infinity])assert.throws(()=>figureStandardOptions('heatmap',{font,minimum:font}));
 const a=figureStandardOptions('volcano',{axis_line:.3,threshold_line:2,plot_line:1.2,font:6,minimum:4,title_font:20,palette:'viridis',custom_colors:'#FF0000,#00FF00',dpi:150});
 assert.equal(a.publication.appearance.threshold_line,2);assert.equal(a.export_size.dpi,150);assert.equal(figureStandardOptions('boxplot').publication.appearance,undefined);
 assert.equal(figureStandardOptions('deg_heatmap',{cell_line:0,tree_line:1.5}).publication.appearance.tree_line,1.5);
 for(const bad of [{axis_line:-1},{axis_line:Infinity},{title_font:0},{custom_colors:'javascript:alert(1)'},{palette:'invalid'},{dpi:12}])assert.throws(()=>figureStandardOptions('volcano',bad));
});

test('visible inherited defaults track base text and auto mode without becoming overrides',async()=>{
 const {figureAppearanceDefaults,figureAppearanceSignature}=await import('../frontend/js/figure_standards.mjs');
 const profile={width:60,height:60,font:6,minimum:6,labels:'auto'};
 const defaults=figureAppearanceDefaults('volcano',profile);assert.equal(defaults.title_font,6);assert.equal(defaults.axis_line,.35);assert.equal(defaults.threshold_line,.35);assert.equal(defaults.dpi,300);assert.equal(defaults.legend,'bottom');
 const measured=figureAppearanceDefaults('volcano',profile,{point_size:.4694,axis_title_font:8.5714});assert.equal(measured.point_size,.4694);assert.equal(measured.axis_title_font,8.5714);
 assert.equal(figureAppearanceDefaults('volcano',{...profile,font:9}).label_font,9);
 const options=figureStandardOptions('volcano',profile);assert.equal(options.publication.appearance,undefined);
 assert.equal(figureAppearanceSignature(options),figureAppearanceSignature({...options,session_id:'ignored'}));
 assert.notEqual(figureAppearanceSignature(options),figureAppearanceSignature(figureStandardOptions('volcano',{...profile,point_size:.8})));
});

test('full automatic parameters derive from canvas and ignore manual overrides',async()=>{
 const {automaticFigureOptions}=await import('../frontend/js/figure_standards.mjs');
 let previous=0;for(const side of [60,87,120,180]){const value=automaticFigureOptions('volcano',side,side);assert.ok(value.publication.font_pt>previous);previous=value.publication.font_pt;assert.equal(value.publication.auto_params,true);assert.equal(value.publication.appearance.point_size,undefined);}
 const profile={unit:'mm',width:60,height:60,font:99,minimum:98,grid_line:9,point_size:8,palette:'viridis',auto_params:true};const auto=figureStandardOptions('volcano',profile);assert.equal(auto.publication.font_pt,6);assert.equal(auto.publication.appearance.grid_line,.15);assert.equal(auto.color_panel,'npg');assert.equal(auto.custom_colors,'#2166AC,#BDBDBD,#B2182B');
 const manual=figureStandardOptions('volcano',{...profile,auto_params:false});assert.equal(manual.publication.font_pt,99);assert.equal(manual.publication.appearance.grid_line,9);assert.equal(manual.publication.appearance.point_size,8);
 assert.equal(automaticFigureOptions('heatmap',900,900).export_size.dpi,150);
});
test('heatmaps independently configure scale and Group legend positions',()=>{
 for(const scale of ['auto','top','bottom','left','right'])for(const annotation of ['auto','top','bottom','left','right']){
  const a=figureStandardOptions('deg_heatmap',{scale_position:scale,annotation_position:annotation}).publication.appearance;
  assert.equal(a.scale_position,scale);assert.equal(a.annotation_position,annotation);
 }
 assert.throws(()=>figureStandardOptions('heatmap',{scale_position:'outside'}),/position/);
 assert.equal(figureStandardOptions('volcano',{scale_position:'top'}).publication.appearance,undefined);
 const auto=figureStandardOptions('heatmap',{width:60,height:60,auto_params:true,scale_position:'left',annotation_position:'top'});
 assert.equal(auto.publication.appearance.scale_position,'bottom');assert.equal(auto.publication.appearance.annotation_position,'bottom');
});

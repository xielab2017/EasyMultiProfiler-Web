source('webapp/backend/helpers/utils.R');source('webapp/backend/helpers/plot_theme.R');source('webapp/backend/helpers/viz.R')
root<-file.path('.local_run','verification','automatic-parameters');dir.create(root,recursive=TRUE,showWarnings=FALSE)
previous<-NULL
for(side in c(60,87,120,180)) {
 size<-list(width_mm=side,height_mm=side,dpi=300)
 # The switch overrides previously edited manual fonts, lines and colors.
 emp_viz_style_begin(list(export_size=size,publication=list(font_pt=42,min_font_pt=40,label_mode='auto',auto_params=TRUE,appearance=list(axis_line=9,point_size=8))))
 profile<-emp_publication_profile();stopifnot(profile$auto_params,profile$font_pt<42,profile$appearance$axis_line<9,is.null(profile$appearance$point_size))
 if(!is.null(previous))stopifnot(profile$font_pt>previous)
 previous<-profile$font_pt
 set.seed(15);m<-matrix(rexp(800),200,dimnames=list(paste0('Gene',1:200),paste0('S',1:4)))
 h<-emp_publication_pheatmap(m,main='Automatic heatmap',annotation_col=data.frame(Group=c('Control','Control','Treatment','Treatment'),row.names=colnames(m)),border_color='grey92',silent=TRUE)
 save_plot_pdf(h,file.path(root,paste0('heatmap-auto-',side,'.pdf')))
 writeBin(base64enc::base64decode(plot_to_base64(h)),file.path(root,paste0('heatmap-auto-',side,'.png')))
 stopifnot(nrow(h$tree_row$merge)==199L,getOption('emp.figure_effective')$cell_line==0)
 cat('PASS automatic heatmap:',side,'mm;',profile$font_pt,'pt; all 200 rows clustered\n')
}
size<-list(width_mm=900,height_mm=900,dpi=600)
emp_viz_style_begin(list(export_size=size,publication=list(auto_params=TRUE)))
stopifnot(getOption('emp.viz_style')$export_size$dpi==150)
profile<-list(font_pt=7,min_font_pt=8,label_mode='manual',appearance=list(point_size=.8,axis_line=1))
emp_viz_style_begin(list(export_size=list(width_mm=60,height_mm=60,dpi=300),publication=profile))
stopifnot(emp_publication_profile()$font_pt==7,emp_publication_profile()$appearance$point_size==.8)
cat('PASS server-authoritative auto fonts / strokes / DPI and manual isolation\n')
# Full auto chooses label density even when an old manual label count was saved.
set.seed(22);fixture<-data.frame(feature=paste0('Gene',1:100),symbol=paste0('Gene',1:100),log2FoldChange=c(runif(30,-3,-1),runif(40,-.5,.5),runif(30,1,5)),padj=c(runif(30,.0001,.01),runif(40,.1,1),runif(30,.0001,.01)))
fixture$pvalue<-fixture$padj;.viz_load_empt<-function(...)NULL;load_diff_raw<-function(...)list(data=fixture);viz_emit_ggplot<-function(p,...)p
emp_viz_style_begin(list(export_size=list(width_mm=60,height_mm=60,dpi=300),publication=list(auto_params=TRUE,figure_kind='volcano')))
p<-make_volcano('fixture','fixture',label_top=2)
q<-emp_publication_plot(p,60/25.4,60/25.4);built<-ggplot2::ggplot_build(q)
stopifnot(nrow(built$data[[1]])==100L,nrow(built$data[[4]])>2,nrow(built$data[[4]])==nrow(built$data[[5]]))
expected<-c(Down='#2166AC',NS='#BDBDBD',Up='#B2182B');stopifnot(all(built$data[[1]]$colour==unname(expected[as.character(p$data$change)])))
save_plot_pdf(p,file.path(root,'volcano-full-auto.pdf'))
cat('PASS automatic volcano labels / matching highlights / conventional colors, all observations retained\n')

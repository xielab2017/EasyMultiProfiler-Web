source('webapp/backend/helpers/utils.R');source('webapp/backend/helpers/plot_theme.R')
root<-'.local_run/verification/heatmap-legend-positions';dir.create(root,recursive=TRUE,showWarnings=FALSE)
set.seed(17);mat<-matrix(rnorm(160),20,dimnames=list(paste0('Gene',1:20),paste0('Sample',1:8)))
annotation<-data.frame(Group=rep(c('Control','Treatment'),each=4),row.names=colnames(mat))
previous<-NULL
for(scale in c('top','bottom','left','right'))for(group in c('top','bottom','left','right')) {
 emp_viz_style_begin(list(export_size=list(width_mm=120,height_mm=140,dpi=150),publication=list(font_pt=8,min_font_pt=8,label_mode='manual',appearance=list(scale_position=scale,annotation_position=group))))
 h<-emp_publication_pheatmap(mat,annotation_col=annotation,scale='row',breaks=seq(-2,2,length.out=101),color=grDevices::colorRampPalette(c('#2166AC','white','#B2182B'))(100),legend_breaks=c(-2,-1,0,1,2),main='Independent legends')
 if(!is.null(previous))stopifnot(identical(h$tree_row,previous$tree_row),identical(h$tree_col,previous$tree_col))
 previous<-h
 eff<-getOption('emp.figure_effective');stopifnot(eff$scale_position==scale,eff$annotation_position==group)
 l<-h$gtable$layout;m<-l[l$name=='matrix',]
 for(side in unique(c(scale,group))){leg<-l[l$name==paste0('publication_legends_',side),];stopifnot(nrow(leg)==1L);stopifnot(switch(side,top=leg$b<m$t,bottom=leg$t>m$b,left=leg$r<m$l,right=leg$l>m$r))}
 stem<-paste(scale,group,sep='-');save_plot_pdf(h,file.path(root,paste0(stem,'.pdf')));writeBin(base64enc::base64decode(plot_to_base64(h)),file.path(root,paste0(stem,'.png')))
}
cat('PASS all 16 independent scale / Group positions; identical clustering and full vector exports\n')

# Regression: a 60 mm volcano with 1564 points clipped its bottom legend and used
# the same point / highlight sizes as a full-size figure.
source('webapp/backend/helpers/utils.R');source('webapp/backend/helpers/plot_theme.R');source('webapp/backend/helpers/viz.R')
set.seed(24);n<-1564L
df<-data.frame(feature=paste0('Gene',seq_len(n)),symbol=paste0('Gene',seq_len(n)),log2FoldChange=c(runif(66,-3,-1),rnorm(1326,0,.6),runif(172,1,5)),padj=c(10^-runif(66,1.5,6.5),runif(1326,.06,1),10^-runif(172,1.5,7)))
df$pvalue<-df$padj
.viz_load_empt<-function(...)NULL;load_diff_raw<-function(...)list(data=df);viz_emit_ggplot<-function(p,...)p
root<-Sys.getenv('EMP_AUTO_LAYOUT_PROOF_DIR',file.path('.local_run','verification','auto-layout'));dir.create(root,recursive=TRUE,showWarnings=FALSE)
p<-make_volcano('test','test');snapshot<-function(x)list(data=x$data,layer_data=lapply(x$layers,function(l)l$data),parameters=lapply(x$layers,function(l)l$aes_params),theme=x$theme);original<-snapshot(p)
for(config in list(c(60,60,6),c(87,87,8),c(120,100,10))) {
 w<-config[1];h<-config[2];font<-config[3]
 emp_viz_style_begin(list(export_size=list(width_mm=w,height_mm=h,dpi=300),publication=list(font_pt=font,min_font_pt=font,label_mode='auto')))
 q<-emp_publication_plot(p,w/25.4,h/25.4)
 stopifnot(nrow(ggplot2::ggplot_build(q)$data[[1]])==n,identical(snapshot(p),original))
 b<-ggplot2::ggplot_build(q);labels<-b$data[[4]];points<-b$data[[1]]
 stopifnot(all(labels$x[labels$hjust==1]<min(points$x)),all(labels$x[labels$hjust==0]>max(points$x)))
 match<-match(labels$label,df$symbol);stopifnot(all(abs(labels$x_orig-df$log2FoldChange[match])<1e-12),all(abs(labels$y_orig+log10(df$padj[match]))<1e-12))
 stopifnot(identical(unname(as.character(b$plot$scales$get_scales('colour')$get_breaks())),c('NS','Up','Down')))

 if(w<100) {
   stopifnot(q$layers[[1]]$aes_params$size<1.75,q$layers[[5]]$aes_params$size<2.6,q$layers[[5]]$aes_params$stroke<.9)
   stopifnot(nrow(q$layers[[4]]$data)<=14L,all(c('Down','Up')%in%as.character(q$layers[[4]]$data$change)))
   if(w==60)stopifnot(nrow(q$layers[[4]]$data)<14L)
 }
 path<-file.path(root,paste0('volcano-auto-',w,'.pdf'));save_plot_pdf(p,path)
 writeBin(base64enc::base64decode(plot_to_base64(p)),file.path(root,paste0('volcano-auto-',w,'.png')))
 grDevices::pdf(tempfile(),width=w/25.4,height=h/25.4)
 g<-emp_publication_draw_ggplot(q)
 grid::grid.force();drawn<-grid::grid.ls(print=FALSE)$name
 cat('Callout audit:',w,'mm;',nrow(labels),'labels;',sum(grepl('^segmentrepelgrob',drawn)),'connectors;',sum(grepl('^textrepelgrob',drawn)),'text grobs\n')
 stopifnot(sum(grepl('^segmentrepelgrob',drawn))==nrow(labels),sum(grepl('^textrepelgrob',drawn))==nrow(labels))
 boxes<-Filter(Negate(is.null),emp_publication_guide_bounds(g,w,h))
 stopifnot(length(boxes)>0L,all(vapply(boxes,function(b)b$width<=b$available_width+.1,logical(1))))
 for(i in which(grepl('^guide-box',g$layout$name))) {
   box<-g$grobs[[i]];if(inherits(box,'zeroGrob'))next
   guides<-Filter(function(x)inherits(x,'gtable'),box$grobs)
   for(guide in guides){labels<-guide$layout[grepl('^label',guide$layout$name),,drop=FALSE];if(nrow(labels)>1L)stopifnot(length(unique(labels$l))==1L,all(diff(labels$t)>0))}
 }
 for(box in boxes)cat('PASS guide extent:',w,'mm canvas;',box$name,round(box$width,2),'<=',round(box$available_width,2),'mm\n')
 grDevices::dev.off()
}
emp_viz_style_begin(list(export_size=list(width_mm=60,height_mm=60,dpi=300),publication=list(font_pt=6,min_font_pt=6,label_mode='manual')))
q<-emp_publication_plot(p,60/25.4,60/25.4)
stopifnot(q$layers[[1]]$aes_params$size==1.75,q$layers[[5]]$aes_params$size==2.6,nrow(q$layers[[4]]$data)==14L)
emp_viz_style_begin(list(export_size=list(width_mm=60,height_mm=60,dpi=300),publication=list(font_pt=6,min_font_pt=6,label_mode='auto',appearance=list(point_size=1.1,threshold_line=2))))
q<-emp_publication_plot(p,60/25.4,60/25.4)
stopifnot(q$layers[[1]]$aes_params$size==1.1,abs(q$layers[[2]]$aes_params$linewidth*(72.27/25.4)*.75-2)<1e-10)
cat('PASS adaptive volcano density / highlights / labels, NS / Up / Down legend, external label lanes and one connector per label, unchanged observations, manual isolation, explicit overrides\n')

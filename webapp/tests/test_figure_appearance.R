source('webapp/backend/helpers/utils.R');source('webapp/backend/helpers/plot_theme.R');source('webapp/backend/helpers/viz.R')
root<-file.path('.local_run','verification','figure-appearance');dir.create(root,recursive=TRUE,showWarnings=FALSE)
base<-list(font_pt=6,min_font_pt=3,label_mode='auto')
a<-list(axis_line=1.5,plot_line=2.25,threshold_line=3,grid_line=.25,point_size=2,title_font=12,axis_font=5,axis_title_font=7,legend_font=4,label_font=3,family='sans',legend='bottom')
base$appearance<-a
p<-ggplot2::ggplot(mtcars,ggplot2::aes(wt,mpg))+ggplot2::geom_point(size=.5)+ggplot2::geom_line()+ggplot2::geom_hline(yintercept=20)+ggplot2::geom_text(ggplot2::aes(label=rownames(mtcars)))+ggplot2::labs(title='Style proof')+ggplot2::theme_bw()
style<-list(export_size=list(width_mm=180,height_mm=160,dpi=150),publication=base)
emp_viz_style_begin(style);q<-emp_publication_plot(p,180/25.4,160/25.4)
stopifnot(q$theme$axis.text.x$size==5,q$theme$axis.title.x$size==7,q$theme$legend.text$size==4,q$theme$plot.title$size==12,abs(q$layers[[3]]$aes_params$linewidth*(72.27/25.4)*.75-3)<1e-10,q$layers[[1]]$aes_params$size==2,p$layers[[1]]$aes_params$size==.5,is.null(p$layers[[3]]$aes_params$linewidth))
save_plot_pdf(p,file.path(root,'line-widths.pdf'))
for(font in c(1,4,7.25,28)){
 base$font_pt<-font;base$min_font_pt<-font;base$appearance<-NULL
 emp_viz_style_begin(list(export_size=list(width_mm=180,height_mm=220,dpi=150),publication=base))
 set.seed(3);m<-matrix(rexp(160),40,dimnames=list(paste0('Gene',1:40),paste0('S',1:4)))
 h<-emp_publication_pheatmap(m,main='Font proof',silent=TRUE)
 save_plot_pdf(h,file.path(root,paste0('font-',font,'.pdf')))
}
base$font_pt<-6;base$min_font_pt<-3;base$appearance<-list(cell_line=.5,tree_line=2,family='sans',title_font=9,legend_font=4)
emp_viz_style_begin(list(export_size=list(width_mm=180,height_mm=220,dpi=150),publication=base))
h<-emp_publication_pheatmap(m,main='Heatmap strokes',silent=TRUE)
get_lwd<-function(g){c(g$gp$lwd,unlist(lapply(g$grobs,get_lwd)),unlist(lapply(g$children,get_lwd)))}
for(name in c('row_tree','col_tree'))stopifnot(all(abs(get_lwd(h$gtable$grobs[[which(h$gtable$layout$name==name)]])* .75-2)<1e-10))
save_plot_pdf(h,file.path(root,'heatmap-lines.pdf'))
for(a in list(list(axis_line=-1),list(title_font=0),list(family='bad'),list(custom_colors='red'),list(unknown=1))) {base$appearance<-a;stopifnot(inherits(tryCatch(emp_publication_validate(base),error=identity),'error'))}
cat('PASS arbitrary positive fonts, individual typography, physical stroke widths, heatmap borders / trees, clone isolation and input validation\n')

# Manual output accepts dense/small canvases and preserves selected text.
base<-list(font_pt=7,min_font_pt=8,label_mode='manual')
for(size in list(c(76.2,101.6),c(50.8,50.8),c(11,8))){
 emp_viz_style_begin(list(export_size=list(width_mm=size[1],height_mm=size[2],dpi=150),publication=base))
 set.seed(8);dense<-matrix(rexp(800),200,dimnames=list(paste0('Gene',1:200),paste0('S',1:4)))
 h<-emp_publication_pheatmap(dense,main='Manual',silent=TRUE)
 save_plot_pdf(h,file.path(root,paste0('manual-',size[1],'.pdf')))
 stopifnot(length(h$gtable$grobs[[which(h$gtable$layout$name=='row_names')]]$label)==200)
}
emp_viz_style_begin(list(export_size=list(width_mm=76.2,height_mm=101.6,dpi=150),publication=base))
p<-ggplot2::ggplot(mtcars,ggplot2::aes(factor(cyl),mpg))+ggplot2::geom_point()+ggplot2::labs(title='Manual')+ggplot2::theme_bw()
q<-emp_publication_plot(p,3,4);stopifnot(q$theme$plot.title$size==7,q$theme$axis.text.x$size==7)
save_plot_pdf(p,file.path(root,'manual-ggplot.pdf'))
cat('PASS manual mode: 76.2 / 50.8 / 11 mm heatmaps, 200 labels retained, base 7 pt below inactive 8 pt floor, no canvas coercion
')

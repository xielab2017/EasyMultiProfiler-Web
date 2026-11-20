source('webapp/backend/helpers/utils.R');source('webapp/backend/helpers/plot_theme.R');source('webapp/backend/helpers/viz_enrichment.R')
root<-'.local_run/verification/enrichment-complete-layout';dir.create(root,recursive=TRUE,showWarnings=FALSE)
terms<-c('Viral protein interaction with cytokine and cytokine receptor','Cytokine-cytokine receptor interaction','Complement and coagulation cascades','Neuroactive ligand-receptor interaction','IL-17 signaling pathway','Lipid and atherosclerosis','Chemokine signaling pathway','Rheumatoid arthritis','Wnt signaling pathway','Influenza A','Amoebiasis','Pertussis','Malaria','Apoptosis','TNF signaling pathway','NF-kappa B signaling pathway','C-type lectin receptor signaling pathway','Cell adhesion molecules','Natural killer cell mediated cytotoxicity','Antigen processing and presentation')
input<-data.frame(ID=paste0('Term',seq_along(terms)),Description=terms,GeneRatio=paste0(seq_along(terms),'/100'),Count=seq_along(terms),p.adjust=seq(.001,.02,length.out=length(terms)),check.names=FALSE)
emp_assert_session_owner<-function(...)TRUE;enrich_viz_source<-function(...)list(data=input,source=list(kind='ora',source_job='synthetic',database='Fixture'));session_path<-function(...)root
original<-.enrich_viz_export;.enrich_viz_export<-function(p,...){last_plot<<-p;original(p,...)}
for(side in c(60,76.2,120,180)){
 size<-list(width_mm=side,height_mm=side,dpi=150)
 for(attempt in 1:4){
  emp_viz_style_begin(list(export_size=size,publication=list(auto_params=TRUE,figure_kind='enrichment')))
  before<-list.files(file.path(root,'plots'))
  out<-tryCatch(enrich_viz_dotplot(list(session_id='fixture',source_job='synthetic',base_size=4,width=size$width_mm/25.4,height=size$height_mm/25.4,label_wrap=0,max_point_size=0,low_color='bad'),'fixture'),emp_figure_layout_error=identity)
  if(!inherits(out,'emp_figure_layout_error'))break
  stopifnot(identical(list.files(file.path(root,'plots')),before))
  # Insufficient space is actionable, with no silently changed size or cropped files.
  stopifnot(out$suggestion$height_mm>size$height_mm||out$suggestion$width_mm>size$width_mm)
  stopifnot(identical(getOption('emp.viz_style')$export_size$width_mm,size$width_mm),identical(getOption('emp.viz_style')$export_size$height_mm,size$height_mm))
  size<-c(out$suggestion,list(dpi=150))
 }
 stopifnot(isTRUE(out$success),out$n_rows==20L,out$parameters$displayed_labels==20L)
 data<-utils::read.csv(file.path(root,'plots',sub('[.]pdf$','.data.csv',out$pdf_name)));stopifnot(identical(data$Description,terms),nrow(data)==20L)
 file.copy(file.path(root,'plots',out$pdf_name),file.path(root,paste0('complete-',side,'.pdf')),overwrite=TRUE)
 writeBin(base64enc::base64decode(out$plot),file.path(root,paste0('complete-',side,'.png')))
 grDevices::pdf(tempfile(fileext='.pdf'),width=size$width_mm/25.4,height=size$height_mm/25.4)
 p<-emp_publication_plot(last_plot,size$width_mm/25.4,size$height_mm/25.4);q<-emp_publication_fit_enrichment(p,size$width_mm,size$height_mm);built<-ggplot2::ggplot_build(q);layout<-attr(q,'emp.enrichment_layout')
 stopifnot(nrow(built$data[[1]])==20L,isTRUE(all.equal(built$data[[1]]$x,seq_along(terms)/100)))
 stopifnot(length(layout$labels)==20L,!any(grepl('…',layout$labels,fixed=TRUE)),identical(gsub('[[:space:]]','',unname(layout$labels)),gsub('[[:space:]]','',terms)),layout$panel_height>=sum(layout$row_heights)-.1,layout$panel_width>=15)
 stopifnot(all(vapply(layout$guide_bounds,function(b)b$height<=b$available_height+.1&&b$width<=b$available_width+.1,logical(1))))
 stopifnot(q$theme$legend.position=='right',all(is.finite(built$data[[1]]$y)))
 grDevices::dev.off()
 cat('PASS complete enrichment:',side,'mm requested ->',size$width_mm,'x',size$height_mm,'mm accepted; all 20 full labels, points and legends retained\n')
}
# Manual fonts / wrapping stay user-controlled. Explicitly accept suggested size.
size<-list(width_mm=76.2,height_mm=76.2,dpi=150)
for(attempt in 1:4){
 emp_viz_style_begin(list(export_size=size,publication=list(font_pt=4,min_font_pt=8,label_mode='manual')))
 manual<-tryCatch(enrich_viz_dotplot(list(session_id='fixture',source_job='synthetic',base_size=4,width=size$width_mm/25.4,height=size$height_mm/25.4,label_wrap=5),'fixture'),emp_figure_layout_error=identity)
 if(!inherits(manual,'emp_figure_layout_error'))break
 size<-c(manual$suggestion,list(dpi=150))
}
stopifnot(manual$success,manual$parameters$label_wrap>0,manual$parameters$base_size==4,emp_publication_profile()$font_pt==4)
cat('PASS manual full names: font 4 and wrap 5 preserved; size changed only by explicit acceptance\n')

res<-new.env();reply<-safe_api(stop(structure(list(message='needs space',call=NULL,suggestion=list(width_mm=120,height_mm=200)),class=c('emp_figure_layout_error','error','condition'))),res)
stopifnot(res$status==422,reply$code=='FIGURE_LAYOUT_NEEDS_SPACE',reply$layout_suggestion$height_mm==200)
cat('PASS structured size advice and cleanup of incomplete exports\n')
for(position in c('left','right','top','bottom','none')){
 emp_viz_style_begin(list(export_size=list(width_mm=180,height_mm=240,dpi=150),publication=list(font_pt=8,min_font_pt=8,label_mode='manual',appearance=list(axis_font=9,legend_font=12,title_font=18,legend=position))))
 out<-enrich_viz_dotplot(list(session_id='fixture',source_job='synthetic',base_size=8,width=180/25.4,height=240/25.4,label_wrap=40,max_point_size=3),'fixture')
 stopifnot(out$success,out$parameters$displayed_labels==20L,getOption('emp.figure_effective')$axis_font==9,getOption('emp.figure_effective')$legend_font==12)
}
cat('PASS custom typography and all five user-selected legend positions\n')
previous_format<-getOption('emp.figure_format');options(emp.figure_format='caller-format')
plain<-ggplot2::ggplot(data.frame(x=1:2,y=1:2),ggplot2::aes(x,y))+ggplot2::geom_point()
for(ext in c('png','pdf','svg')){emp_publication_export(plain,tempfile(fileext=paste0('.',ext)),2,2);stopifnot(getOption('emp.figure_format')=='caller-format')}
options(emp.figure_format=previous_format)
cat('PASS graphic format restored after PNG / PDF / SVG exports\n')

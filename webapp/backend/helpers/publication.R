# Physical publication policy, shared by synchronous plots and background exports.
emp_publication_profile <- function() {
  profile <- getOption('emp.viz_style', list())$publication
  if (is.null(profile)) return(NULL)
  profile
}
emp_publication_auto_dpi <- function(size) {
  for(dpi in c(300,150,72))if(prod(ceiling(c(size$width_mm,size$height_mm)/25.4*dpi))<=40000000)return(dpi)
  72
}
emp_publication_auto_profile <- function(size,kind=NULL) {
  if(is.null(size))stop('Automatic parameters require a physical canvas')
  short<-min(size$width_mm,size$height_mm);quarter<-function(v)pmax(.25,floor(v*4+.5)/4)
  font<-quarter(max(.5,min(12,6*sqrt(short/60))));scale<-max(.3,min(2,sqrt(short/60)));line<-function(v)as.numeric(sprintf('%.4f',v*scale))
  result<-list(font_pt=font,min_font_pt=font*.65,label_mode='auto',auto_params=TRUE,appearance=list(
    title_font=quarter(font*1.1),axis_font=font,axis_title_font=font,legend_font=quarter(font*.95),label_font=font,
    axis_line=line(.35),plot_line=line(.5),threshold_line=line(.3),grid_line=line(.15),cell_line=line(.2),tree_line=line(.4),
    palette='npg',family='sans',legend=if(size$width_mm>=100&&size$width_mm/size$height_mm>1.2)'right' else 'bottom',background='#FFFFFF',method='original'))
  if(!is.null(kind)){if(length(kind)!=1L||!is.character(kind)||!kind%in%c('heatmap','deg_heatmap','volcano','boxplot','barplot','scatter','enrichment','gsea','ternary','de_significance','alpha','structure','sankey','network','clinical','analysis_dimension','analysis_correlation','analysis_cluster','analysis_marker'))stop('Invalid automatic figure kind');result$figure_kind<-kind}
  if(!is.null(kind)&&kind%in%c('heatmap','deg_heatmap','analysis_correlation')){result$appearance$scale_position<-result$appearance$legend;result$appearance$annotation_position<-result$appearance$legend}
  if(identical(kind,'enrichment'))result$appearance$legend<-'right'
  if(identical(kind,'volcano'))result$appearance$custom_colors<-'#2166AC,#BDBDBD,#B2182B'
  result
}
emp_publication_validate <- function(profile) {
  if (is.null(profile)) return(NULL)
  if (!is.list(profile) || !all(c('font_pt','min_font_pt','label_mode') %in% names(profile)) ||
      !is.numeric(profile$font_pt) || length(profile$font_pt)!=1L || !is.finite(profile$font_pt) ||
      !is.numeric(profile$min_font_pt) || length(profile$min_font_pt)!=1L || !is.finite(profile$min_font_pt) ||
      profile$min_font_pt <= 0 || profile$font_pt <= 0 || (profile$label_mode!='manual'&&profile$font_pt < profile$min_font_pt) ||
      length(profile$label_mode)!=1L || !profile$label_mode %in% c('manual','auto','strict')) stop('Invalid publication typography: use positive finite point sizes; base font must meet the custom minimum')
  if(!is.null(profile$auto_params)&&(!is.logical(profile$auto_params)||length(profile$auto_params)!=1L||is.na(profile$auto_params)))stop('Invalid automatic parameter switch')
  result<-list(font_pt=profile$font_pt,min_font_pt=profile$min_font_pt,label_mode=profile$label_mode)
  if(isTRUE(profile$auto_params))result$auto_params<-TRUE
  if(!is.null(profile$figure_kind))result$figure_kind<-profile$figure_kind
  a<-profile$appearance
  if(!is.null(a)) {
    numbers<-c('title_font','axis_font','axis_title_font','legend_font','label_font','axis_line','plot_line','threshold_line','grid_line','cell_line','tree_line','point_size')
    strings<-list(scale_position=c('auto','left','right','top','bottom'),annotation_position=c('auto','left','right','top','bottom'),palette=c('npg','lancet','nejm','jama','aaas','tableau','set2','dark3','viridis'),family=c('sans','serif','mono','Helvetica','Arial','Times','Courier'),legend=c('right','left','top','bottom','none'),method=c('original','self_built'))
    if(!is.list(a)||is.null(names(a))||anyDuplicated(names(a))||any(!names(a)%in%c(numbers,names(strings),'custom_colors','background')))stop('Invalid per-figure appearance fields')
    for(key in intersect(names(a),numbers)){v<-a[[key]];if(!is.numeric(v)||length(v)!=1L||!is.finite(v)||if(grepl('_line$',key))v<0 else v<=0)stop(paste('Invalid appearance:',key))}
    for(key in intersect(names(a),names(strings)))if(!is.character(a[[key]])||length(a[[key]])!=1L||!a[[key]]%in%strings[[key]])stop(paste('Invalid appearance:',key))
    for(key in intersect(names(a),c('custom_colors','background'))){if(!is.character(a[[key]])||length(a[[key]])!=1L)stop('Invalid figure color');colors<-trimws(strsplit(a[[key]],',',fixed=TRUE)[[1]]);if(!length(colors)||length(colors)>30L||any(!grepl('^#[0-9a-fA-F]{6}$',colors))||(key=='background'&&length(colors)!=1L))stop('Invalid figure color')}
    result$appearance<-a
  }
  result
}
emp_publication_note <- function(message) {
  notes <- getOption('emp.publication_notes', character())
  options(emp.publication_notes=unique(c(notes,message)))
}
emp_publication_wrap <- function(text, width_mm, font_pt) {
  if (is.null(text) || !is.character(text)) return(text)
  # Also split long uninterrupted identifiers so they cannot exceed the page.
  chars <- max(8L, floor(width_mm/(font_pt*25.4/72*.6)))
  vapply(text,function(x)paste(unlist(lapply(strsplit(x,'\n',fixed=TRUE)[[1]],function(line){
    if(nchar(line)>chars && !grepl(' ',line,fixed=TRUE)) return(substring(line,seq(1,nchar(line),chars),pmin(seq(1,nchar(line),chars)+chars-1,nchar(line))))
    strwrap(line,width=chars)
  })),collapse='\n'),character(1),USE.NAMES=FALSE)
}
# Effective appearance is response metadata; observing defaults never applies overrides.
emp_publication_capture_ggplot <- function(p,built=NULL) {
  profile<-emp_publication_profile();if(is.null(profile))return(invisible(NULL))
  a<-profile$appearance %||% list();font<-profile$font_pt
  text<-function(key,fallback=font){v<-p$theme[[key]]$size;if(is.numeric(v)&&length(v)==1L&&is.finite(v))v else fallback}
  stroke<-function(key){el<-p$theme[[key]];if(inherits(el,'element_blank'))return(0);v<-el$linewidth %||% el$size;if(is.numeric(v)&&length(v)==1L&&is.finite(v))v*(72.27/25.4)*.75 else NULL}
  values<-list(title_font=text('plot.title'),axis_font=text('axis.text.x'),axis_title_font=text('axis.title.x'),legend_font=text('legend.text'),label_font=a$label_font %||% font,
    axis_line=stroke('axis.line'),grid_line=stroke('panel.grid.major'),family=a$family %||% p$theme$text$family %||% 'sans',legend=p$theme$legend.position %||% 'right',background=p$theme$plot.background$fill %||% '#FFFFFF',palette=getOption('emp.color_panel','npg'),method=getOption('emp.viz_style',list())$figure_method %||% 'original',dpi=getOption('emp.viz_style',list())$export_size$dpi %||% 300)
  if(!nzchar(values$family))values$family<-'sans'
  if(identical(values$background,'white'))values$background<-'#FFFFFF'
  first_point<-TRUE
  for(i in seq_along(p$layers)) {
    layer<-p$layers[[i]]
    reference<-inherits(layer$geom,c('GeomHline','GeomVline','GeomAbline'))
    if(!is.null(layer$aes_params$linewidth))values[[if(reference)'threshold_line' else 'plot_line']]<-layer$aes_params$linewidth*(72.27/25.4)*.75
    if(inherits(layer$geom,'GeomPoint')&&first_point) {
      first_point<-FALSE;v<-layer$aes_params$size
      if(is.null(v)&&!is.null(built))v<-unique(built$data[[i]]$size)
      if(is.numeric(v)&&length(v)==1L)values$point_size<-v
      else if(is.numeric(v)&&length(v)>1L)values$point_size_range<-range(v,finite=TRUE)
      colors<-if(!is.null(built))unique(built$data[[i]]$colour) else character()
      colors<-colors[!is.na(colors)&grepl('^#[0-9a-fA-F]{6}$',colors)]
      if(length(colors)&&length(colors)<=30L)values$custom_colors<-paste(colors,collapse=',')
    }
  }
  if(!is.null(a$custom_colors))values$custom_colors<-a$custom_colors
  if(identical(profile$figure_kind,'volcano'))values$label_count<-sum(vapply(p$layers,function(layer)if(inherits(layer$geom,'GeomTextRepel')&&is.data.frame(layer$data))nrow(layer$data) else 0L,integer(1)))
  values$axis_line_details<-list(axis=stroke('axis.line'),frame=stroke('panel.border'))
  values$axis_title_details<-list(x=text('axis.title.x'),y=text('axis.title.y'))
  options(emp.figure_effective=values)
  invisible(values)
}
emp_publication_plot <- function(p, width, height) {
  hidden_guides<-attr(p,'emp.hidden_guides')
  profile <- emp_publication_profile()
  if (is.null(profile)) return(p)
  font <- profile$font_pt
  automatic <- !identical(profile$label_mode,'manual')
  adaptive <- identical(profile$label_mode,'auto')
  full_auto <- isTRUE(profile$auto_params)
  appearance <- profile$appearance %||% list()
  volcano_callouts<-attr(p,'emp.volcano_callouts')
  # grid line widths are multiples of 1/96 inch; controls use physical points.
  line_mm <- function(pt)pt/(.75*(72.27/25.4))
  if (inherits(p,'patchwork')) {
    for(i in seq_along(p$patches$plots)) p$patches$plots[[i]] <- emp_publication_plot(p$patches$plots[[i]],width,height)
    if(automatic&&!is.null(p$patches$annotation$title))p$patches$annotation$title<-emp_publication_wrap(p$patches$annotation$title,width*25.4-8,font+2)
    if(automatic&&!is.null(p$patches$annotation$subtitle))p$patches$annotation$subtitle<-emp_publication_wrap(p$patches$annotation$subtitle,width*25.4-8,font)
    p$patches$annotation$theme <- (p$patches$annotation$theme %||% ggplot2::theme())+ggplot2::theme(text=ggplot2::element_text(size=font),plot.title=ggplot2::element_text(size=if(automatic)font+2 else font),plot.subtitle=ggplot2::element_text(size=font))
  }
  if (inherits(p,'ggplot')) {
    compact <- width*25.4 < 100
    if(identical(appearance$method,'self_built'))p<-p+emp_pub_theme(base_size=font)
    auto_point<-NULL;auto_labels<-Inf
    # Respect intentionally blank elements (for example a GSEA rug panel).
    theme <- list(text=ggplot2::element_text(size=font),plot.margin=ggplot2::margin(4,4,4,4))
    for(key in c('axis.text','axis.text.x','axis.text.y','axis.title','axis.title.x','axis.title.y','legend.text','legend.title','strip.text','plot.subtitle','plot.caption','plot.title')) {
      if(!inherits(p$theme[[key]],'element_blank')) theme[[key]]<-ggplot2::element_text(size=if(key=='plot.title'&&!compact&&automatic)font+2 else font)
    }
    for(key in c('axis.text','axis.text.x','axis.text.y'))if(!is.null(appearance$axis_font)&&!inherits(p$theme[[key]],'element_blank'))theme[[key]]<-ggplot2::element_text(size=appearance$axis_font)
    for(key in c('axis.title','axis.title.x','axis.title.y'))if(!is.null(appearance$axis_title_font)&&!inherits(p$theme[[key]],'element_blank'))theme[[key]]<-ggplot2::element_text(size=appearance$axis_title_font)
    for(key in c('legend.text','legend.title'))if(!is.null(appearance$legend_font)&&!inherits(p$theme[[key]],'element_blank'))theme[[key]]<-ggplot2::element_text(size=appearance$legend_font)
    if(!is.null(appearance$title_font))theme$plot.title<-ggplot2::element_text(size=appearance$title_font)
    if(adaptive&&(compact||full_auto)) {
      theme$plot.margin<-if(full_auto)ggplot2::margin(font*.5,font*.5,font*.5,font*.5) else ggplot2::margin(3,3,3,3)
      theme$legend.location<-'plot';theme$legend.title.position<-'top'
      theme$legend.margin<-ggplot2::margin(0,0,0,0)
      theme$legend.box.spacing<-grid::unit(1,'mm');theme$legend.spacing.x<-grid::unit(1,'mm');theme$legend.spacing.y<-grid::unit(.5,'mm')
      theme$legend.key.width<-grid::unit(max(1.5,font*25.4/72),'mm')
      theme$legend.key.height<-grid::unit(max(1.5,font*25.4/72),'mm')
      if(is.null(appearance$axis_line)) {
        theme$axis.ticks<-ggplot2::element_line(linewidth=line_mm(.35),colour='grey30')
        theme$axis.line<-ggplot2::element_line(linewidth=line_mm(.35),colour='grey20')
        theme$panel.border<-ggplot2::element_rect(fill=NA,colour='grey20',linewidth=line_mm(.35))
      }
      if(is.null(appearance$grid_line))theme$panel.grid.major<-ggplot2::element_line(linewidth=line_mm(.2),colour='grey92')
    }
    if(!is.null(appearance$family))theme$text$family<-appearance$family
    if(!is.null(appearance$axis_line)) {
      theme$axis.line<-ggplot2::element_line(linewidth=line_mm(appearance$axis_line))
      theme$axis.ticks<-ggplot2::element_line(linewidth=line_mm(appearance$axis_line))
      theme$panel.border<-ggplot2::element_rect(fill=NA,linewidth=line_mm(appearance$axis_line))
    }
    if(!is.null(appearance$grid_line))theme$panel.grid<-theme$panel.grid.major<-ggplot2::element_line(linewidth=line_mm(appearance$grid_line),colour='grey90')
    if(!is.null(appearance$background)){theme$plot.background<-ggplot2::element_rect(fill=appearance$background,colour=NA);theme$panel.background<-ggplot2::element_rect(fill=appearance$background,colour=NA)}
    if(!is.null(appearance$legend))theme$legend.position<-appearance$legend else if (automatic && compact && !identical(p$theme$legend.position,'none')) theme$legend.position<-'bottom' 
    for(axis in if(automatic)c('x','y') else character()) {
      depth<-emp_publication_math_depth(p$labels[[axis]])
      if(depth>0L)theme[[paste0('axis.title.',axis)]]<-ggplot2::element_text(size=max(appearance$axis_title_font %||% font,profile$min_font_pt/(.7^depth)))
    }
    p <- p+do.call(ggplot2::theme,theme)
    if(automatic)for(key in c('title','subtitle','caption','x','y')) if(is.character(p$labels[[key]]))p$labels[[key]]<-emp_publication_wrap(p$labels[[key]],if(key=='y')height*25.4-12 else width*25.4-8,if(key=='title'&&!compact)font+2 else font)
    if (!inherits(p,'patchwork')) {
      built<-ggplot2::ggplot_build(p)
      if(adaptive&&(compact||full_auto)) {
        points<-which(vapply(p$layers,function(layer)inherits(layer$geom,'GeomPoint'),logical(1)))
        count<-if(length(points))max(vapply(built$data[points],nrow,integer(1))) else 0L
        body_area<-max(1,(width*25.4-14)*(height*25.4-23))
        if(count>0L)auto_point<-max(.2,min(1.2,sqrt(body_area/count)*.45))
        auto_labels<-max(2L,floor(body_area/(font*25.4/72)^2*.025))
      }
      for(axis in if(automatic)setdiff(c('x','y'),if(!is.null(attr(p,'emp.enrichment_labels')))'y' else character()) else character()) {
        scale<-built$plot$scales$get_scales(axis)
        if(!is.null(scale)&&scale$is_discrete()) {
          breaks<-scale$get_breaks();capacity<-max(2L,floor(((if(axis=='x')width else height)*25.4-35)/(font*25.4/72*1.35)))
          if(length(breaks)>capacity) {
            if(profile$label_mode=='strict')stop(sprintf('Publication labels too dense: %d %s-axis labels; capacity %d. Enlarge the A4 panel.',length(breaks),axis,capacity))
            keep<-unique(round(seq(1,length(breaks),length.out=capacity)))
            adjusted<-scale$clone();adjusted$breaks<-breaks[keep]
            p<-p+adjusted
            emp_publication_note(sprintf('%s-axis labels: %d / %d shown at %g pt; all observations retained. / 坐标标签间隔显示，数据完整保留。',axis,length(keep),length(breaks),font))
          }
        }
      }
      if(!is.null(appearance$palette)||!is.null(appearance$custom_colors))for(aesthetic in c('colour','fill')) {
        scale<-built$plot$scales$get_scales(aesthetic)
        if(!is.null(scale)&&scale$is_discrete()) {
          colors<-if(!is.null(appearance$custom_colors))trimws(strsplit(appearance$custom_colors,',',fixed=TRUE)[[1]]) else emp_pub_palette(max(1L,length(scale$get_breaks())),appearance$palette)
          adjusted<-scale$clone();original<-scale$palette
          adjusted$palette<-local({values<-colors;previous<-original;function(n){old<-previous(n);stats::setNames(rep(values,length.out=length(old)),names(old))}})
          adjusted$palette.cache<-NULL;adjusted$n.breaks.cache<-NULL
          p<-suppressMessages(p+adjusted)
        }
      }
      if(automatic) for(aesthetic in c('colour','fill')) {
        scale<-built$plot$scales$get_scales(aesthetic)
        if(!is.null(scale)&&scale$is_discrete()&&length(scale$get_breaks())>0L) {
          guide<-list(ggplot2::guide_legend(ncol=1,byrow=TRUE,title.position=if(adaptive)'top' else 'left'));names(guide)<-aesthetic;p<-p+do.call(ggplot2::guides,guide)
        }
      }
    }
    if(!is.null(auto_point)&&is.null(appearance$point_size)&&is.null(p$mapping$size)&&any(vapply(p$layers,function(layer)inherits(layer$geom,'GeomPoint')&&is.null(layer$mapping$size),logical(1))))emp_publication_note(sprintf('Auto point size: %.2f mm for the current canvas; all observations retained. / 自动点径 %.2f mm，保留全部数据点。',auto_point,auto_point))
    # Clone layers: exporting must not mutate a cached/user plot object.
    p$layers <- lapply(p$layers,function(layer){
      copy<-ggplot2::ggproto(NULL,layer)
      if (inherits(copy$geom,'GeomText') || inherits(copy$geom,'GeomLabel') || inherits(copy$geom,'GeomTextRepel') || inherits(copy$geom,'GeomLabelRepel')) {
        label_font<-appearance$label_font %||% font
        copy$aes_params$size <- if(identical(copy$geom_params$size.unit,'pt'))label_font else label_font/(72.27/25.4)
        if (!is.null(copy$mapping$size)) {copy$mapping$size<-NULL;emp_publication_note('Text size mapping replaced by the publication font; data and point sizes are unchanged.')}
        if(inherits(copy$geom,'GeomTextRepel')||inherits(copy$geom,'GeomLabelRepel')) {
          copy$geom_params$seed<-1L
          if(adaptive&&(compact||full_auto)) {
            if(is.data.frame(copy$data)&&nrow(copy$data)>auto_labels) {
              total<-nrow(copy$data)
              # Round-robin the existing ranked groups: keep both up/down labels.
              groups<-if('change'%in%names(copy$data))split(seq_len(total),copy$data$change,drop=TRUE) else list(seq_len(total))
              order<-unlist(lapply(seq_len(max(lengths(groups))),function(i)vapply(groups,function(g)if(length(g)>=i)g[i] else NA_integer_,integer(1))),use.names=FALSE)
              keep<-head(order[!is.na(order)],auto_labels);copy$data<-copy$data[keep,,drop=FALSE]
              emp_publication_note(sprintf('Auto labels: %d / %d shown; all observations retained. / 自动保留 %d / %d 个标注，数据点全部保留。',length(keep),total,length(keep),total))
            }
            copy$geom_params$box.padding<-grid::unit(.15,'lines');copy$geom_params$point.padding<-grid::unit(.1,'lines')
            copy$geom_params$max.overlaps<-Inf;copy$geom_params$max.iter<-10000L
          }
        }
      }
      reference<-inherits(copy$geom,'GeomHline')||inherits(copy$geom,'GeomVline')||inherits(copy$geom,'GeomAbline')
      width<-if(reference)appearance$threshold_line else appearance$plot_line
      if(is.null(width)&&adaptive&&(compact||full_auto))width<-if(reference).35 else .5
      if(!is.null(width)&&('linewidth'%in%names(copy$geom$default_aes))) {copy$aes_params$linewidth<-line_mm(width);copy$mapping$linewidth<-NULL}
      if(inherits(copy$geom,'GeomPoint')&&is.null(copy$mapping$size)&&is.null(p$mapping$size)) {
        if(!is.null(appearance$point_size))copy$aes_params$size<-appearance$point_size
        else if(!is.null(auto_point)) {
          highlight<-isFALSE(copy$show.legend)
          copy$aes_params$size<-auto_point*(if(highlight)1.6 else 1)
          copy$aes_params$stroke<-min(.15,auto_point*.2)
        }
      }
      copy
    })
    if(!is.null(volcano_callouts)&&is.data.frame(p$data)) {
      # Resolve the lanes at the final export size, after optional label thinning.
      indices<-which(vapply(p$layers,function(layer)inherits(layer$geom,'GeomTextRepel')&&is.data.frame(layer$data)&&'.label_hjust'%in%names(layer$data),logical(1)))
      for(i in indices) {
        rails<-.viz_volcano_callout_rails(p$data,p$layers[[i]]$data,width,height,volcano_callouts$fc_cutoff)
        p$layers[[i]]$position<-.viz_volcano_callout_position(rails$left,rails$right,rails$spacing,rails$ymin,rails$ymax)
        if(full_auto){
          selected<-p$layers[[i]]$data$feature
          for(j in seq_along(p$layers))if(inherits(p$layers[[j]]$geom,'GeomPoint')&&is.data.frame(p$layers[[j]]$data)&&'.label_hjust'%in%names(p$layers[[j]]$data))p$layers[[j]]$data<-p$layers[[j]]$data[p$layers[[j]]$data$feature%in%selected,,drop=FALSE]
        }
        p<-suppressMessages(p+ggplot2::scale_x_continuous(limits=rails$limits,expand=ggplot2::expansion(mult=0)))
      }
    }
    if(length(hidden_guides)){guides<-stats::setNames(rep(list('none'),length(hidden_guides)),hidden_guides);p<-p+do.call(ggplot2::guides,guides)}
    emp_publication_capture_ggplot(p,if(exists('built',inherits=FALSE))built else NULL)
  }
  p
}
emp_publication_text_grob <- function(grob, font) {
  if(inherits(grob,'text')) {
    grob$gp$fontsize <- font; grob$gp$cex <- NULL
  }
  if(!is.null(grob$grobs)) grob$grobs<-lapply(grob$grobs,emp_publication_text_grob,font=font)
  if(!is.null(grob$children)) for(i in seq_along(grob$children))grob$children[[i]]<-emp_publication_text_grob(grob$children[[i]],font)
  grob
}
emp_publication_grob_style <- function(grob,lwd=NULL,family=NULL,border=NULL) {
  if(!is.null(lwd)&&inherits(grob,c('segments','polyline','lines','rect')))grob$gp$lwd<-lwd
  if(!is.null(border)&&inherits(grob,'rect'))grob$gp$col<-border
  if(!is.null(lwd)&&lwd==0&&inherits(grob,c('segments','polyline','lines','rect')))grob$gp$col<-NA
  if(!is.null(family)&&inherits(grob,'text'))grob$gp$fontfamily<-family
  if(!is.null(grob$grobs))grob$grobs<-lapply(grob$grobs,emp_publication_grob_style,lwd=lwd,family=family,border=border)
  if(!is.null(grob$children))for(i in seq_along(grob$children))grob$children[[i]]<-emp_publication_grob_style(grob$children[[i]],lwd=lwd,family=family,border=border)
  grob
}
# Place the scale and annotation legend independently; every legend has padding
# for complete tick glyphs, including negative signs and the endpoint labels.
emp_publication_heatmap_place_legends <- function(out,positions,width_mm,height_mm,font,base_font=font) {
  table<-out$gtable;entries<-list();pad<-max(1.5,font*25.4/72*.75+.5)
  texts<-function(g){c(if(inherits(g,'text'))list(g) else list(),unlist(lapply(g$grobs,texts),recursive=FALSE),unlist(lapply(g$children,texts),recursive=FALSE))}
  for(key in c('scale','annotation')) {
    i<-which(table$layout$name==if(key=='scale')'legend' else 'annotation_legend')
    if(!length(i))next
    grob<-emp_publication_text_grob(table$grobs[[i[1]]],font);labels<-texts(grob)
    widths<-vapply(labels,function(g)grid::convertWidth(grid::grobWidth(g),'mm',valueOnly=TRUE),numeric(1))
    n<-sum(vapply(labels,function(g)length(g$label),integer(1)))
    fm<-max(font,base_font)*25.4/72
    box_width<-max(10,max(c(0,widths))+5)+2*pad
    box_height<-if(key=='scale')min(height_mm*.4,max(16,fm*6+2*pad)) else max(8,n*fm*1.6+2*pad+1)
    # Keep the inner region positive even for deliberately tiny manual canvases.
    box_height<-max(box_height,2*pad+1)
    padded<-gtable::gtable(widths=grid::unit.c(grid::unit(pad,'mm'),grid::unit(1,'null'),grid::unit(pad,'mm')),heights=grid::unit.c(grid::unit(pad,'mm'),grid::unit(1,'null'),grid::unit(pad,'mm')))
    padded<-gtable::gtable_add_grob(padded,grob,t=2,l=2,clip='off')
    entries[[key]]<-list(grob=padded,width=box_width,height=box_height,side=positions[[key]])
  }
  old<-which(table$layout$name%in%c('legend','annotation_legend'))
  if(length(old)) {
    cols<-unique(unlist(lapply(old,function(i)seq.int(table$layout$l[i],table$layout$r[i]))))
    table$widths[cols]<-grid::unit(0,'mm')
    for(i in old)table$grobs[[i]]<-grid::nullGrob()
  }
  matrix<-table$layout[table$layout$name=='matrix',,drop=FALSE]
  table$widths[matrix$l[1]]<-grid::unit(1,'null');table$heights[matrix$t[1]]<-grid::unit(1,'null')
  for(side in c('top','bottom','left','right')) {
    keys<-names(entries)[vapply(entries,function(e)identical(e$side,side),logical(1))]
    if(!length(keys))next
    selected<-entries[keys]
    if(side%in%c('top','bottom')) {
      block<-gtable::gtable(widths=grid::unit(rep(1,length(keys)),'null'),heights=grid::unit(1,'null'))
      for(j in seq_along(keys))block<-gtable::gtable_add_grob(block,selected[[j]]$grob,t=1,l=j,clip='on')
      height<-max(vapply(selected,function(e)e$height,numeric(1)))
      if(side=='top') {
        title<-table$layout[table$layout$name=='main',,drop=FALSE];pos<-if(nrow(title))max(title$b) else 0L
        table<-gtable::gtable_add_rows(table,grid::unit(height,'mm'),pos=pos);row<-pos+1L
      }else{table<-gtable::gtable_add_rows(table,grid::unit(height,'mm'));row<-length(table$heights)}
      table<-gtable::gtable_add_grob(table,block,t=row,l=1,r=length(table$widths),name=paste0('publication_legends_',side),clip='on')
    }else {
      heights<-lapply(keys,function(key)if(length(keys)==1L||key=='scale')grid::unit(1,'null') else grid::unit(entries[[key]]$height,'mm'))
      block<-gtable::gtable(widths=grid::unit(1,'null'),heights=do.call(grid::unit.c,heights))
      for(j in seq_along(keys))block<-gtable::gtable_add_grob(block,selected[[j]]$grob,t=j,l=1,clip='on')
      width<-max(vapply(selected,function(e)e$width,numeric(1)))
      if(side=='left'){table<-gtable::gtable_add_cols(table,grid::unit(width,'mm'),pos=0);col<-1L}else{table<-gtable::gtable_add_cols(table,grid::unit(width,'mm'));col<-length(table$widths)}
      matrix<-table$layout[table$layout$name=='matrix',,drop=FALSE]
      table<-gtable::gtable_add_grob(table,block,t=matrix$t,b=matrix$b,l=col,name=paste0('publication_legends_',side),clip='on')
    }
  }
  out$gtable<-table;out$legend_positions<-positions;out
}
# A heatmap keeps every matrix value. Only printed labels may be thinned.
emp_publication_pheatmap <- function(..., publication_width=NULL, publication_height=NULL) {
  args<-list(...);profile<-emp_publication_profile()
  if(is.null(profile))return(do.call(pheatmap::pheatmap,args))
  size<-emp_figure_size(publication_width %||% 180/25.4,publication_height %||% 120/25.4)
  w<-size$width*25.4;h<-size$height*25.4;font<-profile$font_pt
  automatic<-!identical(profile$label_mode,'manual')
  full_auto<-isTRUE(profile$auto_params)
  mat<-args$mat %||% args[[1]];nr<-nrow(mat);nc<-ncol(mat)
  appearance<-profile$appearance %||% list()
  args$fontsize<-font;args$fontsize_row<-font;args$fontsize_col<-font;args$fontsize_number<-appearance$label_font %||% font
  if(full_auto) {
    if(!isFALSE(args$cluster_rows))args$treeheight_row<-min(args$treeheight_row %||% 50,w*.12*72/25.4)
    if(!isFALSE(args$cluster_cols))args$treeheight_col<-min(args$treeheight_col %||% 50,h*.08*72/25.4)
    if((h-20)/nr<1||(w-30)/nc<1)appearance$cell_line<-0
  }
  if(!is.null(appearance$cell_line)&&appearance$cell_line==0)args$border_color<-NA
  if(!is.null(appearance$custom_colors))args$color<-grDevices::colorRampPalette(trimws(strsplit(appearance$custom_colors,',',fixed=TRUE)[[1]]))(100)
  else if(full_auto)args$color<-grDevices::colorRampPalette(emp_diverging_colors(n=11,panel=appearance$palette %||% 'npg'))(100)
  else if(!is.null(appearance$palette))args$color<-grDevices::colorRampPalette(emp_pub_palette(5,name=appearance$palette))(100)
  args$cellwidth<-NA_real_;args$cellheight<-NA_real_
  title<-args$main %||% '';if(automatic)title<-emp_publication_wrap(title,w-8,font)
  args$main<-title
  rows<-args$labels_row %||% rownames(mat) %||% as.character(seq_len(nr))
  cols<-args$labels_col %||% colnames(mat) %||% as.character(seq_len(nc))
  label_height<-if(isFALSE(args$show_colnames))0 else min(35,max(nchar(cols),na.rm=TRUE)*font*25.4/72*.55)
  row_capacity<-max(1L,floor((h-12-length(strsplit(title,'\n',fixed=TRUE)[[1]])*font*25.4/72*1.3-label_height)/(font*25.4/72*1.25)))
  label_width<-if(isFALSE(args$show_rownames))0 else min(38,max(nchar(rows),na.rm=TRUE)*font*25.4/72*.55)
  auto_side<-if(w>=100&&w/h>1.2)'right' else 'bottom'
  resolve<-function(value){if(is.null(value)||!nzchar(value))return(if(full_auto)auto_side else 'right');if(value=='auto')auto_side else value}
  positions<-list(scale=resolve(appearance$scale_position),annotation=resolve(appearance$annotation_position))
  bottom_legends<-any(unlist(positions)%in%c('top','bottom'))
  legend_width<-if(bottom_legends||isFALSE(args$legend)&&isFALSE(args$annotation_legend))0 else if(full_auto)max(8,min(20,w*.22)) else 27
  tree_width<-if(isFALSE(args$cluster_rows))0 else if(full_auto)(args$treeheight_row %||% 40)*25.4/72 else 14
  if(automatic&&!full_auto&&(w < label_width+legend_width+tree_width+18 || h < 35)) {
    stop(sprintf('Publication layout too small / 投稿画布过小: %.1f × %.1f mm at %g pt. Use at least %.0f mm width and 60 mm height, hide row labels, or choose a wider A4 panel. / 请扩大图块或关闭行名。',w,h,font,label_width+legend_width+tree_width+20))
  }
  thin<-function(labels,capacity,kind,order=seq_along(labels)){
    if(!automatic)return(labels)
    active<-order[!is.na(labels[order])&nzchar(labels[order])];if(length(active)<=capacity)return(labels)
    if(profile$label_mode=='strict')stop(sprintf('Publication labels too dense / 标签过密: %d %s labels at %g pt; capacity %d. Enlarge the canvas or choose automatic label spacing.',length(active),kind,font,capacity))
    keep<-active[unique(round(seq(1,length(active),length.out=capacity)))];out<-rep('',length(labels));out[keep]<-labels[keep]
    emp_publication_note(sprintf('%s labels: %d / %d shown at %g pt; all %d data rows/columns retained. / 已间隔显示标签，数据全部保留。',kind,length(keep),length(active),font,length(labels)))
    out
  }
  # pheatmap computes absolute grob extents using the active graphics device.
  # Build at the target size instead of R's default 7-inch device.
  tmp<-tempfile(fileext='.pdf');on.exit(unlink(tmp),add=TRUE)
  if(capabilities('aqua'))grDevices::quartz(type='pdf',file=tmp,width=size$width,height=size$height) else grDevices::pdf(tmp,width=size$width,height=size$height)
  device<-grDevices::dev.cur();on.exit(grDevices::dev.off(device),add=TRUE)
  args$silent<-TRUE
  out<-do.call(pheatmap::pheatmap,args)
  # Select labels in their final clustered order, so neighbouring labels remain
  # separated even when the clustering permutes the original input rows.
  row_order<-if(inherits(out$tree_row,'hclust'))out$tree_row$order else seq_len(nr)
  col_order<-if(inherits(out$tree_col,'hclust'))out$tree_col$order else seq_len(nc)
  # Final matrix dimensions, after legend placement, determine label capacity.
  if(!isFALSE(args$show_rownames))args$labels_row<-rows
  col_capacity<-max(1L,floor((w-label_width-legend_width-tree_width)/(font*25.4/72*1.25)))
  if(!isFALSE(args$show_colnames))args$labels_col<-cols
  if(is.matrix(args$display_numbers)&&!is.null(args$labels_row)) {
    hidden<-!nzchar(args$labels_row)
    if(any(hidden)){args$display_numbers[hidden,]<-'';emp_publication_note('Cell annotations spaced with row labels; full statistics and matrix retained. / 单元格标注随行标签间隔显示，统计表与矩阵完整保留。')}
  }
  if(inherits(out$tree_row,'hclust'))args$cluster_rows<-out$tree_row
  if(inherits(out$tree_col,'hclust'))args$cluster_cols<-out$tree_col
  out<-do.call(pheatmap::pheatmap,args)
  place<-function(out)emp_publication_heatmap_place_legends(out,positions,w,h,appearance$legend_font %||% font,font)
  out<-place(out)
  cell<-out$gtable$layout[out$gtable$layout$name=='matrix',,drop=FALSE]
  if(nrow(cell)) {
    mw<-w-grid::convertWidth(sum(out$gtable$widths),'mm',valueOnly=TRUE)
    mh<-h-grid::convertHeight(sum(out$gtable$heights),'mm',valueOnly=TRUE)
    if(automatic&&mw>0&&mh>0) {
      if(!isFALSE(args$show_rownames))args$labels_row<-thin(rows,max(1L,floor(mh/(font*25.4/72*1.25))),'Feature',row_order)
      if(!isFALSE(args$show_colnames))args$labels_col<-thin(cols,max(1L,floor(mw/(font*25.4/72*1.25))),'Sample',col_order)
      if(is.matrix(args$display_numbers)&&!is.null(args$labels_row))args$display_numbers[!nzchar(args$labels_row),]<-''
      out<-place(do.call(pheatmap::pheatmap,args))
      cell<-out$gtable$layout[out$gtable$layout$name=='matrix',,drop=FALSE]
      mw<-w-grid::convertWidth(sum(out$gtable$widths),'mm',valueOnly=TRUE)
      mh<-h-grid::convertHeight(sum(out$gtable$heights),'mm',valueOnly=TRUE)
    }
    if(!automatic){
      if(mw<=0)out$gtable$widths[cell$l[1]]<-grid::unit(1,'mm')
      if(mh<=0)out$gtable$heights[cell$t[1]]<-grid::unit(1,'mm')
    }
    if(automatic&&(if(full_auto)mw<=0||mh<=0 else mw<15||mh<10))stop(sprintf('Publication layout too small / 投稿画布无法容纳图例和标签: matrix area %.1f × %.1f mm. Choose a wider or taller A4 panel; fonts remain %g pt.',mw,mh,font))
  }
  # pheatmap scales its main heading by 1.3 by default; keep headings controlled.
  out$gtable<-emp_publication_text_grob(out$gtable,font)
  for(i in seq_along(out$gtable$grobs)) {
    name<-out$gtable$layout$name[i];grob<-out$gtable$grobs[[i]]
    rolefont<-if(name=='main')appearance$title_font else if(grepl('legend',name))appearance$legend_font else if(name=='matrix')appearance$label_font else NULL
    if(!is.null(rolefont))grob<-emp_publication_text_grob(grob,rolefont)
    if(!is.null(appearance$family))grob<-emp_publication_grob_style(grob,family=appearance$family)
    if(name%in%c('row_tree','col_tree')&&!is.null(appearance$tree_line))grob<-emp_publication_grob_style(grob,lwd=appearance$tree_line/.75)
    if(name=='matrix'&&!is.null(appearance$cell_line))grob<-emp_publication_grob_style(grob,lwd=appearance$cell_line/.75,border=if(appearance$cell_line>0)'grey80' else NA)
    out$gtable$grobs[[i]]<-grob
  }
  # Read physical strokes from the final heatmap grobs (dense maps may omit borders).
  read_stroke<-function(g){
    values<-numeric()
    if(inherits(g,c('rect','segments','polyline','lines'))){col<-g$gp$col;values<-if(!is.null(col)&&all(is.na(col)))0 else (g$gp$lwd %||% 1)*.75}
    c(values,unlist(lapply(g$grobs,read_stroke)),unlist(lapply(g$children,read_stroke)))
  }
  values<-list(scale_position=positions$scale,annotation_position=positions$annotation,title_font=appearance$title_font %||% font,legend_font=appearance$legend_font %||% font,label_font=appearance$label_font %||% font,family=appearance$family %||% 'sans',palette=getOption('emp.color_panel','npg'),dpi=size$dpi)
  for(key in c('cell_line','tree_line')) {
    indices<-which(out$gtable$layout$name %in% if(key=='cell_line')'matrix' else c('row_tree','col_tree'))
    widths<-unlist(lapply(out$gtable$grobs[indices],read_stroke));if(length(widths))values[[key]]<-max(widths)
  }
  if(!is.null(args$color)&&length(args$color)>1L)values$custom_colors<-paste(args$color[unique(round(seq(1,length(args$color),length.out=3)))],collapse=',')
  if(!is.null(appearance$custom_colors))values$custom_colors<-appearance$custom_colors
  options(emp.figure_effective=values)
  out
}

emp_publication_svg <- function(p, path, width, height) {
  withr::local_options(list(emp.figure_format='svg'))
  if (!is.null(emp_publication_profile())) withr::local_seed(108L)
  if(!requireNamespace('svglite',quietly=TRUE))stop('SVG export requires svglite')
  size<-emp_figure_size(width,height)
  svglite::svglite(path,width=size$width,height=size$height,bg='white')
  device<-grDevices::dev.cur();on.exit(grDevices::dev.off(device),add=TRUE)
  .viz_draw_plot(emp_publication_plot(p,size$width,size$height))
  path
}
emp_publication_export <- function(p,path,width=9,height=6,dpi=300) {
  ext<-tolower(tools::file_ext(path));dir.create(dirname(path),recursive=TRUE,showWarnings=FALSE)
  if(ext=='pdf')return(save_plot_pdf(p,path,width,height,archive=FALSE))
  if(ext=='svg')return(emp_publication_svg(p,path,width,height))
  if(ext=='png'){writeBin(base64enc::base64decode(plot_to_base64(p,width,height,dpi)),path);return(path)}
  stop('Unsupported publication figure format')
}

# Export frozen workbench coordinates/values, never recompute an analysis.
emp_publication_workbench <- function(b, principal) {
  st<-emp_assert_job_owner(b$job_id,principal)
  if(!identical(st$status,'done') || !identical(st$kind,'count_workbench'))stop('Unsupported or incomplete workbench job')
  result<-get_job_result(b$job_id)
  kind<-b$kind %||% ''
  if(!kind %in% c('pca','heatmap'))stop('Unsupported workbench figure')
  size<-emp_figure_size(180/25.4,120/25.4)
  if(kind=='pca') {
    a<-result$artifacts$pca
    if(is.null(a$scores))stop('PCA result is unavailable')
    data<-if(is.data.frame(a$scores))a$scores else do.call(rbind,lapply(a$scores,as.data.frame,stringsAsFactors=FALSE))
    for(key in c('PC1','PC2'))data[[key]]<-as.numeric(data[[key]])
    p<-ggplot2::ggplot(data,ggplot2::aes(PC1,PC2,color=group))+ggplot2::geom_point(size=2)+ggplot2::labs(title='PCA · frozen count-workbench result',x=sprintf('PC1 (%.1f%%)',100*a$variance_explained[[1]]),y=sprintf('PC2 (%.1f%%)',100*a$variance_explained[[2]]),color='Group')+ggplot2::theme_bw()
  } else {
    a<-result$artifacts$heatmap
    if(is.null(a$values))stop('Heatmap result is unavailable')
    mat<-do.call(rbind,lapply(a$values,function(row)as.numeric(unlist(row))))
    dimnames(mat)<-list(unlist(a$feature_ids),unlist(a$sample_ids))
    p<-emp_publication_pheatmap(mat,scale='none',color=grDevices::colorRampPalette(c('#2166ac','white','#b2182b'))(256),breaks=seq(-2.5,2.5,length.out=257),main='High-variance features\nRow z-score; display clipped at ±2.5',publication_width=size$width,publication_height=size$height,silent=TRUE)
  }
  dir<-tempfile('emp-workbench-figure-');dir.create(dir);on.exit(unlink(dir,recursive=TRUE),add=TRUE)
  files<-lapply(c('pdf','svg'),function(ext){path<-file.path(dir,paste0(kind,'.',ext));emp_publication_export(p,path,size$width,size$height);base64enc::base64encode(path)})
  list(success=TRUE,pdf_base64=files[[1]],svg_base64=files[[2]],width_mm=size$width*25.4,height_mm=size$height*25.4,source_job=b$job_id,kind=kind,analysis_recomputed=FALSE)
}

emp_publication_floor_grob <- function(grob, minimum, default) {
  if(inherits(grob,'text')) {
    font<-grob$gp$fontsize %||% default
    font<-font*(grob$gp$cex %||% 1)
    script_depth<-emp_publication_math_depth(grob$label)
    grob$gp$fontsize<-pmax(minimum/(.7^script_depth),font);grob$gp$cex<-NULL
  }
  if(!is.null(grob$grobs))grob$grobs<-lapply(grob$grobs,emp_publication_floor_grob,minimum=minimum,default=default)
  if(!is.null(grob$children))for(i in seq_along(grob$children))grob$children[[i]]<-emp_publication_floor_grob(grob$children[[i]],minimum,default)
  grob
}
emp_publication_guide_bounds <- function(grob,width,height) {
  positions<-which(grepl('^guide-box',grob$layout$name))
  lapply(positions,function(i){
    guide<-grob$grobs[[i]];if(inherits(guide,'zeroGrob'))return(NULL)
    row<-grob$layout[i,,drop=FALSE]
    span<-function(units,first,last,total,dimension){
      convert<-if(dimension=='width')grid::convertWidth else grid::convertHeight
      fixed<-convert(sum(units), 'mm',valueOnly=TRUE)
      types<-grid::unitType(units);null<-which(types=='null');weights<-vapply(null,function(j)as.numeric(units[j]),numeric(1))
      inside<-null>=first & null<=last
      convert(sum(units[first:last]),'mm',valueOnly=TRUE)+if(length(weights)&&sum(weights)>0)max(0,total-fixed)*sum(weights[inside])/sum(weights) else 0
    }
    list(name=grob$layout$name[i],width=grid::convertWidth(grid::grobWidth(guide),'mm',valueOnly=TRUE),height=grid::convertHeight(grid::grobHeight(guide),'mm',valueOnly=TRUE),available_width=span(grob$widths,row$l,row$r,width,'width'),available_height=span(grob$heights,row$t,row$b,height,'height'))
  })
}
# Complete categorical labels, measured on the final export device. Row spacing
# reflects wrapped text height; every ID, point and full label remains present.
emp_publication_fit_enrichment <- function(p,width_mm,height_mm) {
  full<-attr(p,'emp.enrichment_labels');profile<-emp_publication_profile()
  if(is.null(full)||is.null(profile))return(p)
  automatic<-isTRUE(profile$auto_params);a<-profile$appearance %||% list()
  font<-a$axis_font %||% profile$font_pt;family<-a$family %||% 'sans';fm<-font*25.4/72
  measure<-function(text)grid::convertWidth(grid::grobWidth(grid::textGrob(text,gp=grid::gpar(fontsize=font,fontfamily=family))),'mm',valueOnly=TRUE)
  budget<-max(1,width_mm*.39)
  wrap_limit<-if(automatic)Inf else attr(p,'emp.enrichment_wrap') %||% 45
  wrap_text<-function(text){
    # Wrap at word boundaries, splitting only identifiers longer than a column.
    paragraphs<-strsplit(text,'\n',fixed=TRUE)[[1]]
    result<-unlist(lapply(paragraphs,function(paragraph){
      words<-strsplit(trimws(paragraph),'[[:space:]]+')[[1]];out<-character();line<-''
      fits<-function(x)nchar(x)<=wrap_limit&&measure(x)<=budget
      for(word in words){
        candidate<-if(nzchar(line))paste(line,word) else word
        if(fits(candidate)){line<-candidate;next}
        if(nzchar(line)){out<-c(out,line);line<-''}
        if(fits(word)){line<-word;next}
        for(ch in strsplit(word,'',fixed=TRUE)[[1]]){if(nzchar(line)&&!fits(paste0(line,ch))){out<-c(out,line);line<-ch}else line<-paste0(line,ch)}
      }
      c(out,line)
    }),use.names=FALSE)
    paste(result,collapse='\n')
  }
  labels<-vapply(full,wrap_text,character(1));n<-length(full)
  # Use short, conventional guide headings, retaining the exact colour metric.
  horizontal<-(p$theme$legend.position %||% 'right')%in%c('top','bottom')
  colors<-ggplot2::ggplot_build(p)$plot$scales$get_scales('colour')
  if(!is.null(colors)&&!colors$is_discrete()){
    colors<-colors$clone();limits<-range(p$data$neg_log10_padj,finite=TRUE)
    colors$breaks<-unique(seq(limits[1],limits[2],length.out=3));colors$labels<-function(x)format(signif(x,3),trim=TRUE)
    p<-suppressMessages(p+colors)
  }
  p<-p+ggplot2::labs(x='Gene ratio',color='−log10\n(p.adjust)',size='Count',caption=NULL)+
    ggplot2::guides(colour=ggplot2::guide_colorbar(display=if(identical(getOption('emp.figure_format'),'png')||grepl('png',names(grDevices::dev.cur()),ignore.case=TRUE))'raster' else 'rectangles',direction=if(horizontal)'horizontal' else 'vertical',barwidth=grid::unit(if(horizontal)width_mm*.38 else max(2,fm*1.2),'mm'),barheight=grid::unit(if(horizontal)max(2,fm) else min(35,height_mm*.3),'mm'),title.position='top',order=1),size=ggplot2::guide_legend(nrow=if(horizontal)1 else NULL,ncol=if(horizontal)NULL else 1,title.position='top',order=2))+
    ggplot2::theme(legend.box='vertical',axis.text.y=ggplot2::element_text(size=font,lineheight=1.2,margin=ggplot2::margin(r=3)),plot.margin=ggplot2::margin(6,8,6,6))
  if(automatic){
    maximum<-max(.25,min(4,fm*.95))
    p<-suppressMessages(p+ggplot2::scale_size_area(max_size=maximum,breaks=unique(round(seq(min(p$data$Count),max(p$data$Count),length.out=3)))))
  }
  p<-p+ggplot2::scale_x_continuous(expand=ggplot2::expansion(mult=c(.10,.16)))
  built<-ggplot2::ggplot_build(p);diameters<-built$data[[1]]$size
  heights<-vapply(labels,function(text)max(grid::convertHeight(grid::grobHeight(grid::textGrob(text,gp=grid::gpar(fontsize=font,fontfamily=family,lineheight=1.2))),'mm',valueOnly=TRUE),length(strsplit(text,'\n',fixed=TRUE)[[1]])*fm*1.2),numeric(1))+max(.8,fm*.35)
  if(length(diameters)==n)heights<-pmax(heights,diameters+max(.6,fm*.25))
  centers<-sum(heights)-cumsum(heights)+heights/2;names(centers)<-names(full)
  p$data$.enrich_y<-unname(centers[as.character(p$data$ID)])
  p$mapping$y<-ggplot2::aes(y=.enrich_y)$y
  p$layers<-lapply(p$layers,function(layer){copy<-ggplot2::ggproto(NULL,layer);if(is.data.frame(copy$data)&&'ID'%in%names(copy$data))copy$data$.enrich_y<-unname(centers[as.character(copy$data$ID)]);copy})
  p<-suppressMessages(p+ggplot2::scale_y_continuous(limits=c(0,sum(heights)),breaks=unname(centers),labels=unname(labels),expand=c(0,0)))
  g<-ggplot2::ggplotGrob(p)
  # Allocate real space for titles, axes and both guides before drawing.
  fixed_w<-grid::convertWidth(sum(g$widths),'mm',valueOnly=TRUE)
  fixed_h<-grid::convertHeight(sum(g$heights),'mm',valueOnly=TRUE)
  available_w<-width_mm-fixed_w;available_h<-height_mm-fixed_h
  bounds<-Filter(Negate(is.null),emp_publication_guide_bounds(g,width_mm,height_mm))
  guide_deficit<-max(c(0,vapply(bounds,function(b)b$height-b$available_height,numeric(1))))
  missing_w<-max(0,15-available_w);missing_h<-max(0,sum(heights)-available_h,guide_deficit)
  if(missing_w>.1||missing_h>.1){
    # The chosen dimensions and fonts are never changed without user action.
    recommended<-list(width_mm=if(missing_w>.1)ceiling(width_mm+missing_w+10) else width_mm,height_mm=ceiling(height_mm+missing_h+6))
    if(recommended$width_mm>width_mm&&automatic)recommended$height_mm<-ceiling(recommended$height_mm*1.3)
    message<-sprintf('完整名称与图例需要更多空间；当前 %.1f × %.1f mm、%g pt。建议至少 %g × %g mm，或手动减小字号 / 增大换行宽度。未生成裁切图。 / Complete labels need more space; suggested canvas %g × %g mm.',width_mm,height_mm,font,recommended$width_mm,recommended$height_mm,recommended$width_mm,recommended$height_mm)
    stop(structure(list(message=message,call=NULL,suggestion=recommended),class=c('emp_figure_layout_error','error','condition')))
  }
  effective<-getOption('emp.figure_effective',list());effective$label_wrap<-max(vapply(strsplit(labels,'\n',fixed=TRUE),function(parts)max(nchar(parts)),integer(1)));effective$label_count<-n;effective$label_max_lines<-max(lengths(strsplit(labels,'\n',fixed=TRUE)));effective$label_complete<-TRUE
  effective$point_size_range<-range(diameters,finite=TRUE);effective$max_point_size<-max(diameters)
  options(emp.figure_effective=effective)
  attr(p,'emp.enrichment_layout')<-list(labels=labels,centers=centers,row_heights=heights,panel_height=available_h,panel_width=available_w,guide_bounds=bounds)
  p
}
emp_publication_draw_ggplot <- function(p) {
  grid::grid.newpage()
  profile<-emp_publication_profile();size<-grDevices::dev.size('in')*25.4
  build<-function(plot)if(inherits(plot,'patchwork'))patchwork::patchworkGrob(plot) else ggplot2::ggplotGrob(plot)
  p<-emp_publication_fit_enrichment(p,size[1],size[2])
  grob<-build(p)
  if(identical(profile$label_mode,'auto')&&!inherits(p,'patchwork')) {
    for(columns in 1L) {
      bounds<-Filter(Negate(is.null),emp_publication_guide_bounds(grob,size[1],size[2]))
      overflow<-vapply(bounds,function(g)g$width>g$available_width+.1,logical(1))
      if(!any(overflow))break
      # Retain one top-to-bottom column; fitting must not reflow categories horizontally.
      built<-ggplot2::ggplot_build(p)
      for(aesthetic in c('colour','fill','shape','linetype')) {
        scale<-built$plot$scales$get_scales(aesthetic)
        if(!is.null(scale)&&scale$is_discrete()) {
          guide<-list(ggplot2::guide_legend(ncol=columns,byrow=TRUE,title.position='top'));names(guide)<-aesthetic
          p<-p+do.call(ggplot2::guides,guide)
        }
      }
      grob<-build(p)
      emp_publication_note(sprintf('Auto legend: fitted to the canvas using %d column(s); all legend entries retained. / 图例按 %d 列适配画布，保留所有类别。',columns,columns))
    }
  }
  if(!identical(profile$label_mode,'manual')&&!inherits(p,'patchwork')) {
    # Null units represent the plotting body. Reserve the actual text/legend size.
    available_w<-size[1]-grid::convertWidth(sum(grob$widths),'mm',valueOnly=TRUE)
    available_h<-size[2]-grid::convertHeight(sum(grob$heights),'mm',valueOnly=TRUE)
    if(available_w<12||available_h<10)stop(sprintf('Publication layout too small / 投稿画布无法容纳文字: plot body %.1f × %.1f mm. Choose a larger A4 panel; text remains at least %g pt.',available_w,available_h,profile$min_font_pt))
  }
  if(!identical(profile$label_mode,'manual'))grob<-emp_publication_floor_grob(grob,profile$min_font_pt,profile$font_pt)
  grid::grid.draw(grob)
  invisible(grob)
}

emp_publication_math_depth <- function(label) {
  depth<-function(x) {
    if(is.expression(x))return(max(c(0L,vapply(as.list(x),depth,integer(1)))))
    if(!is.call(x))return(0L)
    name<-as.character(x[[1]])[1];args<-as.list(x)[-1]
    if(!length(args))return(0L)
    values<-vapply(args,depth,integer(1))
    if(name %in% c('[','^')&&length(values)>1L)values[-1]<-values[-1]+1L
    as.integer(max(values))
  }
  depth(label)
}


emp_publication_use_type <- function(name) {
  old<-getOption('emp.viz_style',NULL);profiles<-old$figure_profiles
  if(is.null(profiles))return(old)
  kind<-if(grepl('deg.*heatmap',name))'deg_heatmap' else if(grepl('heatmap',name))'heatmap' else if(grepl('volcano',name))'volcano' else if(grepl('pca|scatter|ordination|pcoa|nmds',name))'scatter' else if(grepl('gsea|running_es',name))'gsea' else if(grepl('enrich|dotplot',name))'enrichment' else if(grepl('boxplot',name))'boxplot' else if(grepl('alpha|diversity',name))'alpha' else if(grepl('network',name))'network' else if(grepl('sankey',name))'sankey' else if(grepl('structure|composition|taxonomy',name))'structure' else 'barplot'
  profile<-profiles[[kind]]
  if(!is.null(profile))options(emp.viz_style=utils::modifyList(old,profile))
  old
}

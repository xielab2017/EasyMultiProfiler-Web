# Group overlays and exploratory tests on frozen ordination coordinates.
# No distance matrix, embedding, or original assay is recomputed here.
.ord_axis_tests <- function(d, axes, requested='auto') {
  if(!requested %in% c('auto','rank','welch','none'))stop('Invalid axis test')
  ok<-!d$group_missing
  counts<-table(d$group[ok]);ng<-length(counts)
  result<-lapply(seq_along(axes),function(i){
    values<-d[[c('x','y')[i]]][ok];groups<-factor(d$group[ok])
    method<-if(requested=='none')'Disabled' else if(requested=='welch')if(ng==2)'Welch t-test' else 'Welch one-way test' else if(ng==2)'Wilcoxon rank-sum' else 'Kruskal-Wallis'
    reason<-if(requested=='none')'Disabled by user' else if(ng<2)'At least two known groups required' else if(any(counts<2))'At least two observations in every known group required' else if(length(unique(values))<2)'All projected values are identical' else ''
    p<-NA_real_;statistic<-NA_real_
    if(!nzchar(reason)){
      test<-tryCatch(suppressWarnings(if(requested=='welch'){
        if(ng==2)stats::t.test(values~groups,var.equal=FALSE) else stats::oneway.test(values~groups,var.equal=FALSE)
      }else if(ng==2)stats::wilcox.test(values~groups,exact=FALSE,correct=TRUE) else stats::kruskal.test(values,groups)),error=identity)
      if(inherits(test,'error'))reason<-conditionMessage(test) else if(!is.finite(test$p.value))reason<-'Test is not estimable for these coordinates' else {p<-test$p.value;statistic<-unname(test$statistic)}
    }
    data.frame(axis=axes[i],method=method,statistic=statistic,p_value=p,p_adjusted=NA_real_,adjustment='BH (two selected axes)',n=sum(ok),n_missing=sum(!ok),n_groups=ng,group_counts=paste(names(counts),as.integer(counts),sep='=',collapse='; '),status=if(nzchar(reason))reason else 'Exploratory; independent samples assumed',stringsAsFactors=FALSE)
  })
  result<-do.call(rbind,result);finite<-is.finite(result$p_value)
  if(any(finite))result$p_adjusted[finite]<-stats::p.adjust(result$p_value[finite],method='BH',n=2)
  result
}

.ord_pairwise <- function(d, axes, requested='auto', mode='all', reference='') {
  if(!mode %in% c('all','reference','none'))stop('Invalid pairwise comparison mode')
  empty<-data.frame(axis=character(),group_1=character(),group_2=character(),method=character(),n_1=integer(),n_2=integer(),statistic=numeric(),p_value=numeric(),p_adjusted=numeric(),adjustment=character(),status=character())
  groups<-sort(unique(d$group[!d$group_missing]))
  if(mode=='none'||requested=='none'||length(groups)<2)return(empty)
  pairs<-utils::combn(groups,2,simplify=FALSE)
  if(mode=='reference'){
    if(!nzchar(reference))reference<-groups[1]
    if(!reference %in% groups)stop('Pairwise reference group is absent from saved labels')
    pairs<-Filter(function(x)reference %in% x,pairs)
  }
  rows<-list()
  for(i in seq_along(axes))for(pair in pairs){
    a<-d[[c('x','y')[i]]][!d$group_missing&d$group==pair[1]];b<-d[[c('x','y')[i]]][!d$group_missing&d$group==pair[2]]
    reason<-if(min(length(a),length(b))<2)'At least two observations in each compared group required' else if(length(unique(c(a,b)))<2)'All projected values are identical' else ''
    p<-statistic<-NA_real_
    if(!nzchar(reason)){
      test<-tryCatch(suppressWarnings(if(requested=='welch')stats::t.test(a,b,var.equal=FALSE) else stats::wilcox.test(a,b,exact=FALSE,correct=TRUE)),error=identity)
      if(inherits(test,'error'))reason<-conditionMessage(test) else if(!is.finite(test$p.value))reason<-'Test is not estimable' else {p<-test$p.value;statistic<-unname(test$statistic)}
    }
    rows[[length(rows)+1L]]<-data.frame(axis=axes[i],group_1=pair[1],group_2=pair[2],method=if(requested=='welch')'Welch t-test' else 'Wilcoxon rank-sum',n_1=length(a),n_2=length(b),statistic=statistic,p_value=p,p_adjusted=NA_real_,adjustment='BH (all requested pairs across both axes)',status=if(nzchar(reason))reason else 'Exploratory; independent samples assumed',stringsAsFactors=FALSE)
  }
  result<-do.call(rbind,rows);finite<-is.finite(result$p_value)
  if(any(finite))result$p_adjusted[finite]<-stats::p.adjust(result$p_value[finite],method='BH',n=nrow(result))
  result
}

.ord_ellipses <- function(d, type='confidence', level=.95) {
  if(!type %in% c('confidence','spread','none'))stop('Invalid ellipse type')
  level<-.af_num(level,.95,.Machine$double.eps,1-.Machine$double.eps)
  groups<-unique(d$group[!d$group_missing]);out<-list();audit<-list()
  for(group in groups){
    z<-as.matrix(d[d$group==group&!d$group_missing,c('x','y')]);n<-nrow(z);reason<-''
    if(type=='none')reason<-'Disabled by user' else if(n<3)reason<-'At least three non-collinear observations required'
    if(!nzchar(reason)){
      covariance<-stats::cov(z);e<-eigen(covariance,symmetric=TRUE)
      if(any(!is.finite(e$values))||min(e$values)<=max(e$values)*1e-10||max(e$values)<=0)reason<-'Singular covariance; no ellipse drawn'
    }
    if(!nzchar(reason)){
      # (mu - mean)' S^-1 (mu - mean) <= 2(n-1)/(n(n-2)) F(2,n-2).
      radius2<-if(type=='confidence')2*(n-1)/(n*(n-2))*stats::qf(level,2,n-2) else stats::qchisq(level,2)
      theta<-seq(0,2*pi,length.out=181)
      xy<-cbind(cos(theta),sin(theta))%*%diag(sqrt(e$values*radius2),2)%*%t(e$vectors)
      xy<-sweep(xy,2,colMeans(z),'+')
      out[[length(out)+1L]]<-data.frame(x=xy[,1],y=xy[,2],group=group)
    }
    audit[[length(audit)+1L]]<-list(group=group,n=n,type=type,level=level,drawn=!nzchar(reason),reason=reason)
  }
  list(data=if(length(out))do.call(rbind,out) else data.frame(x=numeric(),y=numeric(),group=character()),audit=audit,type=type,level=level)
}

.ord_p <- function(p)if(!is.finite(p))'NA' else format.pval(p,digits=2,eps=1e-4)
.ord_p_label<-function(name,p)paste0(name,if(is.finite(p)&&p<1e-4)'<1e-4' else paste0('=',.ord_p(p)))

emp_ordination_figure <- function(d, b, axes, axis_labels, title) {
  grouped<-nzchar(b$group %||% '')
  scope<-b$test_scope %||% 'replicated';if(!scope %in% c('replicated','all'))stop('Invalid test group scope')
  counts<-table(d$group[!d$group_missing]);excluded_groups<-if(grouped&&scope=='replicated')names(counts)[counts<2] else character();excluded<-!d$group_missing&d$group%in%excluded_groups;test_d<-d[!excluded,,drop=FALSE]
  tests<-.ord_axis_tests(test_d,axes,if(grouped)b$axis_test %||% 'auto' else 'none');tests$n_excluded<-sum(excluded);tests$excluded_groups<-paste(excluded_groups,collapse='; ')
  pairwise<-.ord_pairwise(test_d,axes,if(grouped)b$axis_test %||% 'auto' else 'none',if(grouped)b$pairwise_mode %||% 'all' else 'none',b$pairwise_reference %||% '')
  pair_labels<-b$pairwise_labels %||% 'p';if(!pair_labels %in% c('p','q','both'))stop('Invalid pairwise label choice')
  pair_max<-as.integer(.af_num(b$pairwise_max,6,1,190))
  ellipses<-.ord_ellipses(d,if(grouped)b$ellipse_type %||% 'spread' else 'none',b$ellipse_level %||% .95)
  opacity<-.af_num(b$ellipse_alpha,.14,0,1)
  appearance<-emp_publication_profile()$appearance %||% list();font<-emp_publication_profile()$font_pt %||% 10
  levels<-sort(unique(d$group[!d$group_missing]));d$.ord_group<-factor(ifelse(d$group_missing,NA,d$group),levels=levels)
  colors<-if(!is.null(appearance$custom_colors))trimws(strsplit(appearance$custom_colors,',',fixed=TRUE)[[1]]) else emp_pub_palette(max(1,length(levels)),appearance$palette %||% 'npg')
  colors<-stats::setNames(rep_len(colors,length(levels)),levels)
  group_counts<-table(d$group[!d$group_missing]);label<-function(v)ifelse(is.na(v),paste0('Missing (n=',sum(d$group_missing),')'),paste0(v,' (n=',as.integer(group_counts[v]),')'))
  scales<-list(ggplot2::scale_fill_manual(values=colors,na.value='#B8BDC7',labels=label,name=if(grouped)b$group else NULL),ggplot2::scale_color_manual(values=colors,na.value='#B8BDC7',guide='none'))
  p<-ggplot2::ggplot(d,ggplot2::aes(x,y,fill=.ord_group))
  if(nrow(ellipses$data))p<-p+ggplot2::geom_polygon(data=ellipses$data,ggplot2::aes(x,y,fill=group,color=group,group=group),inherit.aes=FALSE,alpha=opacity,linewidth=.5,show.legend=FALSE)
  # White outlines and translucent regions give separation while preserving 2D coordinates.
  p<-p+ggplot2::geom_point(data=d[order(d$group_missing,decreasing=TRUE),,drop=FALSE],shape=21,color='white',stroke=.3,size=2.6,alpha=.94)+scales[seq_len(if(nrow(ellipses$data))2 else 1)]+ggplot2::labs(x=axis_labels[1],y=axis_labels[2])+emp_pub_theme(base_size=font)
  if(!grouped)p<-p+ggplot2::guides(fill='none')
  if(isTRUE(b$labels))p<-p+ggrepel::geom_text_repel(ggplot2::aes(label=sample),seed=1,max.overlaps=Inf,show.legend=FALSE,color='grey20')
  notes<-character()
  if(grouped){
    counts<-table(d$group[!d$group_missing]);notes<-paste('Known groups / 已知分组:',paste(names(counts),as.integer(counts),sep=' n=',collapse='; '))
    if(any(d$group_missing))notes<-c(notes,sprintf('%d missing group labels: points retained in gray; excluded from ellipses and axis tests. / %d 个分组缺失点保留为灰色，不参与椭圆和检验。',sum(d$group_missing),sum(d$group_missing)))
    skipped<-vapply(ellipses$audit,function(x)!x$drawn&&x$type!='none',logical(1))
    if(any(skipped))notes<-c(notes,paste('Ellipse unavailable / 无法绘制椭圆:',paste(vapply(ellipses$audit[skipped],function(x)paste0(x$group,' (n=',x$n,'): ',x$reason),character(1)),collapse='; ')))
    if(ellipses$type!='none')notes<-c(notes,if(ellipses$type=='confidence')sprintf('%.1f%% group-mean confidence ellipses (Hotelling, normality assumption); not sample coverage.',100*ellipses$level) else sprintf('%.1f%% normal data ellipses; dispersion display, not a mean confidence interval.',100*ellipses$level))
  }else notes<-'Select a known sample grouping to enable ellipses and axis comparisons. / 选择样本分组后启用椭圆和轴向比较。'
  if(grouped&&(b$axis_test %||% 'auto')!='none')notes<-c(notes,'Axis tests are exploratory on learned coordinates; independent samples assumed. BH correction covers the two selected axes only. / 轴向检验为探索性结果，假定样本独立；BH 仅校正本次两条坐标轴。')
  if(length(excluded_groups))notes<-c(notes,paste('Tests exclude non-replicated groups (points retained) / 检验排除无重复样本组，点仍保留:',paste(excluded_groups,counts[excluded_groups],sep=' n=',collapse='; ')))
  annotation_info<-list(shown_per_axis=0,total_per_axis=nrow(pairwise)/2,reason='Projections disabled')
  projection<-grouped&&any(!d$group_missing)&&!identical(b$axis_projections,FALSE)
  if(projection){
    # Shared numeric limits keep the marginal projections aligned with the scatter.
    limits<-function(a,extra){r<-range(c(a,extra),finite=TRUE);pad<-max(diff(r)*.04,.Machine$double.eps*max(1,abs(r)));r+c(-pad,pad)}
    xr<-limits(d$x,ellipses$data$x);yr<-limits(d$y,ellipses$data$y)
    size<-emp_figure_size(180/25.4,160/25.4);font_mm<-font*25.4/72;body_mm<-max(font_mm*14,size$height*25.4-font_mm*7-8);top_mm<-max(length(levels)*font_mm*1.6,font_mm*6)+font_mm*2.5+3;main_mm<-max(font_mm*10,body_mm-top_mm);panel_mm<-max(font_mm*6,main_mm-font_mm*4.5);label_gap<-font_mm*if(pair_labels=='both')2.6 else 1.5;label_pad<-font_mm*1.5
    brackets<-lapply(axes,function(axis){
      z<-head(pairwise[pairwise$axis==axis,,drop=FALSE],pair_max)
      z$start<-match(z$group_1,levels);z$end<-match(z$group_2,levels)
      z$label<-vapply(seq_len(nrow(z)),function(i)switch(pair_labels,p=.ord_p(z$p_value[i]),q=.ord_p(z$p_adjusted[i]),both=paste(.ord_p(z$p_value[i]),.ord_p(z$p_adjusted[i]),sep='\n')),character(1));z
    })
    needed<-24+4*max(vapply(brackets,nrow,integer(1)));fit<-min(size$width,size$height)*25.4/font_mm>=needed
    if(!fit&&nrow(pairwise)){brackets<-lapply(brackets,function(z)z[FALSE,,drop=FALSE]);notes<-c(notes,'Compact canvas: overall P remains beside each projection; full pairwise P/BH table is shown below and in PAIRWISE. Enlarge the canvas or reduce annotation text to add brackets. / 当前画布以完整分布及总体 P 为主，两两比较完整表显示于下方和 PAIRWISE；可增大尺寸或调小标注字号显示括号。')}
    annotation_info<-list(shown_per_axis=nrow(brackets[[1]]),total_per_axis=nrow(pairwise)/2,reason=if(fit)'Within annotation budget' else 'Compact canvas; full statistics retained')
    if(!nrow(brackets[[1]])){top_mm<-max(length(levels)*font_mm*1.5,font_mm*3)+font_mm*2.5+3;main_mm<-max(font_mm*10,body_mm-top_mm)}
    if(nrow(brackets[[1]])){available<-max(font_mm*6,size$width*25.4*.73-font_mm*4-nrow(brackets[[1]])*label_gap-label_pad);step<-diff(xr)*label_gap/available;pad<-diff(xr)*label_pad/available;brackets[[1]]$position<-xr[2]+step*seq_len(nrow(brackets[[1]]));brackets[[1]]$tip<-step*.12;xr[2]<-xr[2]+step*nrow(brackets[[1]])+pad}
    if(nrow(brackets[[2]])){available<-max(font_mm*2,panel_mm-nrow(brackets[[2]])*label_gap-label_pad);step<-diff(yr)*label_gap/available;pad<-diff(yr)*label_pad/available;brackets[[2]]$position<-yr[2]+step*seq_len(nrow(brackets[[2]]));brackets[[2]]$tip<-step*.12;yr[2]<-yr[2]+step*nrow(brackets[[2]])+pad}
    known<-d[!d$group_missing,,drop=FALSE]
    p<-p+ggplot2::scale_x_continuous(limits=xr,expand=c(0,0))+ggplot2::scale_y_continuous(limits=yr,expand=c(0,0))
    top<-ggplot2::ggplot(known,ggplot2::aes(x,.ord_group,fill=.ord_group))+ggplot2::geom_boxplot(width=.55,outlier.shape=NA,linewidth=.3)+ggplot2::geom_point(position=ggplot2::position_jitter(width=0,height=.08,seed=14),shape=21,color='white',stroke=.2,size=1.5)+ggplot2::scale_x_continuous(limits=xr,expand=c(0,0))+scales[1]+ggplot2::scale_y_discrete(expand=ggplot2::expansion(add=1))+ggplot2::guides(fill='none',colour='none')+ggplot2::labs(x=NULL,y=NULL)+emp_pub_theme(base_size=font)+ggplot2::theme(legend.position='none',axis.text.x=ggplot2::element_blank(),axis.ticks.x=ggplot2::element_blank(),panel.grid.minor=ggplot2::element_blank())
    right<-ggplot2::ggplot(known,ggplot2::aes(.ord_group,y,fill=.ord_group))+ggplot2::geom_boxplot(width=.55,outlier.shape=NA,linewidth=.3)+ggplot2::geom_point(position=ggplot2::position_jitter(width=.08,height=0,seed=14),shape=21,color='white',stroke=.2,size=1.5)+ggplot2::scale_y_continuous(limits=yr,expand=c(0,0))+scales[1]+ggplot2::guides(fill='none',colour='none')+ggplot2::labs(x=NULL,y=NULL)+emp_pub_theme(base_size=font)+ggplot2::theme(legend.position='none',axis.text.y=ggplot2::element_blank(),axis.ticks.y=ggplot2::element_blank(),axis.text.x=ggplot2::element_text(angle=90,hjust=1,vjust=.5))
    if(nrow(brackets[[1]])){
      z<-brackets[[1]]
      top<-top+ggplot2::geom_segment(data=z,ggplot2::aes(x=position,xend=position,y=start,yend=end),inherit.aes=FALSE,linewidth=.3)+ggplot2::geom_segment(data=z,ggplot2::aes(x=position-tip,xend=position,y=start,yend=start),inherit.aes=FALSE,linewidth=.3)+ggplot2::geom_segment(data=z,ggplot2::aes(x=position-tip,xend=position,y=end,yend=end),inherit.aes=FALSE,linewidth=.3)+ggplot2::geom_text(data=z,ggplot2::aes(x=position,y=(start+end)/2,label=label),inherit.aes=FALSE,angle=90,vjust=-.35,size=font/(72.27/25.4))
    }
    if(nrow(brackets[[2]])){
      z<-brackets[[2]]
      right<-right+ggplot2::geom_segment(data=z,ggplot2::aes(x=start,xend=end,y=position,yend=position),inherit.aes=FALSE,linewidth=.3)+ggplot2::geom_segment(data=z,ggplot2::aes(x=start,xend=start,y=position-tip,yend=position),inherit.aes=FALSE,linewidth=.3)+ggplot2::geom_segment(data=z,ggplot2::aes(x=end,xend=end,y=position-tip,yend=position),inherit.aes=FALSE,linewidth=.3)+ggplot2::geom_text(data=z,ggplot2::aes(x=(start+end)/2,y=position,label=label),inherit.aes=FALSE,vjust=-.4,size=font/(72.27/25.4))
    }
    top<-top+ggplot2::labs(title=paste(axes[1],paste(.ord_p_label('Overall P',tests$p_value[1]),.ord_p_label('BH q',tests$p_adjusted[1]),sep='; '),sep='\n'))
    right<-right+ggplot2::labs(title=paste(axes[2],.ord_p_label('P',tests$p_value[2]),.ord_p_label('BH q',tests$p_adjusted[2]),sep='\n'))
    attr(top,'emp.hidden_guides')<-c('fill','colour');attr(right,'emp.hidden_guides')<-c('fill','colour')
    summary<-paste0('N(test)=',tests$n[1],'\nNA=',tests$n_missing[1],if(any(excluded))paste0('\nExcluded=',sum(excluded)) else '')
    # Axis statistics live outside the numeric panels, without changing point positions.
    corner<-ggplot2::ggplot()+ggplot2::annotate('text',x=0,y=.5,label=summary,hjust=0,size=font/(72.27/25.4),lineheight=1.1)+ggplot2::scale_x_continuous(limits=c(0,1),breaks=NULL)+ggplot2::scale_y_continuous(limits=c(0,1),breaks=NULL)+ggplot2::theme_void()
    p<-patchwork::wrap_plots(top,corner,right,p,design='AB\nDC',widths=c(4,1.45),heights=c(top_mm,main_mm),guides='collect')+patchwork::plot_annotation(title=title,subtitle=emp_publication_wrap(paste(c(if(ellipses$type!='none')sprintf('%.0f%% %s',100*ellipses$level,if(ellipses$type=='confidence')'mean CI' else 'data ellipse'),paste(unique(tests$method),collapse=' / '),if(length(excluded_groups))paste0('Tests exclude: ',paste(excluded_groups,collapse=', '))),collapse=' · '),size$width*25.4-8,font),theme=ggplot2::theme(plot.title=ggplot2::element_text(size=font+1,face='bold'),plot.subtitle=ggplot2::element_text(size=font)))
    if(nrow(pairwise)){caption<-if(!annotation_info$shown_per_axis)'Pairwise P/BH q: PAIRWISE.' else switch(pair_labels,p='Brackets: pairwise P (unadjusted); BH q values in PAIRWISE.',q='Brackets: BH-adjusted pairwise P (all requested pairs, both axes).',both='Brackets: pairwise P (first line), BH q (second line); all requested pairs and both axes.');size<-emp_figure_size(180/25.4,160/25.4);p<-p+patchwork::plot_annotation(caption=emp_publication_wrap(caption,size$width*25.4-8,font),theme=(p$patches$annotation$theme %||% ggplot2::theme())+ggplot2::theme(plot.caption=ggplot2::element_text(size=font,hjust=0)))}
    p<-p & ggplot2::theme(legend.position=appearance$legend %||% 'bottom')
  }else p<-p+ggplot2::labs(title=title,subtitle=if(grouped)paste(vapply(seq_len(nrow(tests)),function(i)paste(axes[i],.ord_p_label('P',tests$p_value[i]),.ord_p_label('BH q',tests$p_adjusted[i])),character(1)),collapse='\n') else NULL)
  if(nrow(pairwise))notes<-c(notes,sprintf('Pairwise labels: %s; %d / %d comparisons per axis annotated. Pairwise BH covers all requested comparisons across both axes; full results in PAIRWISE. / 每轴标注 %d / %d 项两两比较，完整原始 P 和校正值见 PAIRWISE。',pair_labels,annotation_info$shown_per_axis,nrow(pairwise)/2,annotation_info$shown_per_axis,nrow(pairwise)/2))
  list(plot=p,data=d[,setdiff(names(d),'.ord_group'),drop=FALSE],statistics=tests,pairwise=pairwise,pairwise_annotations=annotation_info,test_scope=list(mode=scope,n_test=tests$n[1],n_missing=sum(d$group_missing),n_excluded=sum(excluded),excluded_groups=excluded_groups),ellipses=ellipses[c('audit','type','level')],notes=notes,colors=colors)
}

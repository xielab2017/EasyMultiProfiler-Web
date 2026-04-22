####操作指南
#1. 建立一个保存分析数据的文件夹，例如：RNAseq，将该脚本放到RNAseq 文件夹中
#2. 在RNAseq文件夹中，建一个命名为raw_count 的文件夹，将所有HTSeq 得到的raw count 的txt格式的数据全部放在里面

#第一次操作安装必要的包
install.packages("pheatmap")
install.packages("dplyr")
install.packages("car")
install.packages("plyr")
install.packages("fs")
install.packages("RColorBrewer")

####自动查询目前 R 简本所在文件夹路径 ###########
library(rstudioapi)   
setwd(dirname(getActiveDocumentContext()$path))
####自动查询目前 R 简本所在文件夹路径 ###########

#加载软件包
library(dplyr)
library(pheatmap)
library(car)
library(plyr)
library(fs)
library(RColorBrewer)
library(ggplot2) # best plotting package

rm(list = ls())
#提取1-7两列
setwd("raw_count/")
files<-list.files(pattern = "Mai") #，读入所有文件名
RNAseq<-list()
for (f in files) {
  data<-read.delim(f,header = F)[-c(1:2),-c(2:6)]
  name<-strsplit(f,".",fixed=TRUE)[[1]][1]
  #write.table(data,file = paste0("DEseq2_output/",name,".csv"),
  #row.names = F,col.names=F,sep=",")
  
  RNAseq[[name]]<-data$V7
}

#将读取的raw count 写入临时文件k中
k<-as.data.frame(do.call(cbind,RNAseq)) #把每个raw count txt 按照顺序写入 数据框k内
k<-cbind(GeneID=data$V1,k)

####自动查询目前 R 简本所在文件夹路径 ###########
library(rstudioapi)   
setwd(dirname(getActiveDocumentContext()$path))
####自动查询目前 R 简本所在文件夹路径 ###########

#将k以csv形式导出到RNAseq文件夹
write.csv(k,file = "RNAseq_output.csv",row.names = F)

#拆分数据表格，选取标记以外的核心表达数据
row.names(k)<-k$GeneID
n <- ncol(k) #计算数据列数
data <- as.data.frame(k[,2:n]) #选取出第一列以外的所有数据



##################### Heatmap ########################
#读取mapping 文件和基因列表
mapping <- read.delim("mapping_WT_HFE_RT_Cold.txt", sep = "\t", header = T)  #读取mapping文件,需要按照项目单独提供
gene_list <- read.delim("gene_ID.txt", header = T, sep = "\t")  #读取基因列表文件,需要按照项目单独提供
gene_list <- as.data.frame(gene_list) 


#按照mapping 拆分表达矩阵
data <- read.delim("RNAseq_output.csv", header = T, row.names = 1, sep = ",")
data <- data[,which(colnames(data) %in% mapping$SampleID)] #确保mapping 的第一列SampleID 和读取的表达矩阵的样本名字一一对应，在R 读取文件是（_下划线）会被转化成（. 点）
#######如果这一步执行完，得到了空的数据集，说明mapping 的SampleID和表达矩阵内不相符

data <- data[which(rowSums(data) > 10000),]  #过滤调低表达的基因
data_1 <- data.frame(SampleID = colnames(data),t(data))
mapping <- subset(mapping, select = c(SampleID,Group_1,Group_2))
data_2 <- left_join(mapping,data_1,by="SampleID")
rownames(data_2)<- data_2$SampleID

#筛选做热图的基因
heatmap_data <- data_2[,which(colnames(data_2) %in% gene_list$Geneid)] 
heatmap_data <- data.frame(t(heatmap_data))

#色卡
palette <- colorRampPalette(c("blue","white","red"))(100)  #热图色卡
col_n <- ncol(mapping)
if (nrow(as.data.frame(unique(data_2$Group_1)))==1){
  Group_color <- heat.colors(nrow(as.data.frame(unique(data_2$Group_2))), alpha = 0.1)
  names(Group_color)<- unique(data_2$Group_2)
  ann_colors <- list(Group_color)
  annotation_data <- data.frame(Group=data_2$Group_2, row.names = data_2$SampleID)
} else {
  Group_color_1 <-heat.colors(nrow(as.data.frame(unique(data_2$Group_1))), alpha = 0.6)
  Group_color_2 <- brewer.pal(nrow(as.data.frame(unique(data_2$Group_2))),"Set2")
  names(Group_color_1) <- unique(data_2$Group_1)
  names(Group_color_2) <- unique(data_2$Group_2)
  ann_colors <- list(Group_color_1, Group_color_2)
  annotation_data <- data.frame(Group_1=data_2$Group_1, Group_2=data_2$Group_2, row.names = data_2$SampleID)
} 

pheatmap(heatmap_data,
         scale = "row",#对列进行归一化"column","row"
         color = colorRampPalette(c("blue", "white","red"))(256), #colorRampPalette(palette)(256), # color参数自定义颜色
         annotation_col = annotation_data,
         annotation_colors = ann_colors,
         cluster_rows = F,# cluster_row = FALSE参数设定对行进行聚类 
         cluster_cols = F,
         show_rownames =T, # show_rownames和show_colnames参数设定是否显示行名和列名
         show_colnames = F,
         fontsize_row = 5 ,
         fontsize_col = 5,
         cellwidth= 5,
         cellheight=4, # cellwidth和cellheight参数设定每个热图格子的宽度和高度
         #border_color = "white", #grey,black
         main = paste0("heatmap_BAT_WT_HFE_Mito")) # main参数添加主标题


######################################################################################
#Volcano plot
# Load your data
data <- read.csv("Volcano_plot/WT/iWAT/Deseq2_Cold_7D_RT.csv",header=T,sep = ",")
# Three main data, geneID, pvalue and lfc
data <- data.frame(gene = data[,1],
                   pvalue = -log10(data$pvalue),
                   lfc = data[,3])
# Remove rows that have NA values
data <- na.omit(data) 
head(data)

# Modify dataset to add new coloumn of colors
data <- data %>% mutate(color = ifelse(data$lfc > 0 & data$pvalue > 1.3, 
                                       yes = "UP", 
                                       no = ifelse(data$lfc < 0 & data$pvalue > 1.3, 
                                                   yes = "DOWN", 
                                                   no = "none")))


# x,y breaks
x=c(seq(min(data[,3]), max(data[,3]), length.out = 5))
y=c(0,1.3,seq(0,300, length.out = 5)) 
x 
y 

# Color corresponds to fold change directionality
volcanol <- ggplot(data, aes(x = lfc, y = pvalue)) + 
  geom_point(aes(color = factor(color)), size = 1.75, alpha = 0.8, na.rm = T) + # add gene points
  theme_bw(base_size = 16) + # clean up theme
  theme(legend.position = "none") + # remove legend 
  ggtitle(label = "iWAT_RT_Cold_7", subtitle = "") +  # add title
  xlab(expression(log[2]("fold change"))) + # x-axis label
  ylab(expression(-log[10]("adjusted p-value"))) + # y-axis label
  geom_vline(xintercept = 0, colour = "black") + # add line at 0
  geom_hline(yintercept = 1.3, colour = "black") + # p(0.05) = 1.3
  annotate(geom = "text", 
           label = "", 
           x = -2.5, y = 3,  
           size = 7, colour = "black") + # add Untreated text
  annotate(geom = "text", 
           label = "", 
           x = 2.5, y = 3, 
           size = 7, colour = "black")+ # add Treated text
  scale_x_continuous(breaks=c(-12,-8,-4,0,4,8,12),limits=c(-12,12)) +  # set x axis 
  scale_y_continuous(breaks = c(0,1.3,5,10,30,50,100),limits = c(0,100),trans = "log1p") + # set y axis
  scale_color_manual(values = c("UP" = "#E64B35", 
                                "DOWN" = "#3182bd", 
                                "none" = "#636363")) # change colors
ggsave("Volcano_plot/WT/iWAT/iWAT_volcanol.pdf", dpi=600)

# Choose the gene or top gene
geneID_all <- read.table("gene.txt", header = T)
#geneID_all <- geneID_all[geneID_all$FDR<0.05,]
geneID<- geneID_all[,1]
geneID_all <-data[,1]

#geneID_all
# Convert geneID into the row number in the annot file, and Pick up the gene that can not match
gene=c()
cgene=c()
for (i in geneID)
{
  num<- which(geneID_all==i)
  print(num)
  gene=c(gene,num)
  judge <- i %in% geneID_all
  if (judge == "FALSE")
  {
    print(i)
    cgene=c(cgene,i)
  }
}
print(gene) 
print(cgene)
gene <- data[gene,]

volcanol+geom_text_repel(data = gene, # or top_labelled
                         mapping = aes(label = gene), 
                         size = 3,
                         fontface = 'bold', 
                         color = 'black',
                         box.padding = unit(1, "lines"),
                         point.padding = unit(1, "lines"),xlim = c(-12,12))
                        
ggsave("Volcano_plot/WT/iWAT/iWAT_Volcano_plot_label.pdf", dpi=600)





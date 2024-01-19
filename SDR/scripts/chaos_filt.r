# 
library(dbscan)
library(dplyr)
library(data.table)
library(IRanges)
args <- commandArgs(trailingOnly = TRUE)
print(args)
alignintersect<-function(align1,align2,align3){
  del.list<-c()
  cat("-------开始去除着丝粒和端粒区域的比对---------\n")
  cat("去除前的：",dim(align1)[1],"\n")
  ir1ref <- IRanges(start = align1$V8, end = align1$V9)
  ir1que  <- IRanges(start = align1$V3, end = align1$V4)
  ir2 <- IRanges(start =align2$ref_start , end =align2$ref_end)
  overlapsref<-findOverlaps(ir1ref,ir2) ##我们的比对序列的参考基因组序列和人的端粒|着丝粒的交集
  if(length(overlapsref@from)!=0){  
    del.list<-append(del.list,overlapsref@from)
  }
  if(!missing(align3)){
    ir3 <- IRanges(start = align3$query_start, end = align3$query_end)
    overlapsque<-findOverlaps(ir1que,ir3)
    if(length(overlapsque@from)!=0){
      del.list<-append(del.list,overlapsque@from)
    }
  }
  if(length(del.list)!=0)
  {align1<-align1[-del.list,]}
  cat("去除后的：",dim(align1)[1],"\n")
  return(align1)
}
#-------------------function2 把pos改为saffire文件函数 -----------------------------------------------------
flit2saffire<-function(pos,name){
  cat("-------开始转saffire--------\n")
  col_names <- colnames(pos)
  col_names[c(1,3, 4, 8, 9,6,5)] <- c("query_chr","query_start", "query_end", "ref_start", "ref_end","ref_chr","orient")
  colnames(pos) <- col_names
  chrpc<-fread(args[1])
  chrpc<-distinct(chrpc)
  colnames(chrpc)<-c("ref_chr","ref_len","query_chr","query_len")
  saffire<-merge(pos,chrpc,by=c("ref_chr","query_chr"))
  saffire<-saffire[,c("ref_chr","ref_start","ref_end","ref_len","orient","query_chr","query_start","query_end","query_len")]
  saffire_name<-c("#reference_name","reference_start","reference_end","reference_length","strand",  "query_name","query_start","query_end","query_length","perID_by_matches","perID_by_events", "perID_by_all","matches","mismatches","deletion_events", "insertion_events", "deletions","insertions")
  saffire[,c("perID_by_matches","perID_by_events", "perID_by_all","matches","mismatches","deletion_events", "insertion_events", "deletions","insertions")]<-0
  colnames(saffire)<-saffire_name
  saffire$matches<-100
  saffire$mismatches<-100
  write.table(saffire, file = paste(args[2],name,sep = ""), sep = "\t", row.names = FALSE,quote = FALSE)
}
#-------------------function4 split 并聚类 ----------------------

split_region<-function(pos.chr.region){
  col_names <- colnames(pos.chr.region)
  # 修改第3列，第4列，第8列和第9列的名字
  col_names[c(3, 4, 8, 9,5)] <- c("query_start", "query_end", "ref_start", "ref_end","orient")
  colnames(pos.chr.region) <- col_names

  x<-pos.chr.region[pos.chr.region$orient=="-",]
  if(nrow(x)!=0){
    
      selected_rows <- pos.chr.region$orient == '-'
      # 计算新的 query_start 和 query_end 列的值
      #new_query_start <- pos.chr.region[selected_rows, ]$V2 - pos.chr.region[selected_rows, ]$query_end
      #new_query_end <- pos.chr.region[selected_rows, ]$V2 - pos.chr.region[selected_rows, ]$query_start
      
      new_query_start <- pos.chr.region[selected_rows, ]$query_end
      new_query_end <- pos.chr.region[selected_rows, ]$query_start
      # 更新数据框中的值
      pos.chr.region[selected_rows, ]$query_start <- new_query_start
      pos.chr.region[selected_rows, ]$query_end <- new_query_end

  }
  df <- pos.chr.region %>%
    rowwise() %>%
    mutate(length = sqrt((ref_end - ref_start)^2 + (query_end- query_start)^2),
           segments = ceiling(length / 5000))
  df_segments <- df[rep(seq_len(nrow(df)), df$segments), ]
  df_segments <- df_segments %>%
    group_by(ref_start, ref_end, query_start, query_end) %>%
    mutate(segment_id = row_number(),
           segment_mid_x = ref_start + (ref_end - ref_start) * (segment_id - 0.5) / segments,
           segment_mid_y = query_start + (query_end - query_start) * (segment_id - 0.5) / segments)
  
  dbscan_result <- dbscan(df_segments[,c("segment_mid_x", "segment_mid_y")], eps = as.numeric(args[5]), minPts =1)
  df_segments$cluster <- dbscan_result$cluster
  df_segments <- df_segments %>%
    group_by(ref_start, ref_end, query_start, query_end,sourse) %>%
    summarise(cluster = names(which.max(table(cluster))))
  merge<-df_segments %>% group_by(cluster)%>%  #聚cluster
    summarise(ref_start=min(ref_start),ref_end=max(ref_end),query_start=min(query_start),query_end=max(query_end)) ###正链负链？？重新算一下
    #   all<-distinct(all)
  
  
  x<-table(df_segments$cluster)
  del<-as.numeric(names(x[which(x<=5)]))
  for(j in del){
    if(abs(merge[merge$cluster==j,]$ref_end-merge[merge$cluster==j,]$ref_start)>as.numeric(args[6])){
      del<-del[del!=j]
    }
  }
  delall<-df_segments[df_segments$cluster %in% del,]$sourse
  return(delall)
}
print(args[7])
if(args[7]=="cts"){
  cts=TRUE
# cta=FALSE
ctn=FALSE
}
if(args[7]=="ctn"){
  cts=FALSE
# cta=FALSE
ctn=TRUE
}
## 分为三种情况：
## 什么都没有
## 只有参考基因组的端粒和着丝粒
## 两者都有
## cta=TRUE 都计算 FALSE都不计算
## cts=TRUE 计算参考基因组的
## ctn=TRUE 计算参考基因组的

if(cts){  ##只计算参考基因组的
  ## 端粒
  result_reftelo<-fread(args[9])
  result_quetelo<-""
  ## 着丝粒
  result_refcentr<-fread(args[8])
  result_quecentr<-""
}
# if(cta){
#   result_reftelo<-fread("/home/jmhan/breakpoints/minimap/chimpanzee/telocentrodata/hm_teloend.tsv")
#   result_quetelo<-fread("D:/MS/big test/macaque/end_quetelo.txt")
#   result_refcentr<-fread("/home/jmhan/breakpoints/minimap/chimpanzee/telocentrodata/hm_centroend.tsv")
#   result_quecentr<-fread("D:/MS/big test/macaque/end_quecen.txt")
# }
if(ctn){
  result_reftelo<-""
  result_quetelo<-""
  result_refcentr<-""
  result_quecentr<-""
}
print(args[7])
pos<-fread(args[3],fill=TRUE )
cat("去除前的：",dim(pos)[1],"\n")
chrnames <- unique(pos$V6)
numeric_part <- as.numeric(gsub("\\D", "", chrnames))
sorted_chrnames <- chrnames[order(numeric_part)] #染色体排序
## 染色体
## -----------对文件进行过滤：删除距离大于某某G的比对,相当于不考虑translocation的情况
##把着丝粒和端粒区域的比对删掉
for(chrid in sorted_chrnames){
  pos.chr<-pos[pos$V6==chrid,]
  print(chrid)
  align1<-pos.chr  ##我们的比对
  if(cts){
    align2<-result_refcentr[result_refcentr$chr==chrid,]          ##人着丝粒
    intersect<-which(pos.chr$V8>=align2$ref_start & pos.chr$V9<=align2$ref_end)
    if(length(intersect)!=0){
      print("have")
      pos.chr<-pos.chr[-intersect,]
    }
    align2<-result_reftelo[result_reftelo$chr==chrid,]          ##人端粒
    for(j in dim(align2)[1]){
      intersect<-which(pos.chr$V8>=align2[j,]$ref_start & pos.chr$V9<=align2[j,]$ref_end)
      if(length(intersect)!=0){
      pos.chr<-pos.chr[-intersect,]
    }
    }
    assign(chrid,pos.chr)
  }
  # if(cta){
  #   quelist <- paste0("que", unique(align1$V1))
  #   align2<-result_refcentr[result_refcentr$chr==chrid,]          ##人着丝粒
  #   for(j in unique(align1$V1)){
  #     align3<-result_quecentr[result_quecentr$chr==j,]
  #     align1child<-alignintersect(align1[align1$V1==j,],align2,align3)
  #     assign(paste0("que", j),align1child)
  #   }
  #   align1<-do.call(rbind,mget(quelist))
  #   rm(list=quelist)
  #   align2<-result_reftelo[result_reftelo$chr==chrid,]          ##人端粒
  #   for(j in unique(align1$V1)){
  #     align3<-result_quetelo[result_quetelo$chr==j,]      ##猩猩端粒
  #     align1child<-alignintersect(align1[align1$V1==j,],align2,align3)
  #     assign(paste0("que", j),align1child)
  #   }
  #   align1<-do.call(rbind,mget(quelist))
  #   print(dim(align1)[1])
  #   rm(list=quelist)
  #   assign(chrid,align1)
  # }
  
  if(ctn){
    assign(chrid,align1)
  }
}


pos<-do.call(rbind,mget(chrnames))
pos$sourse<-1:dim(pos)[1]
rm(list=chrnames) ##删除变量
cat("去除着丝粒后的：",dim(pos)[1],"\n")
flit2saffire(pos,"filt_process.saffire") ## 看看过滤了以后的比对结果

delall<-c()
for(chrid in sorted_chrnames){
  pos.chr<-pos[pos$V6==chrid,]
  del<-split_region(pos.chr)
  delall<-append(delall,del)
}
xxx<-pos[!pos$sourse %in% delall,]

cat("去除chaos后的：",dim(xxx)[1],"\n")
flit2saffire(xxx,"filt2_process.saffire") ## 看看过滤了以后的比对结果


write.table(xxx, file = args[4], sep = "\t", row.names = FALSE, col.names = FALSE,quote=FALSE)
print("complete!!!!")
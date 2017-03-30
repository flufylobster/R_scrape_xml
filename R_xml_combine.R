install.packages("xml2")
install.packages("XML")

library(xml2)
library(XML)

setwd("Z:\\CreditPolicy\\WNLI\\_FlexPay\\Data Studies\\TUCV Fraud Alerts\\test")


#read.table(read_xml(file, header=FALSE, sep="\t"))

file_list <- list.files()

for (file in file_list){
  
  # if the merged dataset doesn't exist, create it
  if (!exists("dataset")){
   dataset <- read.table(file, header=FALSE, stringsAsFactors=FALSE, sep="\t")
  }
  
  # if the merged dataset does exist, append to it
  if (exists("dataset")){
    temp_dataset <-read.table(file, header=FALSE, stringsAsFactors=FALSE, sep="\t")
    dataset<-rbind(dataset, temp_dataset)
    rm(temp_dataset)
  }
  
}



require("XML")


# set working directory to list of xml files
setwd("Z:\\CreditPolicy\\WNLI\\_FlexPay\\Data Studies\\TUCV Fraud Alerts\\Sridhar_FlexPay_CreditVision_XML_20170314")


# Create file list  from  directory
file_list <- list.files()
# Create namespace for XML structure
nsDefs <- xmlNamespaceDefinitions(xmlTreeParse(file_list[1],useInternalNodes = TRUE))
ns <- structure(sapply(nsDefs, function(x) x$uri), names = names(nsDefs))
names(ns)[1] <- "x"

### create extraction function
extract.flat<-function(codes,id){
    n<-2;
  while (n <= length(codes)) 
  { 
    if (!exists("dataset")){
      dataset <- cbind(setNames(data.frame(xmlValue(codes[[1]]),xmlValue(id[[1]])),c("CODE","ID")))
    }
    
    if (exists("dataset")){
      temp_dataset <-cbind(setNames(data.frame(xmlValue(codes[[n]]),xmlValue(id[[1]])),c("CODE","ID")))
      dataset<-rbind(dataset, temp_dataset)
      rm(temp_dataset)
    }
    
    if (n == length(codes)) { return(dataset)}
      else  { n<-n+1};
  }
                               }

# Iterate over XML files to parse XML code 

for ( m in 1:(length(file_list)-1)) {
  
  if (!exists("d"))
   {
       d<- extract.flat(code=xpathSApply(xmlTreeParse(file_list[1],useInternalNodes = TRUE), "//x:code/text()", namespaces=ns),
                        id=xpathSApply(xmlTreeParse(file_list[1],useInternalNodes = TRUE), "//x:userRefNumber/text()", namespaces=ns))
   #print(d)
   }
 
 if (exists("d")) {
       d1<-extract.flat(code=xpathSApply(xmlTreeParse(file_list[m+1],useInternalNodes = TRUE), "//x:code/text()", namespaces=ns),
                        id=xpathSApply(xmlTreeParse(file_list[m+1],useInternalNodes = TRUE), "//x:userRefNumber/text()", namespaces=ns))
   #print(d1)

  d<-rbind(d,d1)
  #print(d)
  rm(d1)

  }
  #rm(doctemp)
  }


setwd("Z:\\CreditPolicy\\WNLI\\_FlexPay\\Data Studies\\TUCV Fraud Alerts")
write.csv(d,file="parsed_tucv.csv",row.names=F)

#-------------------------
##  Random XML commands
#------------------------------
#xmltop=xmlRoot(doc)
#xmlSize(doc)
#xmlName(xmltop)
#Root Node's children
#xmlSize(xmltop) #number of nodes in each child
#xmlSApply(xmltop, xmlName) #name(s)
#xmlSApply(xmltop[[4]], xmlAttrs) #attribute(s)
#xmlSApply(xmltop, xmlSize) #size
#names(xmltop)











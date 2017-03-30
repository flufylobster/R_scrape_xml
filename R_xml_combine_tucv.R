require("data.table")

# files path
setwd("Z:\\CreditPolicy\\WNLI\\_FlexPay\\Data Studies\\TUCV Fraud Alerts\\Sridhar_FlexPay_CreditVision_XML_20170314")

# list containing your file names
file_list = list.files() 

# read data and save in a list
mydata <- lapply(file_list, read.table, header = FALSE, sep = "\t") 
mydata <- rbindlist(mydata) # merge list to one data frame


# reading data in parallel cores

require(parallel)
file_list = list.files() 

no_cores <- detectCores()
cl <- makeCluster(no_cores)
clusterEvalQ(cl, {library("parallel")}) # install dependencies in cores
clusterExport(cl=cl, varlist=c("file_list")) # global variables
mydata <- parLapply(cl, file_list, read.table, header = FALSE, sep = '\t') 
mydata <- rbindlist(mydata) # merge list to one data frame

write.csv(mydata, file = "flexpay_tucv.csv",row.names=FALSE)

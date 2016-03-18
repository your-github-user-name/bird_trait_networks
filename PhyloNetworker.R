# SETUP ###############################################################

rm(list=ls())
source("~/Documents/workflows/bird_trait_networks/setup.R")
setwd(input.folder) #googledrive/bird trait networks/inputs/data

# PACKAGES & FUNCTIONS ###############################################################

library(caper)
library(geiger)
library(PHYLOGR)
library(rnetcarto)

calcTraitPairN <- function(data){
  
  vars <- names(data)[!names(data) %in% c("species", "synonyms")]
  
  var.grid <- expand.grid(vars, vars, stringsAsFactors = F)
  var.grid <- var.grid[var.grid[,1] != var.grid[,2],]
  
  indx <- !duplicated(t(apply(var.grid, 1, sort))) # finds non - duplicates in sorted rows
  var.grid <- var.grid[indx, ]
  
  countN <- function(x, data){sum(complete.cases(data[,c(x[1], x[2])]))}
  
  var.grid <- data.frame(var.grid, n = apply(var.grid, 1, FUN = countN, data = data))
  
}

pglsPhyloCor <- function(x, data, match.dat, tree, log.vars){
  
  var1 <- unlist(x[1])
  var2 <- unlist(x[2])
  
  data <- data[, c("species", "synonyms", var1, var2)] 
  data <- data[complete.cases(data),]
  
  spp <- data$species
  nsps <- length(spp)
  
  if(var1 %in% log.vars & all(data[,var1] > 0)){
    data[,var1] <- log(data[,var1])
    names(data)[names(data) == var1] <- paste("log", var1, sep = "_")
    var1 <- paste("log", var1, sep = "_")
    
  }
  if(var2 %in% log.vars & all(data[,var2] > 0)){
    data[,var2] <- log(data[,var2])
    names(data)[names(data) == var2] <- paste("log", var2, sep = "_")
    var2 <- paste("log", var2, sep = "_")
  }
  
  # Std. correlation
  cor <- cor(data[,var1], data[,var2])
  
  
  #METHOD 2 extracting from a PGLS
  #----------------------------------------------------
  
  cd <- comparative.data(phy = tree, data = data, names.col = "synonyms", vcv=F)
  
  result.pgls <- try(pgls(as.formula(paste(var1, "~", var2, sep = "")), data = cd, lambda="ML"))
  
  
  if(class(result.pgls) == "try-error"){
    phylocor2 <- NA
    lambda <- NA
    error <- gsub(pattern = ".*\n  ", "", geterrmessage())

  }else{
    
    t <- summary(result.pgls)$coefficients[var2,3]
    df <- as.vector(summary(result.pgls)$fstatistic["dendf"])
    phylocor2 <- sqrt((t*t)/((t*t)+df))*sign(summary(result.pgls)$coefficients[var2,1])
    lambda <- result.pgls$param["lambda"]
    error <- NA

  }
  
  
  return(data.frame(var1 = var1, var2 = var2, cor = cor, phylocor = phylocor2, n = nsps,
                    lambda = lambda, error = error))
}

# SETTINGS ###############################################################

# dir.create(paste(output.folder, "data/phylocors/", sep = ""))
# dir.create(paste(output.folder, "data/networks/", sep = ""))

an.ID <- "100spp"
log <- T
if(log){log.vars <- metadata$master.vname[as.logical(metadata$log)]}else{log.vars <- ""}


# FILES ##################################################################

wide <- read.csv(file ="csv/master wide.csv", fileEncoding = "mac")
spp100 <- unlist(read.csv(file ="csv/100spp.csv"))

spp.list <- data.frame(species = unique(wide$species))

# trees <- read.tree(file = "tree/Stage2_MayrAll_Hackett_set10_decisive.tre")
# tree <- trees[[1]]
# save(tree, file = "tree/tree.RData")
load(file = "tree/tree.RData")

#load match data
load(file = "r data/match data/tree m.RData")
match.dat <- m$data

# WORKFLOW ###############################################################

## NUMERIC VARIABLES >>>>


# separate numeric variables
num.var <- metadata$master.vname[metadata$type %in% c("Int", "Con")]
num.dat <- wide[,c("species", names(wide)[names(wide) %in% num.var])]

#Remove duplicate species matching to the same species on the tree
num.dat <- num.dat[num.dat$species %in% match.dat$species[match.dat$data.status != "duplicate"],]

# add synonym column to data 
num.dat$synonyms <- match.dat$species[match(num.dat$species, match.dat$species)]


## SUBSET TO 100 SPECIES >>>

if(an.ID == "100spp"){
  num.dat <- num.dat[num.dat$species %in% spp100,]}


# VARIABLES COMBINATION DATA AVAILABILITY >>>

## Create grid of unique variable combinations, calculate data availability for each and sort
var.grid <- calcTraitPairN(num.dat)
var.grid <- var.grid[var.grid$n > 3,]
var.grid <- var.grid[order(var.grid$n, decreasing = T),]


# PHYLOGENTICALLY CORRECTED CORRELATIONS ####################################################

var.combs <- var.grid[var.grid$Var1 == res[i,"var1"] & var.grid$Var2 == res[i,"var2"],]
var.combs <- 1:dim(var.grid)[1]

res <- NULL
for(i in var.combs){
  
  res <- rbind(res, pglsPhyloCor(var.grid[i, 1:2], data = num.dat, 
                                 match.dat = match.dat, tree = tree, log.vars = log.vars))
  print(i)
}


res <- res[order(abs(res$phylocor), decreasing = T),]

write.csv(res, paste(output.folder, "data/phylocors/", an.ID," phylocor", if(log){" log"},".csv", sep = ""),
          row.names = F)


## NETWORK ANALYSIS ####################################################################

library(rnetcarto)
net.d <- res[!is.na(res$phylocor), c("var1", "var2", "phylocor")]
net.list <- as.list(net.d)
net <- netcarto(web = net.list, seed = 1)


write.csv(cbind(net[[1]], modularity = net[[2]]), paste(output.folder, "data/networks/", an.ID," network", if(log){" log"},".csv", sep = ""),
          row.names = F)





# RCytoscape ###############################################################################

#source('http://bioconductor.org/biocLite.R')
biocLite ('RCytoscape')

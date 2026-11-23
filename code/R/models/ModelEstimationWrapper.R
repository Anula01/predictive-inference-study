# =============================================================================
#### Info #### 
# =============================================================================
# hierarchical model for the JGET
# code based on hBayesDM


run_model_fit <- function(data, modelfile, savemodelname, nIter = 2000, sampling = "sampling") {
   
   # =============================================================================
   #### Construct Data #### 
   # =============================================================================
   # clear workspace
   library(rstan)
   library(ggplot2)
   # library(R.matlab)
   library(tidyr)
   library(dplyr)
  library(tidyverse)
   
   ### functions 
   no_subjects <- NA; # if NA use all
   logit <- function(x) log(x/(1-x))
   
   
   ### load data
   data_trial <- read.csv(data)
   
   
   ### prepare data
   ntrials = max(data_trial$trials)
   subjList <- unique(data_trial$ID)
   if (!is.na(no_subjects)) subjList <- subjList[1: no_subjects]
 
   
   subset_subjList_temp <- data_trial %>% filter(session== max(data_trial$session)) %>% select(ID) %>% unique()
   subset_subjList <- subset_subjList_temp$ID
 
   

   

   numSub <- length(subjList)
   maxTrials <- ntrials
   
   Tsubj <- matrix(NA, numSub, 4)
   outcome <- array(-1,c(numSub, 4*maxTrials))
   response <- array(-1,c(numSub, 4*maxTrials))
   confidence <- array(-1,c(numSub, 4*maxTrials))
   # mua <- array(-1,c(numSub, 4*maxTrials))
   # mux2 <- array(-1,c(numSub, 4*maxTrials))
   # pix1 <- array(-1,c(numSub, 4*maxTrials))
  
   
   for (ss in 1:numSub) {
      
      for (ses in min(data_trial$session):max(data_trial$session)) {
         a<- data_trial %>% filter(ID == subjList[ss], session == ses) %>%  select(trials) %>% dim()
         
         Tsubj[ss,ses] <- ntrials
         if (a[1] >0)  {
            outcome[ss, seq(from = ntrials*(ses-1)+1, to=ntrials*ses)] = data_trial$outcome[data_trial$session == ses & data_trial$ID == subjList[ss]][1:ntrials]
            response[ss, seq(from = ntrials*(ses-1)+1, to=ntrials*ses)] = data_trial$response[data_trial$session == ses & data_trial$ID == subjList[ss]][1:ntrials]
            conf_temp = data_trial$confidence[data_trial$session == ses & data_trial$ID == subjList[ss]][1:ntrials]/max(data_trial$confidence,na.rm=T)
            conf_temp[conf_temp<0] = 0
            conf_temp[conf_temp>1] = 1
            confidence[ss, seq(from = ntrials*(ses-1)+1, to=ntrials*ses)]  = conf_temp
            # mua[ss, seq(from = ntrials*(ses-1)+1, to=ntrials*ses)] = data_trial$mua_h[data_trial$session == ses & data_trial$ID == subjList[ss]][1:ntrials]
            # mux2[ss, seq(from = ntrials*(ses-1)+1, to=ntrials*ses)] = data_trial$mux2_h[data_trial$session == ses & data_trial$ID == subjList[ss]][1:ntrials]
            # pix1_temp= data_trial$pix1_h[data_trial$session == ses & data_trial$ID == subjList[ss]][1:ntrials]
            # 
            # pix1_temp[log(pix1_temp) %>% is.na()] <- NA
            # pix1[ss, seq(from = ntrials*(ses-1)+1, to=ntrials*ses)] = pix1_temp
            
            
         }
      }
   }
   
   response[is.na(response)]<- -1
   response[is.na(confidence)]<- -1
   
   confidence[is.na(confidence)]<- -1
   # confidence[is.na(log(pix1))]<- -1
   dataList <- list(N = numSub, T = maxTrials, Tsubj = Tsubj, outcome = outcome, response=response, simulate = simulate, confidence = confidence)
                    #, pix1 = pix1, mua = mua, mux2 = mux2)

   # (outcome %>% is.na()) %>% sum()
   # =============================================================================
   #### Running Stan #### 
   # =============================================================================
   rstan_options(auto_write = T)
   options(mc.cores = parallel::detectCores())
   
   if (sampling == "try") {
      cat("Trying..  \n")
      nIter     <-2
      nChains   <-1
      nWarmup   <- 1
      nThin     <- 1
   } else {
      # nIter     <-3000
      nChains   <- 4
      nWarmup   <- floor(nIter/3)# 1000
      nThin     <- 1
   }
   

   cat("Estimating", modelfile, "model... \n")
   
   startTime = Sys.time(); print(startTime)
   cat("Calling", nChains, "simulations in Stan... \n")
   
   fit_rl <- stan(modelfile, 
                  data    = dataList, 
                  chains  = nChains,
                  iter    = nIter,
                  warmup  = nWarmup,
                  thin    = nThin,
                  init    = "0", #inits_list,#,"random",#
                  seed    = 1450154637,
                  control = list(max_treedepth = 17,
                                 adapt_delta = 0.95
                  )
   )
   # 
   # stepsize = 2.0,
   # max_treedepth = 10
   cat("Finishing", modelfile, "model simulation ... \n")
   endTime = Sys.time(); print(endTime)
   cat("It took", as.character(difftime(endTime, startTime, units = "mins")), "minutes\n")
   cat("Saving in ", savemodelname, "... \n")
   
   saveRDS(fit_rl, file = savemodelname)
   
   
   return(fit_rl)
}



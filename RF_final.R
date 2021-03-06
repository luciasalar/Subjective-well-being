install.packages(c("tm","RTextTools","tidyverse","stringr","lda","textmineR","stringi","glmnet","party","qdap","ridge", "Metrics"))
library(tm)
library(RTextTools)
library(tidyverse)
library(stringr)
library(lda)
library(textmineR)
library(stringi)
library(glmnet)
library(party)
library(qdap)
library(ridge)
library(Metrics)


######################  SESSION 1 create topic table   ########################
#read tables
statusswl <- read.csv("user_all_status_swl2.csv", header = T, fill=TRUE,row.names=NULL)
swl<- read.csv("swl.csv", header = T, fill=TRUE,row.names=NULL)

#group status according to userid
statusswl2 <- aggregate(status~user_id, statusswl, FUN= paste, collapse=' ')

#clean data, replace smiley with words
smiles <- data.frame(s=c( ">:(", ":<", ">:", "=(", "=[", "='(",  "^_^",":)","=)","(=" ,"=]","^.^",":(",";)",";-)",":D","XD",":P",";P","<3"),
                     r=c("unhappyface","unhappyface","unhappyface","unhappyface","unhappyface","unhappyface","happyface","happyface","happyface","happyface","happyface","happyface","unhappyface","happyface","happyface","happyface","happyface","happyface","happyface","kiss"))

statusswl2$status %>%
        str_replace_all(" ?(f|ht)tp(s?)://(.*)[.][a-z]+", " ")%>%
        str_replace_all("\\d", " ")%>%
        stri_replace_all_fixed(pattern = smiles$s,replacement = smiles$r,vectorize_all = FALSE)%>%
        str_replace_all("[^[:alnum:]']", " ")%>%
        str_replace_all('\\s\\b[^i]{1}\\s', " ")%>%
        gsub("\\s+", " ",.) -> statusswl2$status

#create dtm
clean2.corpus <- Corpus(VectorSource(statusswl2$status))

dtm2 <- DocumentTermMatrix(clean2.corpus)

#convert dtm into matrix
freqs <- as.data.frame(as.matrix(dtm2))

#load topic list 
topic2000 <- read.csv("2000_emo.csv", header = F, fill=F,row.names=NULL)
topic2001 <- t(topic2000)


#count word frequency according to the topic list, here shows how many topic words occur in each document
p4 <- vector()
for(i in 1:2000) {
        o1 <- vector()
        o1 <- freqs[c(1, match(topic2001[, i], names(freqs), nomatch=0))]
        if(length(o1) > 2) {
                topicCollumn = paste("topic", as.character(i), sep='')
                p4[topicCollumn] <- as.data.frame(rowSums(o1))
        }
}

topic.table <- as.data.frame(p4)
#add userid to p4

topic.id <- as.data.frame(statusswl2[,1])

topic.id[2:1982] <- topic.table[1:1981]
colnames(topic.id)[1] <- "userid"


####################################### SESSION 2 TOPIC TABLE WITH LIWC ####################################

#join topics with LIWC data
liwc <- read.csv("liwc.csv", header = T, fill=TRUE,row.names=NULL)
liwc2 <- liwc
liwc2[2:65] <- scale(liwc[,2:65])



######################## SESSION 3 SENTIMENT ####################################


# import positive and negative words
pos = readLines("positive_words.txt")
neg = readLines("negative_words.txt")
score.sentiment = function(sentences, pos, neg, .progress='none')
{
        require(plyr)
        require(stringr)
        
        # we got a vector of sentences. plyr will handle a list or a vector as an "l" for us
        # we want a simple array of scores back, so we use "l" + "a" + "ply" = laply:
        scores = laply(sentences, function(sentence, pos, neg) {
                
                # clean up sentences with R's regex-driven global substitute, gsub():
                sentence = gsub('[[:punct:]]', '', sentence)
                sentence = gsub('[[:cntrl:]]', '', sentence)
                sentence = gsub('\\d+', '', sentence)
                # and convert to lower case:
                sentence = tolower(sentence)
                
                # split into words. str_split is in the stringr package
                word.list = str_split(sentence, '\\s+')
                # sometimes a list() is one level of hierarchy too much
                words = unlist(word.list)
                
                # compare our words to the dictionaries of positive & negative terms
                pos.matches = match(words, pos)
                neg.matches = match(words, neg)
                
                # match() returns the position of the matched term or NA
                # we just want a TRUE/FALSE:
                pos.matches = !is.na(pos.matches)
                neg.matches = !is.na(neg.matches)
                
                # and conveniently enough, TRUE/FALSE will be treated as 1/0 by sum():
                score = sum(pos.matches) - sum(neg.matches)
                
                return(score)
        }, pos, neg, .progress=.progress )
        
        scores.df = data.frame(score=scores, text=sentences)
        return(scores.df)
}


###count the number of status in each user
detach("package:plyr", unload=TRUE)
statusswl %>%
        group_by(user_id) %>%
        mutate(count = n()) %>%
        select(user_id,count)%>%
        rename(userid = user_id) %>%
        .[!duplicated(.$userid), ]-> status.count


summary(status.count$count)
#Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
#1.0    36.0    98.0   142.3   201.0   500.0 

sd(status.count$count)
#136.9811

hist(status.count$count)


###########clean data
statusswl$status %>%
        #       as_vector() %>%
        str_replace_all(" ?(f|ht)tp(s?)://(.*)[.][a-z]+", " ")%>%
        str_replace_all("\\d", " ")%>%
        stri_replace_all_fixed(pattern = smiles$s,replacement = smiles$r,vectorize_all = FALSE)%>%
        str_replace_all("[^[:alnum:]']", " ")%>%
        str_replace_all('\\s\\b[^i]{1}\\s', " ")%>%
        gsub("\\s+", " ",.) -> statusswl$status

######compute sentiment score
result_all2 <- score.sentiment(statusswl$status, pos, neg)

statusswl.senti <- statusswl
statusswl.senti[3:4] <- result_all2[1:2]
colnames(statusswl.senti)[3] <- "sentiment.score"
colnames(statusswl.senti)[2] <- "userid"

#####join sentiment score with status count for each user
statusswl.senti %>%
        select(userid, sentiment.score,text) %>% 
        left_join(status.count, by = "userid") %>%
        right_join(swl, by = "userid") %>%
        filter(count > 30) -> statusswl.senti2

#mean sentiment score and swl score of each user + frequency of positive post and negative post
detach("package:plyr", unload=TRUE)
statusswl.senti2 %>% group_by(., userid) %>%
        mutate(neg.freq = sum(sentiment.score < 0)/count) %>%
        mutate(pos.freq = sum(sentiment.score > 0)/count) %>%
        mutate(pos.neg = as.numeric(sum(sentiment.score > 0)/sum(sentiment.score < 0))) %>%
        summarise(., mean.senti=mean(sentiment.score),mean.swl=mean(swl),pos.freq=mean(pos.freq),neg.freq=mean(neg.freq),pos.neg=mean(pos.neg))-> statusswl5

#varible correlation with swl
cor.test(statusswl5$neg.freq,statusswl5$mean.swl)
#-0.2325164, p-value < 2.2e-16  
statusswl5$pos.neg[!is.finite(statusswl5$pos.neg)] <- NA
cor.test(statusswl5$pos.neg,statusswl5$mean.swl,use = "complete.obs")
#0.1603037, p-value < 2.2e-16
cor.test(statusswl5$pos.freq,statusswl5$mean.swl)
#0.07833762, p-value = 6.086e-05
cor.test(statusswl5$mean.senti,statusswl5$mean.swl)
#0.2056476, p-value < 2.2e-16 

#The original wordlist without addition of smileys etc achieved 0.1810901 

#number of positive/negative score
sum(statusswl.senti2$sentiment.score > 0)
#184831


sum(statusswl.senti2$sentiment.score < 0)
#115915


sum(statusswl.senti2$sentiment.score == 0)
#194203

##correlation matrix of the sentiment variables, multicolinearity
statusswl5 %>%
        select(mean.swl,mean.senti,pos.freq,neg.freq,pos.neg)%>%
        cor(.,use = "complete.obs") -> cor.matrix

######cor between negative/postive affect and swl


statusswl.senti2 %>% filter(sentiment.score < 0) %>%
        group_by(., userid) %>%
        mutate(neg.affect = sum(sentiment.score)/count)%>%
        .[!duplicated(.$userid), ]-> neg.affect

cor.test(neg.affect$swl,neg.affect$neg.affect)

#0.233827, p<2.2e-16

statusswl.senti2 %>% filter(sentiment.score > 0) %>%
        group_by(., userid) %>%
        mutate(pos.affect = sum(sentiment.score)/count)%>%
        .[!duplicated(.$userid), ]-> pos.affect

cor.test(pos.affect$swl,pos.affect$pos.affect)
#0.07039128, p-value = 0.000317


########################  SESSION 4 JOIN ALL FEATURES  ########################################
#merge all features
statusswl5 %>%
        select(userid,mean.swl,mean.senti,pos.freq,neg.freq,pos.neg)  %>%
        left_join(., topic.id, by = "userid") %>%
        left_join(., liwc2, by = "userid") %>%
        .[, colSums(is.na(.)) != nrow(.)] %>%
        .[complete.cases(.), ] %>%
        .[!duplicated(.$userid), ] -> allFeatures


###################################### SESSION 5 feature selection and prediction ########################
##2000 topics feature selection 

###compute matrix rank 

set.seed(666)
t5 <- allFeatures
ind = sample(2, nrow(t5), replace = TRUE, prob=c(0.7, 0.3))
trainset1 = t5[ind == 1,]
testset1 = t5[ind == 2,]

y = allFeatures$mean.swl
x = allFeatures[3:1988]
x <- as.matrix(x)
cv <- cv.glmnet(x,y,alpha=0.1)

coef(cv,s=0.1)
plot(cv)
cv$lambda.min
c <- coef(cv, s = "lambda.min")


#select == !0 as features
cv_score <- as.matrix(unlist(c))

#lasso prediction using lda topics
set.seed(666)
t5 <- allFeatures
ind = sample(2, nrow(t5), replace = TRUE, prob=c(0.7, 0.3))
trainset1 = t5[ind == 1,]
testset1 = t5[ind == 2,]

y = trainset1$mean.swl
x = as.matrix(trainset1[3:1985])
cv1 <- cv.glmnet(x,y,alpha=1)
c <- coef(cv1, s = "lambda.min")
cv_score <- as.matrix(unlist(c))

testsetx <- as.matrix(testset1[3:1985])
pred2 <- predict(cv1,testsetx,s=c(0.1,0.05,0.01))
cor.test(pred2[,2], testset1$mean.swl)
#0.2517533, p-value = 6.545e-12
rmse(pred2[,2],testset1$mean.swl)
#RMSE=1.334683

cor.test(allFeatures$mean.senti,allFeatures$mean.swl)
#0.2055144, p-value < 2.2e-16

######################### SESSION 6 RANDOM FOREST PREDICTION MODEL #############################
set.seed(66236)
t5 <- allFeatures

ind = sample(2, nrow(t5), replace = TRUE, prob=c(0.7, 0.3))
trainset1 = t5[ind == 1,]
testset1 = t5[ind == 2,]

#naive baseline - betting on the median
md<-median(trainset1$mean.swl) #4.4
naive_pred<-rep_len(md,nrow(testset1)) 
#this has zero standard deviation, which is a problem for computing correlation. 
#we add a very small random number to the prediction
set.seed(9264)
naive_pred_rnd<-naive_pred+runif(length(naive_pred),0,0.001)
cor.test(naive_pred_rnd,testset1$mean.swl)
rmse(naive_pred_rnd,testset1$mean.swl)
#corr=0.001497168, p-value = 0.9676, RMSE:1.371085

set.seed(23778672)

fit1 <- cforest(mean.swl ~ mean.senti+pos.neg+neg.freq+topic588+topic1179+topic205+topic1411+topic700+topic605+topic48
                +topic555+topic939+topic855+topic253+topic1715+topic675+topic1440+topic1725+topic638
                +topic171+topic327+topic217+topic1530+topic51+topic1221+topic470+topic505+topic1819+topic379
                +topic1684+topic314+topic754+topic1873+topic38+topic15+topic126+topic815+topic1620+topic111
                +topic1808+topic1038+topic994+topic321+topic846+topic765+topic259+topic1316+topic1980
                +topic1573+topic812+topic1139+topic551+topic1964+topic1079+topic1590+topic1186+topic1095
                +topic1680+topic630+topic409+topic677+topic53+topic1801+topic479+topic1098+topic142+topic938
                +topic863+topic436+topic539+topic1041+topic1508+topic1543+topic950+topic3+topic1787+topic1540
                +topic1549+topic1171+topic603+topic179+topic1772+topic820+topic1235+topic1043+topic120+topic1625
                +topic610+topic1689+topic811+topic1938+topic425+topic1745+topic867+topic1376+topic23+topic1448
                +topic428+topic1575+topic667+topic1708+topic1478+topic150+topic704+topic1423+topic961+topic592
                +topic427+topic162+topic450+topic956+topic1113+topic569+topic1814+topic1010+topic353+topic1150
                +topic524+topic249+topic1886+topic22+topic90+topic455+topic823+topic708+topic1390+topic530
                +topic1252+we+article+work+home+leisure+number+discrep+anger+negemo+friend+negate+swear+hear
                ,data = trainset1,controls=cforest_unbiased(ntree=1000, mtry= 3))

testset1$Prediction1 <- predict(fit1, testset1, OOB=TRUE)
cor.test(testset1$Prediction1,testset1$mean.swl)
rmse(testset1$Prediction1,testset1$mean.swl)
#Cor:0.3589723, p-value < 2.2e-16,RMSE:1.297639

####variable importance
fit1_varimp <- varimp(fit1)
fit1_varimp
s <- sort(-fit1_varimp2)
fit1_varimp2 <- fit1_varimp[1:50]

library(lattice)
c <- dotplot(sort(fit1_varimp2),xName ='topics',yName ='mean decrease in accuracy',panel=function (x,y){
  panel.dotplot(x, y, col='darkblue', pch=20, cex=1.1)
  panel.abline(v=abs(min(fit1_varimp2)), col = 'red', lty='longdash', lwd=4)
  panel.abline(v=0, col='blue')
})
print(c)
dev.off()


# prediction using liwc

set.seed(6634258)
fit2 <- cforest(mean.swl ~ funct+pronoun+ppron+i+we+you+shehe+they+ipron+article+verb
                +auxverb+past+present+future+adverb+preps+conj+negate+quant+number+swear+social
                +family+friend+humans+affect+posemo+negemo+anx+anger+sad+cogmech+insight+cause
                +discrep+tentat+certain+inhib+incl+excl+percept+see+hear+feel+bio+body+health
                +sexual+ingest+relativ+motion+space+time+work+achieve+leisure+home+money+relig
                +death+assent+nonfl+filler,
                data = trainset1,controls=cforest_unbiased(ntree=1000, mtry= 2))

testset1$Prediction2 <- predict(fit2, testset1, OOB=TRUE)
cor.test(testset1$Prediction2,testset1$mean.swl)
rmse(testset1$Prediction2,testset1$mean.swl)
#corr=0.2881616, p-value = 1.345e-15, RMSE:1.319635

#prediction using LDA topics 

set.seed(2042237)
fit3 <- cforest(mean.swl ~ topic588+topic1179+topic205+topic1411+topic700+topic605+topic48
                +topic555+topic939+topic855+topic253+topic1715+topic675+topic1440+topic1725+topic638
                +topic171+topic327+topic217+topic1530+topic51+topic1221+topic470+topic505+topic1819+topic379
                +topic1684+topic314+topic754+topic1873+topic38+topic15+topic126+topic815+topic1620+topic111
                +topic1808+topic1038+topic994+topic321+topic846+topic765+topic259+topic1316+topic1980
                +topic1573+topic812+topic1139+topic551+topic1964+topic1079+topic1590+topic1186+topic1095
                +topic1680+topic630+topic409+topic677+topic53+topic1801+topic479+topic1098+topic142+topic938
                +topic863+topic436+topic539+topic1041+topic1508+topic1543+topic950+topic3+topic1787+topic1540
                +topic1549+topic1171+topic603+topic179+topic1772+topic820+topic1235+topic1043+topic120+topic1625
                +topic610+topic1689+topic811+topic1938+topic425+topic1745+topic867+topic1376+topic23+topic1448
                +topic428+topic1575+topic667+topic1708+topic1478+topic150+topic704+topic1423+topic961+topic592
                +topic427+topic162+topic450+topic956+topic1113+topic569+topic1814+topic1010+topic353+topic1150
                +topic524+topic249+topic1886+topic22+topic90+topic455+topic823+topic708+topic1390+topic530
                +topic1252,
                data = trainset1,controls=cforest_unbiased(ntree=1000, mtry= 3))

testset1$Prediction1 <- predict(fit3, testset1, OOB=TRUE)
cor.test(testset1$Prediction1,testset1$mean.swl)
rmse(testset1$Prediction1,testset1$mean.swl)
#0.3255, p<2.2e-16, RMSE:1.318288

#prediction using sentiment + lda
set.seed(20247)
fit1 <- cforest(mean.swl ~ mean.senti+pos.neg+neg.freq+topic588+topic1179+topic205+topic1411+topic700+topic605+topic48
                +topic555+topic939+topic855+topic253+topic1715+topic675+topic1440+topic1725+topic638
                +topic171+topic327+topic217+topic1530+topic51+topic1221+topic470+topic505+topic1819+topic379
                +topic1684+topic314+topic754+topic1873+topic38+topic15+topic126+topic815+topic1620+topic111
                +topic1808+topic1038+topic994+topic321+topic846+topic765+topic259+topic1316+topic1980
                +topic1573+topic812+topic1139+topic551+topic1964+topic1079+topic1590+topic1186+topic1095
                +topic1680+topic630+topic409+topic677+topic53+topic1801+topic479+topic1098+topic142+topic938
                +topic863+topic436+topic539+topic1041+topic1508+topic1543+topic950+topic3+topic1787+topic1540
                +topic1549+topic1171+topic603+topic179+topic1772+topic820+topic1235+topic1043+topic120+topic1625
                +topic610+topic1689+topic811+topic1938+topic425+topic1745+topic867+topic1376+topic23+topic1448
                +topic428+topic1575+topic667+topic1708+topic1478+topic150+topic704+topic1423+topic961+topic592
                +topic427+topic162+topic450+topic956+topic1113+topic569+topic1814+topic1010+topic353+topic1150
                +topic524+topic249+topic1886+topic22+topic90+topic455+topic823+topic708+topic1390+topic530
                +topic1252,data = trainset1,controls=cforest_unbiased(ntree=1000, mtry= 3))

testset1$Prediction1 <- predict(fit1, testset1, OOB=TRUE)
cor.test(testset1$Prediction1,testset1$mean.swl)
rmse(testset1$Prediction1,testset1$mean.swl)
#corr=0.3405363, p-value < 2.2e-16, RMSE:1.306313


############# SESSION 7 predict user behaviors with machine predict swl and self-report swl ###############

#this RF model recreates the best performing model from the previous section, but doesn't split the data.
# it builds a model on all the data and uses OOB estimate as the prediction for each sample. 
# This OOB prediction of SWL is compared with self-reported CES-D to see how modeled SWL might 'predict' (share information) depression.

allFeature2 <- allFeatures
set.seed(2564235)
allFeature2$Prediction <- predict(cforest(mean.swl ~ pos.neg+neg.freq+topic588+topic1179+topic205+topic1411+topic700+topic605+topic48
                                          +topic555+topic939+topic855+topic253+topic1715+topic675+topic1440+topic1725+topic638
                                          +topic171+topic327+topic217+topic1530+topic51+topic1221+topic470+topic505+topic1819+topic379
                                          +topic1684+topic314+topic754+topic1873+topic38+topic15+topic126+topic815+topic1620+topic111
                                          +topic1808+topic1038+topic994+topic321+topic846+topic765+topic259+topic1316+topic1980
                                          +topic1573+topic812+topic1139+topic551+topic1964+topic1079+topic1590+topic1186+topic1095
                                          +topic1680+topic630+topic409+topic677+topic53+topic1801+topic479+topic1098+topic142+topic938
                                          +topic863+topic436+topic539+topic1041+topic1508+topic1543+topic950+topic3+topic1787+topic1540
                                          +topic1549+topic1171+topic603+topic179+topic1772+topic820+topic1235+topic1043+topic120+topic1625
                                          +topic610+topic1689+topic811+topic1938+topic425+topic1745+topic867+topic1376+topic23+topic1448
                                          +topic428+topic1575+topic667+topic1708+topic1478+topic150+topic704+topic1423+topic961+topic592
                                          +topic427+topic162+topic450+topic956+topic1113+topic569+topic1814+topic1010+topic353+topic1150
                                          +topic524+topic249+topic1886+topic22+topic90+topic455+topic823+topic708+topic1390+topic530
                                          +topic1252+we+article+work+home+leisure+number+discrep+anger+negemo+friend+negate+swear+hear,
                                          data = allFeature2,controls=cforest_unbiased(ntree=1000, mtry= 2)),OOB= TRUE)

cor.test(allFeature2$Prediction,allFeature2$mean.swl)
rmse(allFeature2$Prediction,allFeature2$mean.swl)
#Cor=0.3249587, p-value < 2.2e-16, RMSE: 1.327758

########################SESSION 7 REGRESSION MODEL PREDICT USER BEHAVIOR ##############################

####merge with depression
allFeature2 %>% select(userid, mean.senti, Prediction, mean.swl,neg.freq,pos.freq) ->reg


dep <- read.csv("dep.csv", header = TRUE)
dep$sum <- rowSums(dep[8:27])

dep[!duplicated(dep$userid),] %>% 
        select(userid, sum) %>%
        right_join(., reg, by = "userid") %>%
        .[complete.cases(.$sum),]-> dep.reg
#386 rows

cor.test(dep.reg$mean.swl,dep.reg$sum)
#corr=-0.2725348, p-value = 5.316e-08

cor.test(dep.reg$sum,dep.reg$Prediction)
#corr=-0.2298818, p-value = 5.041e-06

cor.test(dep.reg$sum,dep.reg$neg.freq)
#corr=0.1582397, p-value = 0.001818

#naive baseline - betting on the median
md_dep<-median(dep.reg$sum) #44
naive_pred<-rep_len(md_dep,nrow(dep.reg)) 
#this has zero standard deviation, which is a problem for computing correlation. 
#we add a very small random number to the prediction
set.seed(945664)
naive_pred_rnd<-naive_pred+runif(length(naive_pred),0,0.001)
cor.test(naive_pred_rnd,dep.reg$sum)
#-0.02110829  p-value = 0.6793
rmse(naive_pred_rnd,dep.reg$sum)
# 9.152087

####Split into training and test set and use RF to predict CES-D score (dep.reg$sum) 
set.seed(42451)
ind = sample(2, nrow(dep.reg), replace = TRUE, prob=c(0.7, 0.3))
trainset3 = dep.reg[ind == 1,]
testset3 = dep.reg[ind == 2,]

set.seed(6389953)
fit_dep <- cforest(sum~ mean.senti+pos.freq+neg.freq, data=trainset3,controls=cforest_unbiased(ntree=1000, mtry= 3))
testset3$pred3<- predict(fit_dep,testset3,OOB=T)
cor.test(testset3$pred3, testset3$sum)
rmse(testset3$pred3, testset3$sum)
#0.07866766   p-value = 0.3812 RMSE: 8.458673 (in a range of -20:80)

set.seed(3347886)
fit_dep <- cforest(sum~ mean.swl+mean.senti+pos.freq+neg.freq, data=trainset3,controls=cforest_unbiased(ntree=1000, mtry= 2))
summary(fit_dep)
testset3$pred3<- predict(fit_dep,testset3,OOB=T)
cor.test(testset3$pred3, testset3$sum)
rmse(testset3$pred3, testset3$sum)
#Corr=0.2846209   , p-value = 0.001237, RMSE: 7.904497

set.seed(3468956)
fit_dep <- cforest(sum~ Prediction+mean.senti+pos.freq+neg.freq, data=trainset3,controls=cforest_unbiased(ntree=1000, mtry= 2))
summary(fit_dep)
testset3$pred3<- predict(fit_dep,testset3, OOB=T)
cor.test(testset3$pred3, testset3$sum)
rmse(testset3$pred3, testset3$sum)
#Corr=0.2503407  , p-value = 0.004695, RMSE: 7.96275



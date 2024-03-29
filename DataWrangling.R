# Import the relavant packages
library(jsonlite)     #Importing JSON Files
library(glmnet)       #Building Linear Models
library(ggplot2)      #Plotting Graphs
library(tidyverse)    #Manipulating the Data
library(corrplot)     #Plotting Correlation Matrices
library(sandwich)     #Robust Standard Errors
library(lmtest)       #Testing the Linear Model
library(caret)        #Splitting Data into Train and Test
require(MASS)         #Used for Ordinal Prediction
require(tree)         #Used for Decision Trees
require(rpart)        #Used for Decision Trees
require(rpart.plot)   #Plot Decision Trees


# Clear the R Workspace and free up unused RAM
cat("\014")  
rm(list=ls())
gc()

# Set Working Directory
setwd("D:/Documents/EC349_Project")

##############################

# Load in json files and save them as R datasets
business_data <- stream_in(file("yelp_academic_dataset_business.json"))
saveRDS(business_data, file = "business_data.rds")

checkin_data <- stream_in(file("yelp_academic_dataset_checkin.json"))
saveRDS(checkin_data, file = "checkin_data.rds")

tip_data <- stream_in(file("yelp_academic_dataset_tip.json"))
saveRDS(tip_data, file = "tip_data.rds")

#Load in datasets to avoid streaming them in every time
tip_data <- readRDS("tip_data.rds")

checkin_data <- readRDS("checkin_data.rds")

business_data <- readRDS("business_data.rds")

load("yelp_review_small.Rda")

load("yelp_user_small.Rda")

##############################################

##Explore the data
#Business Data:
names(business_data)
dim(business_data)
head(business_data)
#Check the percentage of missing fields
(colSums(!is.na(business_data))/nrow(business_data))*100 
#Removes the open text fields and fields with large amounts of missing data
business_data[c('name','address','postal_code','attributes','hours','categories')] <- list(NULL)
#Renames the fields to avoid duplication with other data sets
names(business_data) <- c('business_id','city','state','latitude','longitude','business_stars','business_review_count','is_open')
(colSums(!is.na(business_data))/nrow(business_data))*100


#Checkin Data:
names(checkin_data)
head(checkin_data)
#Splits the checkin dates into a string and sums to find the number of checkins for each business
checkin_data <- checkin_data %>% mutate(checkin_number = 1 + str_count(date, ","))
#Removes the surplus date field
checkin_data[c('date')] <- list(NULL)

#Review Data:
names(review_data_small)
dim(review_data_small)
summary(review_data_small)
#Removes the open text field
review_data_small[c('text')] <- list(NULL)
#Seperates the date field into year, month and day, making them all numeric
review_data_small <- review_data_small %>% separate(date,c('year','month','day'))
review_data_small$year <- as.numeric(review_data_small$year)
review_data_small$month <- as.numeric(review_data_small$month)
review_data_small$day <- as.numeric(review_data_small$day)
#Checks for percentage of missing data
(colSums(!is.na(review_data_small))/nrow(review_data_small))*100

#Tip Data
names(tip_data)
dim(tip_data)
head(tip_data)
tip_data %>% summary()
#Remove text column
tip_data[c('text','date')] <- list(NULL) 
#Adds an instrument that when combined with the other data sets should capture whether there was a tip
tip_data <- tip_data %>% mutate(tip = 1)
#Renames to avoid duplicated IDs
names(tip_data) <- c('user_id','business_id','tip_compliments','tip')

#User Data
names(user_data_small)
dim(user_data_small)
summary(user_data_small)
#Removes text fields
user_data_small[c('name','friends','elite')] <- list(NULL)
#Separates the yelping since field into a year only
user_data_small <- user_data_small %>% separate('yelping_since',c('yelping_since_year'))
user_data_small$yelping_since_year <- as.numeric(user_data_small$yelping_since_year)
#Renames all the fields to avoid duplication
names(user_data_small) <- c('user_id','user_review_count','yelping_since','user_useful','user_funny','user_cool','user_fans','user_stars','compliment_hot','compliment_more','compliment_profile','compliment_cute','compliment_list','compliment_note','compliment_plain','compliment_cool','compliment_funny','compliment_writer','compliment_photos')
#Checks the percentage of missing data
(colSums(!is.na(user_data_small))/nrow(user_data_small))*100

#####################################

#Join the data sets together and removing them once combined
review_data_small <- left_join(review_data_small,user_data_small,'user_id')
rm(user_data_small)
review_data_small <- left_join(review_data_small,business_data,'business_id')
rm(business_data)
review_data_small <- left_join(review_data_small,checkin_data,'business_id')
rm(checkin_data)
#Due to the nature of tip data having multiple potential matches, the joining process added observations
#To the data set (Around 23,000), so it has been left out to avoid spoiling the data
#review_data_small <- left_join(review_data_small,tip_data,by = c('business_id' = 'business_id','user_id'='user_id'))
rm(tip_data)
#Checks to see the percentages of missing data
(colSums(!is.na(review_data_small))/nrow(review_data_small))*100

#Remove the IDs to make modelling easier
review_data_small[c('review_id','user_id','business_id')] <- list(NULL)

#Save
save(review_data_small,file = "review_data.Rda")
#load(file = "review_data.Rda")

#############################

#Split the data into train and test
set.seed(1)
#Partition the data
parts = createDataPartition(review_data_small$stars, p = 1-(10002/nrow(review_data_small)), list = F)
#Select the training and test data using the random selection above
train = review_data_small[parts, ]
test = review_data_small[-parts, ]
#Remove the unnecessary variables to save RAM
rm(parts)
rm(review_data_small)

####################################

(colSums(!is.na(train))/nrow(train))*100
#Sort out the missing values:
train %>% summary()
#User Review Count
ggplot(train, aes(user_review_count)) + geom_histogram()
train <- train %>% mutate(user_review_count = ifelse(is.na(user_review_count), 0, user_review_count))
ggplot(train, aes(user_review_count)) + geom_histogram()
#Yelping Since
ggplot(train, aes(yelping_since)) + geom_histogram()
ggplot(train, aes(year)) + geom_histogram()
#Despite the difference in distributions, the only available information we have for the user
#Is when they wrote the review,and it would be wrong to attribute them being on yelp any
#Earlier than when they wrote their review.
train <- train %>% mutate(yelping_since = ifelse(is.na(yelping_since), year, yelping_since))
ggplot(train, aes(yelping_since)) + geom_histogram()
#User Values
#As most of the user values have similar distributions they have all been treated the same,
#As most of the given data is 0, and since they can't have recieved any praise or comments
#on their account if they didn't have one, they have been treated as if they had an account
#with 0 reactions on any of their posts.
ggplot(train, aes(user_useful)) + geom_histogram()
train <- train %>% mutate(user_useful = ifelse(is.na(user_useful), 0, user_useful),
                          user_funny = ifelse(is.na(user_funny), 0, user_funny),
                          user_cool = ifelse(is.na(user_cool), 0, user_cool),
                          user_fans = ifelse(is.na(user_fans), 0, user_fans),
                          compliment_hot = ifelse(is.na(compliment_hot), 0, compliment_hot),
                          compliment_more = ifelse(is.na(compliment_more), 0, compliment_more),
                          compliment_profile = ifelse(is.na(compliment_profile), 0, compliment_profile),
                          compliment_cute = ifelse(is.na(compliment_cute), 0, compliment_cute),
                          compliment_list = ifelse(is.na(compliment_list), 0, compliment_list),
                          compliment_note = ifelse(is.na(compliment_note), 0, compliment_note),
                          compliment_plain = ifelse(is.na(compliment_plain), 0, compliment_plain),
                          compliment_cool = ifelse(is.na(compliment_cool), 0, compliment_cool),
                          compliment_funny = ifelse(is.na(compliment_funny), 0, compliment_funny),
                          compliment_writer = ifelse(is.na(compliment_writer), 0, compliment_writer),
                          compliment_photos = ifelse(is.na(compliment_photos), 0, compliment_photos)
)
#User stars
#User stars are again going to be attributed to the review that they have given, an approach that
#will only work in the training data set. The test data will need to use a median or mean value
#from the training data.
ggplot(train, aes(user_stars)) + geom_histogram()
train <- train %>% mutate(user_stars = ifelse(is.na(user_stars), median(user_stars, na.rm=TRUE), user_stars))
ggplot(train, aes(user_stars)) + geom_histogram()

#Checkin Data
ggplot(train, aes(checkin_number)) + geom_histogram()
train <- train %>% mutate(checkin_number = ifelse(is.na(checkin_number),0,checkin_number))

#################################################

#Do the same for the test data:
test <- test %>% mutate(user_review_count = ifelse(is.na(user_review_count), 0, user_review_count))
test <- test %>% mutate(yelping_since = ifelse(is.na(yelping_since), year, yelping_since))
test <- test %>% mutate(user_useful = ifelse(is.na(user_useful), 0, user_useful),
                          user_funny = ifelse(is.na(user_funny), 0, user_funny),
                          user_cool = ifelse(is.na(user_cool), 0, user_cool),
                          user_fans = ifelse(is.na(user_fans), 0, user_fans),
                          compliment_hot = ifelse(is.na(compliment_hot), 0, compliment_hot),
                          compliment_more = ifelse(is.na(compliment_more), 0, compliment_more),
                          compliment_profile = ifelse(is.na(compliment_profile), 0, compliment_profile),
                          compliment_cute = ifelse(is.na(compliment_cute), 0, compliment_cute),
                          compliment_list = ifelse(is.na(compliment_list), 0, compliment_list),
                          compliment_note = ifelse(is.na(compliment_note), 0, compliment_note),
                          compliment_plain = ifelse(is.na(compliment_plain), 0, compliment_plain),
                          compliment_cool = ifelse(is.na(compliment_cool), 0, compliment_cool),
                          compliment_funny = ifelse(is.na(compliment_funny), 0, compliment_funny),
                          compliment_writer = ifelse(is.na(compliment_writer), 0, compliment_writer),
                          compliment_photos = ifelse(is.na(compliment_photos), 0, compliment_photos)
)
test <- test %>% mutate(user_stars = ifelse(is.na(user_stars), median(user_stars, na.rm=TRUE), user_stars))
test <- test %>% mutate(checkin_number = ifelse(is.na(checkin_number),0,checkin_number))

(colSums(!is.na(test))/nrow(test))*100

save.image()

#Unneeded from when I was trying to reduce the RAM consumption when modelling
#save(test, file = "test.Rda")
#load(file = "test.Rda")
#rm(test)
#gc()

#######################################

#Explore the data - Look at some key variables and their interaction with stars
ggplot(train, aes(x=stars)) + geom_bar()
ggplot(train, aes(x=user_review_count, y=stars)) + geom_point() + geom_smooth(method="lm")
ggplot(train, aes(x=business_review_count, y=stars)) + geom_point() + geom_smooth(method="lm")
ggplot(train, aes(x=user_stars, y=stars)) + geom_point() + geom_smooth(method="lm") 
ggplot(train, aes(x=business_stars, y=stars)) + geom_point() + geom_smooth(method="lm")
ggplot(train, aes(x=business_stars, y=stars)) + geom_bin_2d() + geom_smooth(method = "lm")
ggplot(train, aes(x=year, y=stars)) + geom_point() + geom_smooth(method = "lm")

#Looks at the correlation matrix between variables
cor(train)
corrplot(cor(train[,-c(26,27)], use = "na.or.complete"))

#Tests some of the key variables and their correlation with stars
cor.test(test$user_stars,test$stars)
cor.test(test$business_stars,test$stars)

#######################################

#Remove city and state as variables from the data:
train[c('city','state')] <- list(NULL)
test[c('city','state')] <- list(NULL)

#Initial Linear Model
linear1 <- glm(stars ~ ., data = train, family = gaussian)
summary(linear1)
linear1_prediction <- predict(linear1,newdata=test)
linear1_error <- mean((test$stars - linear1_prediction)^2)

#Linear Model with Poisson Distribution
linear2 <- glm(stars ~ ., data = train, family = poisson)
summary(linear2)
linear2_prediction <- predict(linear2,newdata=test)
linear2_error <- mean((test$stars - linear2_prediction)^2)
summary(linear2_prediction)

#Linear Model with fewer variables
linear3 <- glm(stars ~ useful + funny + cool + year + month + yelping_since + user_useful + user_funny + user_cool + user_fans + user_stars + compliment_list + compliment_writer + business_stars + is_open +checkin_number, data = train, family = poisson)
summary(linear3)
linear3_prediction <- predict(linear3,newdata=test)
linear3_error <- mean((test$stars - linear3_prediction)^2)

#LASSO Model
lasso1 <- glmnet(as.matrix(train[,-1]), as.matrix(train[,1]), lambda = 1, alpha = 1)
coef(lasso1)
lasso1_prediction <- predict(lasso1, s = 1, newx = as.matrix(test[,-1]))
lasso1_error <- mean((test$stars - lasso1_prediction)^2)

#LASSO with cross validation
#Find the possible values of Lambda
cross_validation <- cv.glmnet(as.matrix(train[,-1]), as.matrix(train[,1]), alpha = 1, nfolds = 3)
plot(cross_validation)
#Find the one that minimises MSE
lambda_lasso <- cross_validation$lambda.min
#Run the lasso model with that optimal value of Lambda
lasso2 <- glmnet(as.matrix(train[,-1]), as.matrix(train[,1]), lambda = lambda_lasso, alpha = 1)
coef(lasso2)
#Predict using the new model
lasso2_prediction <- predict(lasso2, s = lambda_lasso, newx = as.matrix(test[,-1]))
#Find the MSE
lasso2_error <- mean((test$stars - lasso2_prediction)^2)
summary(lasso2_prediction)
#Clean the output into integers
lasso2_prediction <- round(lasso2_prediction, 0)
lasso2_prediction[lasso2_prediction<1] <- 1
lasso2_prediction[lasso2_prediction>5] <- 5
summary(lasso2_prediction)
#Test the new accuracy and MSE
lasso2_error <- mean((test$stars - lasso2_prediction)^2)
lasso2_accuracy <- sum(lasso2_prediction == test$stars)/nrow(test)


#Clean the output of the linear model as well
summary(linear1_prediction)
linear1_prediction <- round(linear1_prediction, 0)
linear1_prediction[linear1_prediction<1] <- 1
linear1_prediction[linear1_prediction>5] <- 5
summary(linear1_prediction)
#Test the accuracy and error of the new model
linear1_error <- mean((test$stars - linear1_prediction)^2)
linear1_accuracy <- sum(linear1_prediction == test$stars)/nrow(test)

#Implement a cross-validated Ridge Model
cross_validation1 <- cv.glmnet(as.matrix(train[,-1]), as.matrix(train[,1]), alpha = 0, nfolds = 3)
plot(cross_validation1)
ridge_lambda <- cross_validation1$lambda.min
ridge1 <- glmnet(train[,-1], train[,1], alpha = 0, lambda = ridge_lambda, thresh = 1e-12)

ridge_prediction <- predict(ridge1, s = ridge_lambda, newx = as.matrix(test[,-1]))
ridge_error <- mean((ridge_prediction - test[,1]) ^ 2)

#Clean the output and check accuracy of ridge model
summary(ridge_prediction)
ridge_prediction <- round(ridge_prediction, 0)
ridge_prediction[ridge_prediction<1] <- 1
ridge_prediction[ridge_prediction>5] <- 5
summary(ridge_prediction)
ridge_error <- mean((test$stars - ridge_prediction)^2)
ridge_accuracy <- sum(ridge_prediction == test$stars)/nrow(test)

#Implementing an ordinal model
#Convert stars into a categorical variable
train$stars <- as.factor(train$stars)

#Run the ordinal model with business_stars and user_stars
ordinal <- polr(stars ~ year + month + yelping_since + user_stars + business_stars + is_open, data = train, Hess=TRUE)
summary(ordinal)
ordinal_prediction <- predict(ordinal, newdata = test)
ordinal_error <- mean((test$stars - as.numeric(ordinal_prediction))^2)
ordinal_accuracy <- sum(as.numeric(ordinal_prediction) == test$stars)/nrow(test)
summary(ordinal_prediction)

set.seed(1)
parts1 = createDataPartition(train$stars, p = 0.1, list = F)
train1 = train[parts1, ]
rm(parts1)

#LASSO with multinomial
#Find the possible values of Lambda
cross_validation_multi <- cv.glmnet(as.matrix(train1[,-1]), as.matrix(train1[,1]), alpha = 1, nfolds = 3,family="multinomial",type.multinomial="grouped")
plot(cross_validation_multi)
#Find the one that minimises MSE
lambda_lasso_multi <- cross_validation_multi$lambda.min
#Run the lasso model with that optimal value of Lambda
lasso_multi <- glmnet(as.matrix(train[,-1]), as.matrix(train[,1]), lambda = lambda_lasso_multi, alpha = 1,family="multinomial")
coef(lasso_multi)
#Predict using the new model
lasso_prediction_multi <- predict(lasso_multi, s = lambda_lasso_multi, newx = as.matrix(test[,-1]),type="class")
#Find the Errors and Accuracy
summary(as.numeric(lasso_prediction_multi))
lasso_multi_error <- mean((test$stars - as.numeric(lasso_prediction_multi)^2))
lasso2_accuracy <- sum(as.numeric(lasso_prediction_multi) == test$stars)/nrow(test)
                          

#Remove the prediction matrices to save RAM
rm(linear1_prediction)
rm(linear2_prediction)
rm(linear3_prediction)
rm(lasso1_prediction)
rm(lasso2_prediction)
rm(ridge_prediction)
rm(ordinal_prediction)

##########################################

#Decision Tree with 'rpart' 
#Train the tree
tree1 <- rpart(stars ~ ., data = train)
#Plot the tree
rpart.plot(tree1)
#Predict using the tree
tree1_prediction <- predict(tree1, newdata = test, type="class")
summary(tree1)
summary(tree1_prediction)
#Determine the Error and Accuracy
tree1_error <- sum(as.numeric(tree1_prediction) != test$stars)/nrow(test)
tree1_accuracy <- sum(as.numeric(tree1_prediction) == test$stars)/nrow(test)


#########################
#Attempts to improve the decision tree were hampered by severe
#problems in handling the computational load so despite best efforts
#this has been removed from the analysis


#Remove Excess variables to reduce the computational load
#train1$stars <- as.numeric(train1$stars)
#corrplot(cor(train1))
#train1 <- train1[,c(1,4,5,8,11,14,24,26,27,28,29,30)]
#corrplot(cor(train1))
#train1$stars <- as.factor(train1$stars)

#Decision Tree with Boosting
#boost <- boosting(stars~., data=train1, boos=TRUE, mfinal=4)
#summary(boost)
#boost_prediction <- predict(boost, newdata = test)
#boost_prediction

#Random Forests
#set.seed(1312)
#model_RF<-randomForest(stars~.,data=train, ntree=25)
#pred_RF_test = predict(model_RF, test)
#mean(model_RF[["err.rate"]])


#Decision Tree with Bagging
#bag <- bagging(stars~., data=train1, nbagg = 5, coob = TRUE, control = rpart.control(minsplit = 1000, cp = 10))
#bag #MSE 1.3074



# First run /Users/srz223/Documents/courses/Benchmarking/repos/cygate-main
# Getting results from that run... 

# Load libraries 
library(readr)
library(dplyr)

# Load real and cygate-predicted labels of test_x
test_y <- read_csv("~/Documents/courses/Benchmarking/data/26_Levine/test_y.csv")
test_x_cygated <- read_csv("~/Documents/courses/Benchmarking/data/26_Levine/test_x_cygated.csv")

# Check dims
dim(test_y)
dim(test_x_cygated)

# Extract labels
test_y_char <- test_y$x
pred_labels <- test_x_cygated$Gated

# Quick performance metrics
cat("\nAccuracy:\n")
acc <- mean(pred_labels == test_y_char)
print(acc)

cat("\nConfusion matrix:\n")
print(table(Predicted = pred_labels, True = test_y_char))


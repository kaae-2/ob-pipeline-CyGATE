
library(dplyr)
library(glue)
library(stringr)

# Training data with label column
test_y_path <- glue("/home/projects/dp_immunoth/people/helweg/projects/benchmarking/prep_data/out/test_y.zip")
pred_y_path <- glue("/home/projects/dp_immunoth/people/helweg/projects/benchmarking/ob-pipeline-CyGATE/predicted.zip")

# LOAD Y TEST
test_y_zip_contents <- unzip(test_y_path, list = TRUE)$Name
csv_files <- test_y_zip_contents[grepl("\\.csv$", test_y_zip_contents)]

test_y_list <- lapply(csv_files, function(f) {
  read.csv(unz(test_y_path, f))
})

# LOAD Y PRED
pred_y_zip_contents <- unzip(pred_y_path, list = TRUE)$Name
csv_files <- pred_y_zip_contents[grepl("\\.csv$", pred_y_zip_contents)]

pred_y_list <- lapply(csv_files, function(f) {
  read.csv(unz(pred_y_path, f))
})

# COMPARE


# Test accuracy 
for (sample in 1:length(test_y_list)){
  
  # sample <- 1

  # Extract y test and pred for the current sample
  test_y <- test_y_list[[sample]][, 1]
  pred_y <- pred_y_list[[sample]][, 1]

  # Accuracy
  acc <- mean(pred_y == test_y)
  print(acc)
  
}

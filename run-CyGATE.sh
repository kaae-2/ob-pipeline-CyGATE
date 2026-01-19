# for computerome:
# module load tools 
# module load gcc/14.2.0 
# module load tbb/2021.8.0
# module load intel/basekit/INITIALIZE/2023.0.0
# module load intel/basekit/mkl/2023.0.0
# module load compiler-rt/2023.0.0
# module load R/4.5.0  
# module load jdk/11.0.1  

#!/bin/bash
set -euo pipefail

# -------------------------------
# PATHS
# -------------------------------
dataset_path="/home/projects/dp_immunoth/people/helweg/projects/benchmarking/prep_data/out"

tmp_train_dir="/home/projects/dp_immunoth/people/helweg/projects/benchmarking/ob-pipeline-CyGATE/tmp_train_unzip"
tmp_test_dir="/home/projects/dp_immunoth/people/helweg/projects/benchmarking/ob-pipeline-CyGATE/tmp_test_unzip"

foo_dir="/home/projects/dp_immunoth/people/helweg/projects/benchmarking/ob-pipeline-CyGATE/CyGATE_foo_files"
Training_UngatedCellLabel="Ungated"

jar_file_path="/home/projects/dp_immunoth/people/helweg/projects/benchmarking/ob-pipeline-CyGATE/cygate-main/CyGate_v1.02.jar"

pred_dir="/home/projects/dp_immunoth/people/helweg/projects/benchmarking/ob-pipeline-CyGATE/predicted"
pred_zip_dir="/home/projects/dp_immunoth/people/helweg/projects/benchmarking/ob-pipeline-CyGATE/predicted.zip"


mkdir -p "$foo_dir"
mkdir -p "$tmp_train_dir"
mkdir -p "$tmp_train_dir/train_xy"
mkdir -p "$tmp_test_dir"
mkdir -p "$pred_dir"

# -------------------------------
# UNZIP TRAINING X AND Y
# -------------------------------

unzip -o -j "$dataset_path/train_x.zip" -d "$tmp_train_dir/train_x"
unzip -o -j "$dataset_path/train_y.zip" -d "$tmp_train_dir/train_y"
unzip -o -j "$dataset_path/test_x.zip" -d "$tmp_test_dir"

# -------------------------------
# MERGE TRAIN X AND Y
# -------------------------------
# Assumes matching filenames between train_x and train_y
for xfile in "$tmp_train_dir/train_x"/*.csv; do
    
    # Extract unique sample identifier 
    base=$(basename "$xfile" .csv)        # e.g., "1" from "1.csv"
    number=$(echo "$base" | cut -d'_' -f3)
    
    # Full path to train_x and train_x
    x_train_file="$tmp_train_dir/train_x/train_x_$number.csv"
    y_train_file="$tmp_train_dir/train_y/train_y_$number.csv"

    # N rows
    n_row_x=$(wc -l < "$x_train_file")
    n_row_y=$(wc -l < "$y_train_file")
    
    if [ $n_row_x -ne $n_row_x ]; then
      echo "Training x and y of sample $number does not contain same number of cells."
      echo "N cells training x: $n_row_x"
      echo "N cells training y: $n_row_y"
    fi 
    
    # Combine x and y train in one file which is needed for CyGATE
    paste -d "," "$x_train_file" "$y_train_file" > "$tmp_train_dir/train_xy/train_xy_$number.csv"

done

# -------------------------------
# CREATE foo.txt
# -------------------------------
foo_file="$foo_dir/foo.txt" > "$foo_file"

# Add training sample lines
for xyfile in "$tmp_train_dir/train_xy"/train_xy_*.csv; do
    echo "Training.Sample= $xyfile" >> "$foo_file"
done

echo "" >> "$foo_file"
echo "Training.UngatedCellLabel= $Training_UngatedCellLabel" >> "$foo_file"
echo "" >> "$foo_file"

# Add test sample lines
shopt -s extglob  # enable extended globbing

for testfile in "$tmp_test_dir"/test_x_+([0-9]).csv; do
    # excludes *_cygated.csv
    echo "Data.Sample= $testfile" >> "$foo_file"
done

shopt -u extglob

# -------------------------------
# RUN CyGATE
# -------------------------------

java -jar "$jar_file_path" --c "$foo_file"

# -------------------------------
# WRAP UP OUTPUT 
# -------------------------------

for cygated in "$tmp_test_dir"/test_x_*_cygated.csv; do

  # Extract unique sample identifier 
  base=$(basename "$cygated" .csv)        # e.g., "1" from "1.csv"
  number=$(echo "$base" | cut -d'_' -f3)

  # Extract predicted cell types 
  awk -F',' '{print $NF}' $cygated > "$pred_dir/pred_$number.csv"
  
done

zip $pred_zip_dir "$pred_dir"/*.csv 


# -------------------------------
# CLEANUP
# -------------------------------
# rm -rf "$tmp_train_dir"
# rm -rf "$tmp_test_dir"
# rm -rf "$foo_dir"



#!/bin/bash
set -euo pipefail

# Parse arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --data.train_matrix)
            DATA_TRAIN_MATRIX="$2"
            shift 2
            ;;
        --data.train_labels)
            DATA_TRAIN_LABELS="$2"
            shift 2
            ;;
        --data.test_matrix)
            DATA_TEST_MATRIX="$2"
            shift 2
            ;;
        --output_dir|-o)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --name|-n)
            NAME="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check required arguments
if [[ -z "${DATA_TRAIN_MATRIX:-}" ]]; then
    echo "Error: --data.train_matrix is required"
    exit 1
fi
if [[ -z "${DATA_TRAIN_LABELS:-}" ]]; then
    echo "Error: --data.train_labels is required"
    exit 1
fi
if [[ -z "${DATA_TEST_MATRIX:-}" ]]; then
    echo "Error: --data.test_matrix is required"
    exit 1
fi

# Print parsed arguments (for debug)
echo "Train matrix: $DATA_TRAIN_MATRIX"
echo "Train labels: $DATA_TRAIN_LABELS"
echo "Test matrix: $DATA_TEST_MATRIX"
echo "Output dir: $OUTPUT_DIR"
echo "Dataset name: $NAME"

# -------------------------------
# PATHS
# -------------------------------

tmp_train_dir=$(mktemp -d)
tmp_test_dir=$(mktemp -d)
foo_dir=$(mktemp -d)
Training_UngatedCellLabel="Ungated" # TODO: UPDATE THIS
tmp_pred=$(mktemp -d)

TMP_JAR=$(mktemp -d)
wget "https://github.com/HanyangBISLab/cygate/raw/main/CyGate_v1.02.jar" -O "$TMP_JAR/CyGate_v1.02.jar"
echo "JAR file downloaded"

# PATHS FOR LOCAL TEST RUN 
# tmp_train_dir="/Users/srz223/Documents/courses/Benchmarking/repos/ob-pipeline-CyGATE/tmp_train"
# tmp_test_dir="/Users/srz223/Documents/courses/Benchmarking/repos/ob-pipeline-CyGATE/tmp_test"
# foo_dir="/Users/srz223/Documents/courses/Benchmarking/repos/ob-pipeline-CyGATE/tmp_foo"
# TMP_JAR=$foo_dir
# tmp_pred="/Users/srz223/Documents/courses/Benchmarking/repos/ob-pipeline-CyGATE/tmp_pred"
# OUTPUT_DIR="/Users/srz223/Documents/courses/Benchmarking/repos/ob-pipeline-CyGATE/tmp_out"

echo "Making tmp dirs..."
mkdir -p "$foo_dir"
mkdir -p "$tmp_train_dir/train_x"
mkdir -p "$tmp_train_dir/train_y"
mkdir -p "$tmp_train_dir/train_xy"
mkdir -p "$tmp_test_dir"
mkdir -p "$tmp_pred"

# -------------------------------
# UNZIP TRAINING X AND Y
# -------------------------------
echo "Unzipping data..."

tar -xzvf $DATA_TRAIN_MATRIX -C "$tmp_train_dir/train_x"
tar -xzvf $DATA_TRAIN_LABELS -C "$tmp_train_dir/train_y"
tar -xzvf $DATA_TEST_MATRIX -C "$tmp_test_dir"

# -------------------------------
# MERGE TRAIN X AND Y
# -------------------------------
echo "Merging train x and y..."
# Assumes matching filenames between train_x and train_y
for xfile in "$tmp_train_dir/train_x"/*.csv; do

    # Extract sample number
    base=$(basename "$xfile" .csv)
    number=$(echo "$base" | cut -d"-" -f3)

    x_train_file="$tmp_train_dir/train_x/data_import-data-$number.csv"
    y_train_file="$tmp_train_dir/train_y/data_import-label-$number.csv"

    n_row_x=$(wc -l < "$x_train_file")
    n_row_y=$(wc -l < "$y_train_file")

    if [ "$n_row_x" -ne "$n_row_y" ]; then
        echo "Mismatch in number of rows for sample $number: x=$n_row_x y=$n_row_y"
        continue
    fi

    combined_file="$tmp_train_dir/train_xy/train_xy_$number.csv"

    # Combine x and y
    paste -d "," "$x_train_file" "$y_train_file" > "$combined_file"

    # --- Generate header robustly ---
    # Take first row, remove trailing commas, count fields
    first_row=$(head -1 "$x_train_file" | sed 's/,+$//')
    n_col=$(echo "$first_row" | awk -F',' '{print NF}')

    # Build header: col1,col2,...,colN,label
    header=$(printf "col%s," $(seq 1 $n_col))
    header=${header%,} # remove trailing comma
    header="$header,label"

    # Prepend header safely
    { echo "$header"; cat "$combined_file"; } > "${combined_file}.tmp" && mv "${combined_file}.tmp" "$combined_file"

done


# -------------------------------
# CREATE foo.txt
# -------------------------------
echo "Creating foo file..."

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

# Loop over test CSVs
for testfile in "$tmp_test_dir/data_import-data-"+([0-9]).csv; do
    # Skip files that might already have *_cygated.csv
    [[ "$testfile" == *_cygated.csv ]] && continue

    # Count columns in the first row, ignoring trailing commas
    first_row=$(head -1 "$testfile" | sed 's/,+$//')
    n_col=$(echo "$first_row" | awk -F',' '{print NF}')

    # Generate header: col1,col2,...,colN
    header=$(printf "col%s," $(seq 1 $n_col))
    header=${header%,}  # remove trailing comma

    # Prepend header to the file safely
    tmp_file=$(mktemp)
    { echo "$header"; cat "$testfile"; } > "$tmp_file" && mv "$tmp_file" "$testfile"

    # Optional: log sample
    echo "Data.Sample= $testfile" >> "$foo_file"
done

shopt -u extglob

# -------------------------------
# RUN CyGATE
# -------------------------------

echo "Running CyGATE..."

java -jar "$TMP_JAR/CyGate_v1.02.jar" --c "$foo_file"
# rm -f "$TMP_JAR"

# -------------------------------
# WRAP UP OUTPUT
# -------------------------------

echo "Wrapping up output..."

shopt -s extglob

for cygated in "$tmp_test_dir/data_import-data-"+([0-9])_cygated.csv; do

  # Extract unique sample identifier
  base=$(basename "$cygated" .csv)
  number=$(echo "$base" | cut -d"-" -f3)
  
  echo $base
  echo $number

  # Extract predicted cell types
  awk -F',' 'NR>1 {print $NF}' $cygated > "$tmp_pred/data_import-data-$number.csv"

done

shopt -u extglob

echo "Zipping output..."
tar -czvf "$OUTPUT_DIR/$NAME"_predicted_labels.tar.gz -C "$tmp_pred"

# -------------------------------
# CLEANUP
# -------------------------------
echo "Cleaning up..."

rm -rf "$tmp_train_dir"
rm -rf "$tmp_test_dir"
rm -rf "$foo_dir"
rm -rf "$tmp_pred"



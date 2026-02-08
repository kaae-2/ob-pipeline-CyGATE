#!/bin/bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
jar_path="${script_dir}/vendor/CyGate_v1.02.jar"

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
    echo "Error: --data.train_matrix is required" >&2
    exit 1
fi
if [[ -z "${DATA_TRAIN_LABELS:-}" ]]; then
    echo "Error: --data.train_labels is required" >&2
    exit 1
fi
if [[ -z "${DATA_TEST_MATRIX:-}" ]]; then
    echo "Error: --data.test_matrix is required" >&2
    exit 1
fi

echo "CyGATE: starting" >&2

if [[ -z "${OUTPUT_DIR:-}" ]]; then
    OUTPUT_DIR="$(pwd)"
fi
mkdir -p "$OUTPUT_DIR"

# -------------------------------
# PATHS
# -------------------------------

tmp_train_dir=$(mktemp -d)
tmp_test_raw_dir=$(mktemp -d)
tmp_test_work_dir=$(mktemp -d)
tmp_meta_dir=$(mktemp -d)
foo_dir=$(mktemp -d)
#Training_UngatedCellLabel="ungated" # TODO: UPDATE THIS --> done
Training_UngatedCellLabel="0"
tmp_pred=$(mktemp -d)

ungated_id=""
label_key_path="$(dirname "$DATA_TRAIN_LABELS")/${NAME}.label_key.json.gz"
if [[ ! -f "$label_key_path" ]]; then
    label_key_path="$(dirname "$DATA_TEST_MATRIX")/${NAME}.label_key.json.gz"
fi
if [[ -f "$label_key_path" ]]; then
    ungated_id=$(LABEL_KEY_PATH="$label_key_path" python - <<'PY'
import gzip
import json
import os

path = os.environ.get("LABEL_KEY_PATH")
if not path:
    raise SystemExit(0)
try:
    with gzip.open(path, "rt", encoding="utf-8") as handle:
        payload = json.load(handle)
except Exception:
    raise SystemExit(0)

id_to_label = payload.get("id_to_label") if isinstance(payload, dict) else None
if not isinstance(id_to_label, dict):
    raise SystemExit(0)
for key, label in id_to_label.items():
    if str(label).strip().lower() == "ungated":
        print(key)
        raise SystemExit(0)
PY
    )
fi
if [[ -z "$ungated_id" ]]; then
    ungated_id="$Training_UngatedCellLabel"
fi

if [[ ! -f "$jar_path" ]]; then
    echo "Error: CyGATE jar not found at $jar_path" >&2
    exit 1
fi

if [[ -n "${CYGATE_JAVA_OPTS:-}" ]]; then
    # shellcheck disable=SC2206
    java_opts=( ${CYGATE_JAVA_OPTS} )
else
    java_xms="${CYGATE_JAVA_XMS:-512m}"
    java_xmx="${CYGATE_JAVA_XMX:-8g}"
    java_opts=("-Xms${java_xms}" "-Xmx${java_xmx}")
fi

# PATHS FOR LOCAL TEST RUN 
# tmp_train_dir="/Users/srz223/Documents/courses/Benchmarking/repos/ob-pipeline-CyGATE/tmp_train"
# tmp_test_raw_dir="/Users/srz223/Documents/courses/Benchmarking/repos/ob-pipeline-CyGATE/tmp_test_raw"
# tmp_test_work_dir="/Users/srz223/Documents/courses/Benchmarking/repos/ob-pipeline-CyGATE/tmp_test_work"
# foo_dir="/Users/srz223/Documents/courses/Benchmarking/repos/ob-pipeline-CyGATE/tmp_foo"
# TMP_JAR=$foo_dir
# tmp_pred="/Users/srz223/Documents/courses/Benchmarking/repos/ob-pipeline-CyGATE/tmp_pred"
# OUTPUT_DIR="/Users/srz223/Documents/courses/Benchmarking/repos/ob-pipeline-CyGATE/tmp_out"

echo "CyGATE: preparing data" >&2
mkdir -p "$foo_dir"
mkdir -p "$tmp_train_dir/train_x"
mkdir -p "$tmp_train_dir/train_y"
mkdir -p "$tmp_train_dir/train_xy"
mkdir -p "$tmp_test_raw_dir"
mkdir -p "$tmp_test_work_dir"
mkdir -p "$tmp_meta_dir"
mkdir -p "$tmp_pred"

# -------------------------------
# UNZIP TRAINING X AND Y
# -------------------------------
echo "CyGATE: extracting archives" >&2

# # Make sure the archive exists before extracting
# [ -f "$DATA_TRAIN_MATRIX" ] || { echo "Error: $DATA_TRAIN_MATRIX not found"; exit 1; }
# [ -f "$DATA_TRAIN_LABELS" ] || { echo "Error: $DATA_TRAIN_LABELS not found"; exit 1; }
# [ -f "$DATA_TEST_MATRIX" ] || { echo "Error: $DATA_TEST_MATRIX not found"; exit 1; }
# 
# tar -xzvf $DATA_TRAIN_MATRIX -C "$tmp_train_dir/train_x"
# tar -xzvf $DATA_TRAIN_LABELS -C "$tmp_train_dir/train_y"
# tar -xzvf $DATA_TEST_MATRIX -C "$tmp_test_raw_dir"

# Enable extended globbing and nullglob for safety
shopt -s nullglob extglob

# Check that each archive exists before extracting
for archive in "$DATA_TRAIN_MATRIX" "$DATA_TRAIN_LABELS" "$DATA_TEST_MATRIX"; do
    if [ ! -f "$archive" ]; then
        echo "Error: Archive $archive not found"
        exit 1
    fi
done

# Extract safely into temp dirs
if tar -tzf "$DATA_TRAIN_MATRIX" >/dev/null 2>&1; then
    tar -xzf "$DATA_TRAIN_MATRIX" -C "$tmp_train_dir/train_x"
else
    echo "Error: $DATA_TRAIN_MATRIX is not a valid tar.gz file"
    exit 1
fi

if tar -tzf "$DATA_TRAIN_LABELS" >/dev/null 2>&1; then
    tar -xzf "$DATA_TRAIN_LABELS" -C "$tmp_train_dir/train_y"
else
    echo "Error: $DATA_TRAIN_LABELS is not a valid tar.gz file"
    exit 1
fi

if tar -tzf "$DATA_TEST_MATRIX" >/dev/null 2>&1; then
    tar -xzf "$DATA_TEST_MATRIX" -C "$tmp_test_raw_dir"
else
    echo "Error: $DATA_TEST_MATRIX is not a valid tar.gz file"
    exit 1
fi

echo "CyGATE: preparing training data" >&2

# enable extended globbing
shopt -s nullglob

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
echo "CyGATE: generating config" >&2

foo_file="$foo_dir/foo.txt" > "$foo_file"

# Add training sample lines
for xyfile in "$tmp_train_dir/train_xy"/train_xy_*.csv; do
    echo "Training.Sample= $xyfile" >> "$foo_file"
done

echo "" >> "$foo_file"
echo "Training.UngatedCellLabel= $Training_UngatedCellLabel" >> "$foo_file"
echo "" >> "$foo_file"

# Loop over test CSVs
for testfile in "$tmp_test_raw_dir/data_import-data-"+([0-9]).csv; do
    # Skip files that might already have *_cygated.csv
    [[ "$testfile" == *_cygated.csv ]] && continue

    base=$(basename "$testfile")
    number=$(echo "$base" | cut -d"-" -f3 | cut -d"." -f1)
    prepared_testfile="$tmp_test_work_dir/$base"
    row_mask_file="$tmp_meta_dir/sample-${number}.mask"

    # Count columns in the first row, ignoring trailing commas
    first_row=$(head -1 "$testfile" | sed 's/,+$//')
    n_col=$(echo "$first_row" | awk -F',' '{print NF}')

    # Generate header: col1,col2,...,colN
    header=$(printf "col%s," $(seq 1 $n_col))
    header=${header%,}  # remove trailing comma

    # Build prepared CyGATE input once, without mutating extracted raw files
    { echo "$header"; cat "$testfile"; } > "$prepared_testfile"

    # Persist per-row missing mask once for post-processing.
    # 1 = row has missing values and should be forced to Ungated.
    # 0 = row can consume one prediction from CyGATE output.
    awk -F',' '
      NF==0 { next }
      $0 ~ /^[[:space:]]*$/ { next }
      {
        missing=0
        for (i=1; i<=NF; i++) {
          if ($i == "") { missing=1; break }
        }
        print missing
      }
    ' "$testfile" > "$row_mask_file"

    echo "Data.Sample= $prepared_testfile" >> "$foo_file"
done


# -------------------------------
# RUN CyGATE
# -------------------------------

echo "CyGATE: running model" >&2
echo "CyGATE: java opts: ${java_opts[*]}" >&2

cygate_log=$(mktemp)
if ! java "${java_opts[@]}" -jar "$jar_path" --c "$foo_file" >"$cygate_log" 2>&1; then
  echo "ERROR: CyGATE failed" >&2
  cat "$cygate_log" >&2
  exit 1
fi
# rm -f "$TMP_JAR"

# -------------------------------
# WRAP UP OUTPUT
# -------------------------------

echo "CyGATE: packaging output" >&2

for cygated in "$tmp_test_work_dir/data_import-data-"+([0-9])_cygated.csv; do

  # Extract unique sample identifier
  base=$(basename "$cygated" .csv)
  number=$(echo "$base" | cut -d"-" -f3 | cut -d"_" -f1)

  # echo $base
  # echo $number

  # Extract predicted cell types
  pred_tmp=$(mktemp)
  awk -F',' 'NR>1 {print $NF}' "$cygated" > "$pred_tmp"

  row_mask_file="$tmp_meta_dir/sample-${number}.mask"
  if [[ ! -f "$row_mask_file" ]]; then
    echo "Warning: missing row mask for sample $number; defaulting rows to model output only" >&2
    row_mask_file=$(mktemp)
    awk 'END { for (i=1; i<=NR; i++) print 0 }' "$pred_tmp" > "$row_mask_file"
  fi

  awk -v ungated="$ungated_id" -v sample="$number" '
    FNR==NR {pred[++n]=$1; next}
    {
      if ($1 == 1) {
        print ungated
      } else {
        used++
        if (used > n) {
          print ungated
        } else {
          print pred[used]
        }
      }
    }
    END {
      if (used != n) {
        print "Warning: prediction count mismatch for sample", sample, "pred", n, "used", used > "/dev/stderr"
      }
    }
  ' "$pred_tmp" "$row_mask_file" > "$tmp_pred/${NAME}-prediction-$number.csv"
  rm -f "$pred_tmp"
  [[ "$row_mask_file" == /tmp/* ]] && rm -f "$row_mask_file"

done

shopt -u extglob

echo "CyGATE: writing archive" >&2
# tar -czvf "$OUTPUT_DIR/$NAME"_predicted_labels.tar.gz -C "$tmp_pred" .
# tar -czvf "$OUTPUT_DIR/$NAME"_predicted_labels.tar.gz *.csv
tar -czvf "$OUTPUT_DIR/${NAME}_predicted_labels.tar.gz" -C "$tmp_pred" .

# -------------------------------
# CLEANUP
# -------------------------------
echo "CyGATE: done" >&2

rm -rf "$tmp_train_dir"
rm -rf "$tmp_test_raw_dir"
rm -rf "$tmp_test_work_dir"
rm -rf "$tmp_meta_dir"
rm -rf "$foo_dir"
rm -rf "$tmp_pred"

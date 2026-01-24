#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"

"${script_dir}/run-CyGATE.sh" \
  --name "cygate" \
  --output_dir "${script_dir}/out/data/analysis/default/cygate" \
  --data.train_matrix "${script_dir}/out/data/data_preprocessing/default/data_import.train.matrix.tar.gz" \
  --data.train_labels "${script_dir}/out/data/data_preprocessing/default/data_import.train.labels.tar.gz" \
  --data.test_matrix "${script_dir}/out/data/data_preprocessing/default/data_import.test.matrices.tar.gz"

# CyGATE Module

## What this module does

Wraps the CyGATE Java tool to match Omnibenchmark inputs/outputs.

- Main wrapper: `run-CyGATE.sh`
- Local convenience runner: `run_cygate.sh`
- Vendor jar: `vendor/CyGate_v1.02.jar`
- Output: `cygate_predicted_labels.tar.gz`

The wrapper extracts train/test archives, generates CyGATE config, runs the jar,
and packages per-sample predictions.

## Run locally

```bash
bash models/CyGATE/run_cygate.sh
```

Tune JVM if needed:

```bash
CYGATE_JAVA_XMS=512m CYGATE_JAVA_XMX=6g bash models/CyGATE/run_cygate.sh
```

## Run as part of benchmark

Configured in `benchmark/Clustering_conda.yml` analysis stage, run through:

```bash
just benchmark
```

## What `run_cygate.sh` / `run-CyGATE.sh` need

- Java runtime in `PATH`
- Vendor jar at `models/CyGATE/vendor/CyGate_v1.02.jar`
- Core shell utilities (`tar`, `awk`, `paste`, `wc`, etc.)
- Preprocessing outputs at `models/CyGATE/out/data/data_preprocessing/default`
- Writable output directory `models/CyGATE/out/data/analysis/default/cygate`

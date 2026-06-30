# C Performance Benchmark Suite

Portable C11 benchmark suite for CTEC44042 Assignment 2.

## What it runs

The suite benchmarks four workloads:

1. CPU intensive: prime number counting
2. Memory intensive: matrix multiplication
3. File I/O intensive: large file write/read
4. Mixed workload: generate, sort, search/checksum

Each workload is executed across `-O0`, `-O1`, `-O2`, and `-O3`. CPU, memory, and mixed workloads also test multiple OpenMP thread counts when OpenMP is available.

## Supported environments

The repository includes runners for:

- Ubuntu native
- Ubuntu on WSL2
- Ubuntu on Oracle Cloud or any other cloud VM
- Native Windows
- Ubuntu in Docker

All Linux-based environments use the same runner script. The environment name you pass is used only to label the output folder.

## Quick Start

### Ubuntu native

Install dependencies:

```bash
sudo apt update
sudo apt install -y build-essential cmake make time valgrind procps util-linux linux-tools-common
chmod +x run_all_linux.sh scripts/*.sh
```

Run the benchmark:

```bash
./run_all_linux.sh ubuntu_native
```

### Ubuntu on WSL2

Inside your Ubuntu WSL2 shell, install the same packages:

```bash
sudo apt update
sudo apt install -y build-essential cmake make time valgrind procps util-linux linux-tools-common
chmod +x run_all_linux.sh scripts/*.sh
```

Run the benchmark:

```bash
./run_all_linux.sh ubuntu_wsl2
```

### Ubuntu on Oracle Cloud or any cloud VM

SSH into the Ubuntu machine, install the same packages, then run:

```bash
sudo apt update
sudo apt install -y build-essential cmake make time valgrind procps util-linux linux-tools-common
chmod +x run_all_linux.sh scripts/*.sh
./run_all_linux.sh ubuntu_cloud
```

If you want the results folder to reflect a specific provider, pass a different label such as `oracle_cloud`, `aws_ubuntu`, or `gcp_ubuntu`.

### Native Windows

Requirements:

- PowerShell
- GCC from MSYS2/MinGW-w64

Run from the project root:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\run_all_windows.ps1 native_windows
```

If you prefer the wrapper batch file:

```cmd
run_all_windows.bat native_windows
```

### Ubuntu in Docker

Build and run the container directly:

```bash
docker build -t c-bench-suite .
docker run --rm -v "$PWD/results:/app/results" c-bench-suite
```

Or use Docker Compose:

```bash
docker compose up --build
```

The Docker image runs `./run_all_linux.sh docker_ubuntu` internally.

## Output locations

Every full run creates a timestamped results folder:

```text
results/<environment>_<timestamp>/
```

Examples:

- `results/ubuntu_native_20260630_062733/`
- `results/native_windows_20260630_141522/`
- `results/docker_ubuntu_20260630_093100/`

Inside each run folder you will find:

- `results.csv` - combined benchmark output
- `run.log` - timestamped runner log
- `system_summary.txt` - environment summary
- `lscpu.txt`, `free_h.txt`, `df_h.txt`, `vmstat_1s_5samples.txt`, `top_snapshot.txt` - Linux system snapshots
- `systeminfo.txt`, `cpu.txt`, `memory.txt`, `disk.txt` - Windows system snapshots
- `raw_*.txt` - raw benchmark stdout for each run
- `time_*.txt` - timing metadata captured by the runner
- `perf_cpu_prime_stat.txt` and `callgrind.cpu_prime.out` when profiling tools are available

The simple legacy runners in `scripts/` write one CSV file per workload directly into `results/`.

## How to use the benchmark data

The main file for analysis is:

```text
results/<environment>_<timestamp>/results.csv
```

It is a single CSV with these columns:

```text
environment,opt_level,threads,repeat,workload,version,seconds,metric_name_or_value,extra
```

Use it to compare:

- optimization levels `O0` to `O3`
- baseline vs optimized source versions
- single-thread vs multi-thread OpenMP runs
- the same environment across different machines or providers

For report tables and charts, keep runs from different environments in separate timestamped folders so you do not mix outputs.

## Tuning the run

The Linux/Docker runner accepts these environment variables:

- `REPEATS` - default `3`
- `CPU_LIMIT` - default `120000`
- `MATRIX_N` - default `512`
- `IO_MB` - default `256`
- `SORT_N` - default `5000000`
- `OMP_THREADS_TO_TEST` - default `1 2 4`

Example:

```bash
REPEATS=5 CPU_LIMIT=200000 ./run_all_linux.sh ubuntu_native
```

## Optional profiling

The Linux runner tries to capture extra profiling output when available:

- `perf stat` for CPU profiling
- `valgrind --tool=callgrind` for instruction-level profiling

If `perf` requires extra permissions, you may need:

```bash
sudo sysctl kernel.perf_event_paranoid=1
```

## Legacy simple runners

These scripts run the already-built binaries and store one CSV per workload in `results/`:

- `scripts/run_linux.sh`
- `scripts/run_windows.ps1`

They are useful for quick checks, but the main recommended entry points are `run_all_linux.sh` and `run_all_windows.ps1` because they also build, collect system information, and write the timestamped benchmark folder.

# C Performance Benchmark Suite

Portable C11 benchmark suite for CTEC44042 Assignment 2.

Supports:
- Native Windows
- Ubuntu on Oracle Cloud
- Ubuntu on WSL2
- Ubuntu in Docker

Workloads:
1. CPU intensive: prime number counting
2. Memory intensive: matrix multiplication
3. File I/O intensive: large file write/read benchmark
4. Mixed workload: generate, sort, search/checksum

Optimization experiments:
- Compile with O0, O1, O2, O3
- Single-thread vs multi-thread using OpenMP
- Baseline vs optimized source versions

## Ubuntu / WSL2 / Oracle Cloud Ubuntu

```bash
sudo apt update
sudo apt install -y build-essential cmake time linux-tools-common valgrind
chmod +x scripts/*.sh
./scripts/build_linux.sh
./scripts/run_linux.sh
./scripts/compare_optimizations_linux.sh
```

For profiling:

```bash
./scripts/profile_linux.sh
```

Note: `perf` may require additional permissions:

```bash
sudo sysctl kernel.perf_event_paranoid=1
```

## Windows

Install one of these:
- Visual Studio Build Tools with CMake, or
- MSYS2/MinGW-w64 with GCC and CMake

PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\build_windows.ps1
.\scripts\run_windows.ps1
.\scripts\compare_optimizations_windows.ps1
```

## Docker

```bash
docker build -t c-bench-suite .
docker run --rm -v "$PWD/results:/app/results" c-bench-suite
```

## Output

Results are written to `results/*.csv`.
Use each environment's CSV files in your report tables and graphs.



## Single runner order

The updated single runners build and compare all required compiler optimization levels: `-O0`, `-O1`, `-O2`, and `-O3`. They do not mix all workloads together. The execution order is:

1. CPU workload: baseline and optimized/OpenMP versions for O0, O1, O2, O3
2. Memory workload: baseline and optimized/OpenMP versions for O0, O1, O2, O3
3. File I/O workload: O0, O1, O2, O3
4. Mixed sorting workload: baseline and optimized/OpenMP versions for O0, O1, O2, O3

This makes it easy to stop after CPU testing, inspect results, then continue with the other workloads if needed.

## Docker Compose Run

This package includes `docker-compose.yml` for running the full ordered benchmark sequence inside Docker.

Run with modern Docker Compose:

```bash
docker compose up --build
```

Or, on systems using the older standalone Compose command:

```bash
docker-compose up --build
```

The container runs:

```bash
./run_all_linux.sh docker_ubuntu
```

Results are saved to the host folder:

```text
results/
```

To change test size or repeat count, edit the environment variables in `docker-compose.yml`, for example `REPEATS`, `CPU_LIMIT`, `MATRIX_N`, `IO_MB`, and `SORT_N`.
# perf_benchmark_c_suite

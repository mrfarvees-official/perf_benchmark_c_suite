#!/usr/bin/env bash
set -u

# One-command runner for Ubuntu / Debian / Fedora / RHEL / Arch / WSL2 / Docker.
# It builds all C benchmarks at -O0, -O1, -O2, and -O3. It completes CPU tests first across all optimization levels, then memory, file I/O, and mixed workloads.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR" || exit 1

ENV_NAME="${1:-linux}"
REPEATS="${REPEATS:-5}"
CPU_LIMIT="${CPU_LIMIT:-120000}"
MATRIX_N="${MATRIX_N:-512}"
IO_MB="${IO_MB:-256}"
SORT_N="${SORT_N:-5000000}"
OMP_THREADS_TO_TEST="${OMP_THREADS_TO_TEST:-1 2 4}"

STAMP="$(date +%Y%m%d_%H%M%S 2>/dev/null || echo run)"
OUT_DIR="results/${ENV_NAME}_${STAMP}"
BIN_DIR="build_${ENV_NAME}_${STAMP}"
mkdir -p "$OUT_DIR" "$BIN_DIR"

log() { printf '\n[%s] %s\n' "$(date '+%H:%M:%S' 2>/dev/null || echo time)" "$*" | tee -a "$OUT_DIR/run.log"; }
have() { command -v "$1" >/dev/null 2>&1; }

if ! have gcc; then
  echo "ERROR: gcc is not installed. Install it first, for example: sudo apt install build-essential" >&2
  exit 1
fi

CC="${CC:-gcc}"
COMMON="src/common.c"
CFLAGS_BASE="-std=c11 -Wall -Wextra -D_POSIX_C_SOURCE=199309L"
LDFLAGS_BASE="-lm"
OPENMP_FLAG=""

# Detect OpenMP support without failing the whole run.
cat > "$BIN_DIR/openmp_check.c" <<'CHECK'
#include <omp.h>
int main(void){return omp_get_max_threads() < 1;}
CHECK
if "$CC" $CFLAGS_BASE -fopenmp "$BIN_DIR/openmp_check.c" -o "$BIN_DIR/openmp_check" >/dev/null 2>&1; then
  OPENMP_FLAG="-fopenmp"
fi

collect_system_info() {
  log "Collecting system information"
  {
    echo "Environment name: $ENV_NAME"
    echo "Date: $(date 2>/dev/null || true)"
    echo "PWD: $ROOT_DIR"
    echo "Compiler: $($CC --version | head -n 1)"
    echo "OpenMP flag detected: ${OPENMP_FLAG:-not available}"
    echo "Kernel: $(uname -a 2>/dev/null || true)"
    echo "Container detection:"
    [ -f /.dockerenv ] && echo "  /.dockerenv exists" || echo "  /.dockerenv not found"
    echo
    echo "CPU information:"
    lscpu 2>/dev/null || true
    echo
    echo "Memory information:"
    free -h 2>/dev/null || true
    echo
    echo "Disk usage:"
    df -h 2>/dev/null || true
    echo
    echo "Block devices:"
    lsblk 2>/dev/null || true
  } > "$OUT_DIR/systeminfo.txt"

  {
    echo "Environment name: $ENV_NAME"
    echo "Date: $(date 2>/dev/null || true)"
    echo "PWD: $ROOT_DIR"
    echo "Compiler: $($CC --version | head -n 1)"
    echo "OpenMP flag detected: ${OPENMP_FLAG:-not available}"
    echo "Kernel: $(uname -a 2>/dev/null || true)"
    echo "Container detection:"
    [ -f /.dockerenv ] && echo "  /.dockerenv exists" || echo "  /.dockerenv not found"
  } > "$OUT_DIR/system_summary.txt"

  lscpu > "$OUT_DIR/lscpu.txt" 2>&1 || true
  free -h > "$OUT_DIR/free_h.txt" 2>&1 || true
  df -h > "$OUT_DIR/df_h.txt" 2>&1 || true
  vmstat 1 5 > "$OUT_DIR/vmstat_1s_5samples.txt" 2>&1 || true
  top -b -n 1 > "$OUT_DIR/top_snapshot.txt" 2>&1 || true
  "$CC" --version > "$OUT_DIR/compiler_version.txt" 2>&1 || true
}

build_one() {
  opt="$1"
  suffix="$2"
  log "Building benchmarks with $opt"
  "$CC" $CFLAGS_BASE "$opt" src/cpu_prime_baseline.c "$COMMON" -o "$BIN_DIR/cpu_prime_baseline_${suffix}" $LDFLAGS_BASE || return 1
  "$CC" $CFLAGS_BASE "$opt" $OPENMP_FLAG src/cpu_prime_optimized.c "$COMMON" -o "$BIN_DIR/cpu_prime_optimized_${suffix}" $LDFLAGS_BASE || return 1
  "$CC" $CFLAGS_BASE "$opt" src/memory_matrix_baseline.c "$COMMON" -o "$BIN_DIR/memory_matrix_baseline_${suffix}" $LDFLAGS_BASE || return 1
  "$CC" $CFLAGS_BASE "$opt" $OPENMP_FLAG src/memory_matrix_optimized.c "$COMMON" -o "$BIN_DIR/memory_matrix_optimized_${suffix}" $LDFLAGS_BASE || return 1
  "$CC" $CFLAGS_BASE "$opt" src/file_io_benchmark.c "$COMMON" -o "$BIN_DIR/file_io_benchmark_${suffix}" $LDFLAGS_BASE || return 1
  "$CC" $CFLAGS_BASE "$opt" src/mixed_sort_baseline.c "$COMMON" -o "$BIN_DIR/mixed_sort_baseline_${suffix}" $LDFLAGS_BASE || return 1
  "$CC" $CFLAGS_BASE "$opt" $OPENMP_FLAG src/mixed_sort_optimized.c "$COMMON" -o "$BIN_DIR/mixed_sort_optimized_${suffix}" $LDFLAGS_BASE || return 1
}

run_cmd() {
  label="$1"
  exe="$2"
  arg="$3"
  opt="$4"
  threads="$5"
  repeat="$6"
  raw="$OUT_DIR/raw_${label}_${opt}_t${threads}_r${repeat}.txt"
  timing="$OUT_DIR/time_${label}_${opt}_t${threads}_r${repeat}.txt"
  export OMP_NUM_THREADS="$threads"

  log "Running $label opt=$opt threads=$threads repeat=$repeat"
  if have /usr/bin/time; then
    /usr/bin/time -v "$exe" "$arg" > "$raw" 2> "$timing"
  else
    "$exe" "$arg" > "$raw" 2> "$timing"
  fi

  time_user_seconds="$(awk -F': *' '/^[[:space:]]*User time \(seconds\):/ {print $2; exit}' "$timing" 2>/dev/null || true)"
  time_system_seconds="$(awk -F': *' '/^[[:space:]]*System time \(seconds\):/ {print $2; exit}' "$timing" 2>/dev/null || true)"
  time_cpu_percent="$(awk -F': *' '/^[[:space:]]*Percent of CPU this job got:/ {gsub(/%/, "", $2); print $2; exit}' "$timing" 2>/dev/null || true)"
  time_peak_rss_kb="$(awk -F': *' '/^[[:space:]]*Maximum resident set size \(kbytes\):/ {print $2; exit}' "$timing" 2>/dev/null || true)"
  time_io_read="$(awk -F': *' '/^[[:space:]]*File system inputs:/ {print $2; exit}' "$timing" 2>/dev/null || true)"
  time_io_write="$(awk -F': *' '/^[[:space:]]*File system outputs:/ {print $2; exit}' "$timing" 2>/dev/null || true)"
  time_cpu_seconds_total="$(awk -v u="$time_user_seconds" -v s="$time_system_seconds" 'BEGIN { if (u == "" && s == "") { print "" } else { print (u + 0) + (s + 0) } }')"

  # Convert program CSV output to one combined CSV.
  # The benchmark programs already emit comma-separated rows, so keep every data
  # line after the per-run header and prefix run metadata.
  awk -F, -v env="$ENV_NAME" -v opt="$opt" -v th="$threads" -v rep="$repeat" \
      -v cpu_total="$time_cpu_seconds_total" -v cpu_pct="$time_cpu_percent" \
      -v peak_rss="$time_peak_rss_kb" -v io_read="$time_io_read" -v io_write="$time_io_write" '
    NR > 1 && NF {
      if (NF == 4) {
        print env "," opt "," th "," rep "," $0 ",," cpu_total "," cpu_pct "," peak_rss "," io_read "," io_write
      } else {
        print env "," opt "," th "," rep "," $0 "," cpu_total "," cpu_pct "," peak_rss "," io_read "," io_write
      }
    }
  ' "$raw" >> "$OUT_DIR/results.csv"
}

generate_averages() {
  awk -F, '
    NR == 1 { next }
    {
      key = $1 SUBSEP $2 SUBSEP $3 SUBSEP $5 SUBSEP $6
      if (!(key in seen)) {
        order[++count] = key
      }
      seen[key]++
      sec_sum[key] += $7 + 0
      metric_sum[key] += $8 + 0
      if (NF >= 9 && $9 != "") {
        extra_sum[key] += $9 + 0
        extra_seen[key]++
      }
      if (NF >= 10 && $10 != "") { cpu_total_sum[key] += $10 + 0; cpu_total_seen[key]++ }
      if (NF >= 11 && $11 != "") { cpu_pct_sum[key] += $11 + 0; cpu_pct_seen[key]++ }
      if (NF >= 12 && $12 != "") { peak_rss_sum[key] += $12 + 0; peak_rss_seen[key]++ }
      if (NF >= 13 && $13 != "") { io_read_sum[key] += $13 + 0; io_read_seen[key]++ }
      if (NF >= 14 && $14 != "") { io_write_sum[key] += $14 + 0; io_write_seen[key]++ }
    }
    END {
      print "environment,opt_level,threads,workload,version,samples,avg_seconds,avg_metric_value,avg_extra_value,avg_resource_cpu_seconds_total,avg_resource_cpu_percent,avg_resource_peak_rss_kb,avg_resource_io_read,avg_resource_io_write"
      for (i = 1; i <= count; i++) {
        key = order[i]
        split(key, f, SUBSEP)
        avg_seconds = sec_sum[key] / seen[key]
        avg_metric = metric_sum[key] / seen[key]
        avg_extra = (extra_seen[key] ? extra_sum[key] / extra_seen[key] : "")
        avg_cpu_total = (cpu_total_seen[key] ? cpu_total_sum[key] / cpu_total_seen[key] : "")
        avg_cpu_pct = (cpu_pct_seen[key] ? cpu_pct_sum[key] / cpu_pct_seen[key] : "")
        avg_peak_rss = (peak_rss_seen[key] ? peak_rss_sum[key] / peak_rss_seen[key] : "")
        avg_io_read = (io_read_seen[key] ? io_read_sum[key] / io_read_seen[key] : "")
        avg_io_write = (io_write_seen[key] ? io_write_sum[key] / io_write_seen[key] : "")
        printf "%s,%s,%s,%s,%s,%d,%.6f,%.6f,", f[1], f[2], f[3], f[4], f[5], seen[key], avg_seconds, avg_metric
        if (avg_extra == "") { printf "," } else { printf "%.6f,", avg_extra }
        if (avg_cpu_total == "") { printf "," } else { printf "%.6f,", avg_cpu_total }
        if (avg_cpu_pct == "") { printf "," } else { printf "%.6f,", avg_cpu_pct }
        if (avg_peak_rss == "") { printf "," } else { printf "%.6f,", avg_peak_rss }
        if (avg_io_read == "") { printf "," } else { printf "%.6f,", avg_io_read }
        if (avg_io_write == "") { printf "\n" } else { printf "%.6f\n", avg_io_write }
      }
    }
  ' "$OUT_DIR/results.csv" > "$OUT_DIR/averages.csv"
}

run_all() {
  echo "environment,opt_level,threads,repeat,workload,version,seconds,metric_name_or_value,extra,resource_cpu_seconds_total,resource_cpu_percent,resource_peak_rss_kb,resource_io_read,resource_io_write" > "$OUT_DIR/results.csv"

  # Required assignment comparison: O0 vs O1 vs O2 vs O3.
  # Important run order: finish one workload completely before moving to the next workload.
  # Order: CPU -> Memory -> File I/O -> Mixed.

  log "PHASE 1/4: CPU workload, all optimization levels"
  for opt in O0 O1 O2 O3; do
    for r in $(seq 1 "$REPEATS"); do
      run_cmd cpu_prime_baseline "$BIN_DIR/cpu_prime_baseline_${opt}" "$CPU_LIMIT" "$opt" 1 "$r"
    done
    for th in $OMP_THREADS_TO_TEST; do
      for r in $(seq 1 "$REPEATS"); do
        run_cmd cpu_prime_optimized "$BIN_DIR/cpu_prime_optimized_${opt}" "$CPU_LIMIT" "$opt" "$th" "$r"
      done
    done
  done

  log "PHASE 2/4: Memory workload, all optimization levels"
  for opt in O0 O1 O2 O3; do
    for r in $(seq 1 "$REPEATS"); do
      run_cmd memory_matrix_baseline "$BIN_DIR/memory_matrix_baseline_${opt}" "$MATRIX_N" "$opt" 1 "$r"
    done
    for th in $OMP_THREADS_TO_TEST; do
      for r in $(seq 1 "$REPEATS"); do
        run_cmd memory_matrix_optimized "$BIN_DIR/memory_matrix_optimized_${opt}" "$MATRIX_N" "$opt" "$th" "$r"
      done
    done
  done

  log "PHASE 3/4: File I/O workload, all optimization levels"
  for opt in O0 O1 O2 O3; do
    for r in $(seq 1 "$REPEATS"); do
      run_cmd file_io_benchmark "$BIN_DIR/file_io_benchmark_${opt}" "$IO_MB" "$opt" 1 "$r"
    done
  done

  log "PHASE 4/4: Mixed sorting workload, all optimization levels"
  for opt in O0 O1 O2 O3; do
    for r in $(seq 1 "$REPEATS"); do
      run_cmd mixed_sort_baseline "$BIN_DIR/mixed_sort_baseline_${opt}" "$SORT_N" "$opt" 1 "$r"
    done
    for th in $OMP_THREADS_TO_TEST; do
      for r in $(seq 1 "$REPEATS"); do
        run_cmd mixed_sort_optimized "$BIN_DIR/mixed_sort_optimized_${opt}" "$SORT_N" "$opt" "$th" "$r"
      done
    done
  done
}

profile_examples() {
  log "Running optional profiling examples"
  if have perf; then
    perf stat "$BIN_DIR/cpu_prime_optimized_O3" "$CPU_LIMIT" > "$OUT_DIR/perf_cpu_prime_stdout.txt" 2> "$OUT_DIR/perf_cpu_prime_stat.txt" || true
  else
    echo "perf not found or not usable in this environment" > "$OUT_DIR/perf_not_available.txt"
  fi

  if have valgrind; then
    valgrind --tool=callgrind --callgrind-out-file="$OUT_DIR/callgrind.cpu_prime.out" "$BIN_DIR/cpu_prime_optimized_O3" "$CPU_LIMIT" > "$OUT_DIR/valgrind_cpu_prime_stdout.txt" 2> "$OUT_DIR/valgrind_cpu_prime_stderr.txt" || true
  else
    echo "valgrind not found" > "$OUT_DIR/valgrind_not_available.txt"
  fi
}

collect_system_info
build_one -O0 O0 || exit 1
build_one -O1 O1 || exit 1
build_one -O2 O2 || exit 1
build_one -O3 O3 || exit 1
run_all
generate_averages
profile_examples

log "Finished. Results saved in: $OUT_DIR"
echo "Results folder: $OUT_DIR"
echo "Main CSV: $OUT_DIR/results.csv"
echo "Average CSV: $OUT_DIR/averages.csv"

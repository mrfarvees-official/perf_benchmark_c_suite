#!/usr/bin/env bash
set -e
mkdir -p opt_builds results
for opt in 0 1 2 3; do
  dir="opt_builds/O$opt"
  mkdir -p "$dir"
  gcc -std=c11 -O$opt -D_POSIX_C_SOURCE=199309L src/common.c src/cpu_prime_optimized.c -lm -fopenmp -o "$dir/cpu_prime_O$opt"
  /usr/bin/time -v "$dir/cpu_prime_O$opt" 120000 > "results/cpu_prime_O$opt.csv" 2> "results/cpu_prime_O$opt_time.txt"
done

#!/usr/bin/env bash
set -e
mkdir -p results
BIN=./build
$BIN/cpu_prime_baseline 120000 | tee results/cpu_prime_baseline.csv
$BIN/cpu_prime_optimized 120000 | tee results/cpu_prime_optimized.csv
$BIN/memory_matrix_baseline 512 | tee results/memory_matrix_baseline.csv
$BIN/memory_matrix_optimized 512 | tee results/memory_matrix_optimized.csv
$BIN/file_io_benchmark 256 | tee results/file_io.csv
$BIN/mixed_sort_baseline 5000000 | tee results/mixed_sort_baseline.csv
$BIN/mixed_sort_optimized 5000000 | tee results/mixed_sort_optimized.csv

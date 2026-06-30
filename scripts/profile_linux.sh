#!/usr/bin/env bash
set -e
mkdir -p results
./scripts/build_linux.sh
/usr/bin/time -v ./build/cpu_prime_optimized 120000 > results/profile_time_cpu.csv 2> results/profile_time_cpu.txt || true
perf stat ./build/cpu_prime_optimized 120000 > results/profile_perf_cpu.csv 2> results/profile_perf_cpu.txt || true
valgrind --tool=callgrind --callgrind-out-file=results/callgrind.cpu.out ./build/cpu_prime_optimized 120000 > results/profile_valgrind_cpu.csv 2> results/profile_valgrind_cpu.txt || true

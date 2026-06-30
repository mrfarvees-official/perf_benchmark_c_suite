#include "common.h"
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#ifdef _OPENMP
#include <omp.h>
#endif

static int is_prime_fast(unsigned long long n) {
    if (n < 2) return 0;
    if (n == 2) return 1;
    if ((n & 1ULL) == 0) return 0;
    unsigned long long root = (unsigned long long)sqrt((double)n);
    for (unsigned long long d = 3; d <= root; d += 2) {
        if (n % d == 0) return 0;
    }
    return 1;
}

int main(int argc, char **argv) {
    unsigned long long limit = argc > 1 ? strtoull(argv[1], NULL, 10) : 120000ULL;
    unsigned long long count = 0;
    double start = now_seconds();
#pragma omp parallel for reduction(+:count) schedule(dynamic)
    for (long long n = 2; n <= (long long)limit; ++n) count += is_prime_fast((unsigned long long)n);
    double seconds = now_seconds() - start;
    print_result_csv("cpu_prime", "optimized_openmp", seconds, (double)count, "prime_count");
    return 0;
}

#include "common.h"
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#ifdef _OPENMP
#include <omp.h>
#endif

static int cmp_u64(const void *a, const void *b) {
    uint64_t x = *(const uint64_t *)a;
    uint64_t y = *(const uint64_t *)b;
    return (x > y) - (x < y);
}

int main(int argc, char **argv) {
    size_t n = argc > 1 ? (size_t)strtoull(argv[1], NULL, 10) : 5000000;
    uint64_t *data = (uint64_t *)malloc(n * sizeof(uint64_t));
    if (!data) { fprintf(stderr, "allocation failed\n"); return 1; }

    double start = now_seconds();
#pragma omp parallel
    {
        uint64_t state = 123456789ULL;
#ifdef _OPENMP
        state += (uint64_t)omp_get_thread_num() * 99991ULL;
#pragma omp for schedule(static)
#endif
        for (long long i = 0; i < (long long)n; ++i) data[i] = xorshift64(&state);
    }
    qsort(data, n, sizeof(uint64_t), cmp_u64);
    uint64_t checksum = 0;
#pragma omp parallel for reduction(^:checksum) schedule(static)
    for (long long i = 0; i < (long long)n; i += 1024) checksum ^= data[i];
    double seconds = now_seconds() - start;
    print_result_csv("mixed_sort", "optimized_parallel_generate", seconds, (double)(checksum % 1000000000ULL), "checksum_mod");
    free(data);
    return 0;
}

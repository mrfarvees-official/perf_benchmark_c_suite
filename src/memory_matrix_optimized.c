#include "common.h"
#include <stdio.h>
#include <stdlib.h>
#ifdef _OPENMP
#include <omp.h>
#endif

static double *alloc_matrix(size_t n) {
    double *m = (double *)malloc(n * n * sizeof(double));
    if (!m) { fprintf(stderr, "allocation failed\n"); exit(1); }
    return m;
}

int main(int argc, char **argv) {
    size_t n = argc > 1 ? (size_t)strtoull(argv[1], NULL, 10) : 512;
    double *a = alloc_matrix(n), *b = alloc_matrix(n), *c = alloc_matrix(n);
    for (size_t i = 0; i < n*n; ++i) { a[i] = (double)(i % 100) / 100.0; b[i] = (double)(i % 50) / 50.0; c[i] = 0.0; }

    double start = now_seconds();
#pragma omp parallel for schedule(static)
    for (long long ii = 0; ii < (long long)n; ++ii) {
        size_t i = (size_t)ii;
        for (size_t k = 0; k < n; ++k) {
            double aik = a[i*n + k];
            for (size_t j = 0; j < n; ++j) {
                c[i*n + j] += aik * b[k*n + j];
            }
        }
    }
    double seconds = now_seconds() - start;

    double checksum = 0.0;
    for (size_t i = 0; i < n*n; i += n + 1) checksum += c[i];
    print_result_csv("memory_matrix", "optimized_ikj_openmp", seconds, checksum, "checksum");
    free(a); free(b); free(c);
    return 0;
}

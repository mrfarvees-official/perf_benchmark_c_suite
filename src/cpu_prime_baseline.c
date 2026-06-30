#include "common.h"
#include <stdio.h>
#include <stdlib.h>

static int is_prime_slow(unsigned long long n) {
    if (n < 2) return 0;
    for (unsigned long long d = 2; d < n; ++d) {
        if (n % d == 0) return 0;
    }
    return 1;
}

int main(int argc, char **argv) {
    unsigned long long limit = argc > 1 ? strtoull(argv[1], NULL, 10) : 120000ULL;
    double start = now_seconds();
    unsigned long long count = 0;
    for (unsigned long long n = 2; n <= limit; ++n) count += is_prime_slow(n);
    double seconds = now_seconds() - start;
    print_result_csv("cpu_prime", "baseline_single_thread", seconds, (double)count, "prime_count");
    return 0;
}

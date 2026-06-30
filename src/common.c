#include "common.h"
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <time.h>
#ifdef _WIN32
#include <windows.h>
#include <direct.h>
#endif

double now_seconds(void) {
#ifdef _WIN32
    static LARGE_INTEGER freq;
    static int initialized = 0;
    LARGE_INTEGER counter;
    if (!initialized) {
        QueryPerformanceFrequency(&freq);
        initialized = 1;
    }
    QueryPerformanceCounter(&counter);
    return (double)counter.QuadPart / (double)freq.QuadPart;
#else
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1000000000.0;
#endif
}

void print_result_csv(const char *workload, const char *version, double seconds, double metric, const char *metric_name) {
    printf("workload,version,seconds,%s\n", metric_name);
    printf("%s,%s,%.6f,%.6f\n", workload, version, seconds, metric);
}

uint64_t xorshift64(uint64_t *state) {
    uint64_t x = *state;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    *state = x;
    return x;
}

int ensure_results_dir(void) {
#ifdef _WIN32
    return _mkdir("results");
#else
    return mkdir("results", 0777);
#endif
}

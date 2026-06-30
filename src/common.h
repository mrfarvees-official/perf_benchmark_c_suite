#ifndef COMMON_H
#define COMMON_H

#include <stddef.h>
#include <stdint.h>

double now_seconds(void);
void print_result_csv(const char *workload, const char *version, double seconds, double metric, const char *metric_name);
uint64_t xorshift64(uint64_t *state);
int ensure_results_dir(void);

#endif

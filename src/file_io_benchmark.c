#include "common.h"
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

int main(int argc, char **argv) {
    size_t mb = argc > 1 ? (size_t)strtoull(argv[1], NULL, 10) : 256;
    const size_t block = 1024 * 1024;
    unsigned char *buffer = (unsigned char *)malloc(block);
    if (!buffer) { fprintf(stderr, "allocation failed\n"); return 1; }
    for (size_t i = 0; i < block; ++i) buffer[i] = (unsigned char)(i & 255);

    ensure_results_dir();
    const char *path = "results/io_test.bin";
    double start = now_seconds();
    FILE *out = fopen(path, "wb");
    if (!out) { perror("fopen write"); return 1; }
    for (size_t i = 0; i < mb; ++i) fwrite(buffer, 1, block, out);
    fclose(out);
    double write_seconds = now_seconds() - start;

    uint64_t checksum = 0;
    start = now_seconds();
    FILE *in = fopen(path, "rb");
    if (!in) { perror("fopen read"); return 1; }
    size_t r;
    while ((r = fread(buffer, 1, block, in)) > 0) {
        for (size_t i = 0; i < r; i += 4096) checksum += buffer[i];
    }
    fclose(in);
    double read_seconds = now_seconds() - start;

    printf("workload,version,seconds,throughput_MBps,checksum\n");
    printf("file_io,write_buffered,%.6f,%.6f,%" PRIu64 "\n", write_seconds, (double)mb / write_seconds, checksum);
    printf("file_io,read_buffered,%.6f,%.6f,%" PRIu64 "\n", read_seconds, (double)mb / read_seconds, checksum);
    free(buffer);
    return 0;
}

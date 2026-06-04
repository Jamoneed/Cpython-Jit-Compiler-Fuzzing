#define _GNU_SOURCE
#include <dlfcn.h>
#include <sys/mman.h>
#include <stdlib.h>
#include <stdio.h>
#include <errno.h>
#include <time.h>
static void *(*real_mmap)(void*, size_t, int, int, int, off_t) = NULL;
static double fail_rate = 0.0;
static long fail_after = -1;
static long exec_mmap_count = 0;
static long fail_count = 0;
static int initialized = 0;
static void init() {
    if (initialized) return;
    initialized = 1;
    srand(time(NULL));
    real_mmap = dlsym(RTLD_NEXT, "mmap");
    char *rate = getenv("MMAP_FAIL_RATE");
    if (rate) fail_rate = atof(rate);
    char *after = getenv("MMAP_FAIL_AFTER");
    if (after) fail_after = atol(after);
    fprintf(stderr, "[fail_mmap] rate=%.4f fail_after=%ld\n", fail_rate, fail_after);
}
void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
    init();
    if (real_mmap == NULL) { errno = ENOMEM; return MAP_FAILED; }
    if ((prot & PROT_EXEC) && (prot & PROT_WRITE)) {
        exec_mmap_count++;
        if (fail_after > 0 && exec_mmap_count == fail_after) {
            fail_count++;
            fprintf(stderr, "[fail_mmap] INJECTING FAIL at exec mmap #%ld\n", exec_mmap_count);
            errno = ENOMEM;
            return MAP_FAILED;
        }
        if (fail_rate > 0.0 && (double)rand() / RAND_MAX < fail_rate) {
            fail_count++;
            errno = ENOMEM;
            return MAP_FAILED;
        }
    }
    return real_mmap(addr, length, prot, flags, fd, offset);
}

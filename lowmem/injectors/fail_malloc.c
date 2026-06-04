#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdlib.h>
#include <stdio.h>
#include <errno.h>
#include <time.h>
#include <string.h>
static void *(*real_malloc)(size_t) = NULL;
static void *(*real_realloc)(void*, size_t) = NULL;
static void *(*real_calloc)(size_t, size_t) = NULL;
static double fail_rate = 0.0;
static long fail_after = -1;
static long alloc_count = 0;
static size_t min_size = 0;
static int initialized = 0;
static void init() {
    if (initialized) return;
    initialized = 1;
    srand(time(NULL));
    real_malloc = dlsym(RTLD_NEXT, "malloc");
    real_realloc = dlsym(RTLD_NEXT, "realloc");
    real_calloc = dlsym(RTLD_NEXT, "calloc");
    char *rate = getenv("MALLOC_FAIL_RATE");
    if (rate) fail_rate = atof(rate);
    char *after = getenv("MALLOC_FAIL_AFTER");
    if (after) fail_after = atol(after);
    char *minsize = getenv("MALLOC_FAIL_MIN_SIZE");
    if (minsize) min_size = atol(minsize);
}
static int should_fail(size_t size) {
    if (size < min_size) return 0;
    alloc_count++;
    if (fail_after > 0 && alloc_count == fail_after) {
        fprintf(stderr, "[fail_malloc] FAIL at alloc #%ld (size=%zu)\n", alloc_count, size);
        return 1;
    }
    if (fail_rate > 0.0 && (double)rand() / RAND_MAX < fail_rate) return 1;
    return 0;
}
void *malloc(size_t size) { init(); if (should_fail(size)) { errno=ENOMEM; return NULL; } return real_malloc(size); }
void *realloc(void *p, size_t s) { init(); if (should_fail(s)) { errno=ENOMEM; return NULL; } return real_realloc(p,s); }
void *calloc(size_t n, size_t s) { init(); if (should_fail(n*s)) { errno=ENOMEM; return NULL; }
    void *ptr=real_malloc(n*s); if(ptr) memset(ptr,0,n*s); return ptr; }

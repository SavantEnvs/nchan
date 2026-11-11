#ifndef NCHAN_FUZZ_COMMON_H
#define NCHAN_FUZZ_COMMON_H

#include <nchan_module.h>
#include <string.h>
#include <stdlib.h>

/* nchan logs through ngx_cycle->log; give it a log whose level is 0 so nothing is formatted or written. */
static ngx_cycle_t  fuzz_cycle;
static ngx_log_t    fuzz_log;

static void nchan_fuzz_init_cycle(void) {
  fuzz_log.log_level = 0;
  fuzz_cycle.log = &fuzz_log;
  ngx_cycle = &fuzz_cycle;
}

/* exact-size NUL-terminated heap copy, so ASan sees any read past the end of the input */
static char *nchan_fuzz_cstr(const uint8_t *data, size_t size) {
  char *s = (char *)malloc(size + 1);
  memcpy(s, data, size);
  s[size] = '\0';
  return s;
}

#endif

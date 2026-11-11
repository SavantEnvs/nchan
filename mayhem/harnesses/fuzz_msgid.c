// Fuzzes nchan's message-id parser: the "<time>:<tag>[,<tag>...]" form a subscriber sends in its
// Etag / Last-Event-ID / ?last_event_id, with the "[active]" tag brace syntax of multiplexed channels.
// The first input byte is the number of channels of the location (ctx->channel_id_count, 0..255).
#include "nchan_fuzz_common.h"
#include <util/nchan_msg.h>

int LLVMFuzzerInitialize(int *argc, char ***argv) {
  (void)argc; (void)argv;
  nchan_fuzz_init_cycle();
  return 0;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  nchan_msg_id_t  id = NCHAN_ZERO_MSGID, one = NCHAN_ZERO_MSGID;
  ngx_str_t       str;
  ngx_int_t       rc;
  uint16_t        n;
  uint8_t        *buf;

  if(size < 1) {
    return -1;
  }
  buf = (uint8_t *)malloc(size - 1 ? size - 1 : 1);
  memcpy(buf, data + 1, size - 1);
  str.data = buf;
  str.len = size - 1;

  rc = nchan_parse_compound_msgid(&id, &str, data[0]);
  if(rc == NGX_OK) {
    for(n = 0; n < id.tagcount; n++) {
      nchan_extract_from_multi_msgid(&id, n, &one);
    }
  }
  free(buf);
  return rc == NGX_OK ? 0 : -1;
}

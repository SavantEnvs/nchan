// Fuzzes nchan's parser for the text a Redis server returns to CLUSTER NODES, and the slot-range
// parser that is run over every master line of that reply.
#include "nchan_fuzz_common.h"
#include <store/redis/redis_nodeset_parser.h>
#include <store/redis/redis_nodeset.h>

static redis_node_t fuzz_node;

int LLVMFuzzerInitialize(int *argc, char ***argv) {
  (void)argc; (void)argv;
  nchan_fuzz_init_cycle();
  return 0;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  size_t                 count = 0, i;
  cluster_nodes_line_t  *lines;
  char                  *reply = nchan_fuzz_cstr(data, size);

  lines = parse_cluster_nodes(&fuzz_node, reply, &count);
  for(i = 0; i < count; i++) {
    cluster_nodes_line_t *l = &lines[i];
    if(l->master && l->slot_ranges_count > 0) {
      redis_slot_range_t *ranges = (redis_slot_range_t *)malloc(sizeof(*ranges) * (size_t)l->slot_ranges_count);
      parse_cluster_node_slots(l, ranges);
      free(ranges);
    }
  }
  free(reply);
  return 0;
}

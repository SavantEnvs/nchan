// Fuzzes nchan's parsers for the text a Redis server returns to INFO REPLICATION: the master
// discovery (master_host/master_port) and the slaveN: lines of a master.
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
  size_t   count = 0;
  char    *info = nchan_fuzz_cstr(data, size);

  parse_info_master(&fuzz_node, info);
  parse_info_slaves(&fuzz_node, info, &count);
  free(info);
  return 0;
}

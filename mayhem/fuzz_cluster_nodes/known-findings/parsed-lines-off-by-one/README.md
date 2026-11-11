# parse_cluster_nodes: one-past-the-end write of the static line table

`src/store/redis/redis_nodeset_parser.c` `parse_cluster_nodes()` stores each parsed `CLUSTER NODES`
line in the static array `cluster_node_parsed_lines[MAX_CLUSTER_NODE_PARSED_LINES]` (512 entries) but
guards the store with `if(n > MAX_CLUSTER_NODE_PARSED_LINES)`. With `n == 512` the guard passes and
`cluster_node_parsed_lines[512] = l` writes 200 bytes past the end of the array.

- Impact: global-buffer-overflow write driven by the reply of a (malicious or buggy) Redis Cluster
  node when nchan has `nchan_redis_storage_mode`/cluster discovery enabled.
- Reproducer: `repro-513-lines` (513 master lines). `/mayhem/fuzz_cluster_nodes-standalone <file>` aborts
  with `AddressSanitizer: global-buffer-overflow ... in __asan_memcpy`.
- One-line fix: `if(n >= MAX_CLUSTER_NODE_PARSED_LINES)`.

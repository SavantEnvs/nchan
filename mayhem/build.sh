#!/usr/bin/env bash
#
# mayhem/build.sh — nchan is an nginx module, so it is built as part of nginx (the pinned release cached
# in /opt/toolchains/deps by the Dockerfile). Two independent out-of-tree builds, each from a scratch
# copy of the nginx source (nginx's configure writes into its cwd):
#   build/fuzz  nginx + nchan with $SANITIZER_FLAGS/$DEBUG_FLAGS and SanCov (-fsanitize=fuzzer-no-link);
#               its object files are what the harnesses link against (nginx.o's main is renamed away)
#   build/test  nginx + nchan with the project's NORMAL flags: the server mayhem/test.sh runs
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

SRC=${SRC:-/mayhem}
NGINX_DEP=/opt/toolchains/deps/nginx-1.26.3/src
B="$SRC/mayhem/build"
cd "$SRC"

# nginx's configure only needs these (no PCRE: nchan does not use it; zlib is what nchan needs for permessage-deflate)
NGX_OPTS=(--without-pcre --without-http_rewrite_module
          --without-http_upstream_zone_module --add-module="$SRC")

prepare_tree() { # $1 = tree dir
  rm -rf "$1"
  mkdir -p "$1"
  cp -a "$NGINX_DEP"/. "$1"/
  chmod -R u+w "$1"
}

# 1) fuzz build: sanitized, DWARF 3, SanCov on the nginx+nchan code
F="$B/fuzz"
prepare_tree "$F"
(
  cd "$F"
  ./configure --with-cc="$CC" "${NGX_OPTS[@]}" \
    --with-cc-opt="-O1 $SANITIZER_FLAGS -fno-sanitize=function,alignment,pointer-overflow $DEBUG_FLAGS -fsanitize=fuzzer-no-link -Wno-error" \
    --with-ld-opt="$SANITIZER_FLAGS" >configure.log 2>&1 || { tail -30 configure.log >&2; exit 1; }
  make -j"$MAYHEM_JOBS" >make.log 2>&1 || { tail -40 make.log >&2; exit 1; }
)

# nginx.o holds nginx's main(); keep its other symbols (ngx_argc, ngx_signal, ...) for the link
objcopy --redefine-sym main=nginx_original_main "$F/objs/src/core/nginx.o" "$F/objs/nginx_lib.o"
mapfile -t NGX_OBJS < <(find "$F/objs" -name '*.o' ! -name nginx.o ! -name nginx_lib.o | sort)
INCS=()
for w in $(sed -n '/^ALL_INCS = /,/[^\\]$/p' "$F/objs/Makefile" | sed 's/^ALL_INCS = //'); do
  d="${w#-I}"
  [ -n "$d" ] && [ "$d" != '\\' ] || continue
  case "$d" in /*) INCS+=("-I$d") ;; *) INCS+=("-I$F/$d") ;; esac
done
INCS+=("-I$SRC/src")
INCS+=("-I$F/objs")
LIBS=(-lz -ldl -lpthread -lcrypt -lm)

SAN_NOLINK="-fsanitize=fuzzer-no-link"
$CC -c $SANITIZER_FLAGS $DEBUG_FLAGS "$STANDALONE_FUZZ_MAIN" -o "$B/standalone_main.o"
$CXX -c $SANITIZER_FLAGS $DEBUG_FLAGS "$SRC/mayhem/lsan_off.cc" -o "$B/lsan_off.o"

for h in fuzz_cluster_nodes fuzz_info fuzz_msgid; do
  $CC -c $SANITIZER_FLAGS -fno-sanitize=function,alignment,pointer-overflow $DEBUG_FLAGS $SAN_NOLINK -Wno-error \
      "${INCS[@]}" "$SRC/mayhem/harnesses/$h.c" -o "$B/$h.o"
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$B/$h.o" "$B/lsan_off.o" \
      "$F/objs/nginx_lib.o" "${NGX_OBJS[@]}" "${LIBS[@]}" -o "$SRC/$h"
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS "$B/$h.o" "$B/standalone_main.o" "$B/lsan_off.o" \
      "$F/objs/nginx_lib.o" "${NGX_OBJS[@]}" "${LIBS[@]}" -o "$SRC/$h-standalone"
done

# 2) test build: the project's normal flags, no sanitizers
T="$B/test"
prepare_tree "$T"
(
  cd "$T"
  ./configure --with-cc="$CC" "${NGX_OPTS[@]}" --with-cc-opt="-O1 -g $COVERAGE_FLAGS" --with-ld-opt="$COVERAGE_FLAGS" \
    >configure.log 2>&1 || { tail -30 configure.log >&2; exit 1; }
  make -j"$MAYHEM_JOBS" >make.log 2>&1 || { tail -40 make.log >&2; exit 1; }
)
test -x "$T/objs/nginx"

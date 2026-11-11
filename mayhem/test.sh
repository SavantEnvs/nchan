#!/usr/bin/env bash
#
# mayhem/test.sh — RUN nchan end to end: start the nginx+nchan server that mayhem/build.sh built with
# the project's normal flags, then publish and subscribe over real HTTP and assert on what comes back.
# (nchan's own suite is a ruby/redis integration rig that needs a running Redis and a gem set; this
# drives the same publisher / subscriber / channel-info paths against known inputs and outputs.)
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

NGINX="$SRC/mayhem/build/test/objs/nginx"
if [ ! -x "$NGINX" ]; then
  echo "missing $NGINX: mayhem/build.sh did not build it" >&2
  emit_ctrf nchan-http 0 1
  exit $?
fi

D=$(mktemp -d)
trap 'kill "$(cat "$D/nginx.pid" 2>/dev/null)" 2>/dev/null; sleep 0.2; rm -rf "$D"' EXIT
PORT=$(( 20000 + RANDOM % 20000 ))
mkdir -p "$D/logs"
cat > "$D/nginx.conf" <<CONF
worker_processes 1;
daemon on;
pid $D/nginx.pid;
error_log $D/error.log info;
events { worker_connections 64; }
http {
  access_log off;
  nchan_max_reserved_memory 16M;
  client_body_temp_path $D/body;
  server {
    listen 127.0.0.1:$PORT;
    location = /pub {
      nchan_publisher;
      nchan_channel_id chan1;
      nchan_message_buffer_length 10;
    }
    location = /sub {
      nchan_subscriber;
      nchan_channel_id chan1;
      nchan_subscriber_first_message oldest;
    }
    location = /msub {
      nchan_subscriber;
      nchan_channel_id chan1 chan2;
      nchan_subscriber_first_message oldest;
    }
    location = /pub2 {
      nchan_publisher;
      nchan_channel_id chan2;
    }
  }
}
CONF

"$NGINX" -p "$D" -c "$D/nginx.conf" -e "$D/error.log" || true
for i in $(seq 1 50); do
  curl -s -o /dev/null "http://127.0.0.1:$PORT/pub" && break
  sleep 0.1
done

passed=0; failed=0
check() { # name expected actual
  if [ "$2" = "$3" ]; then passed=$((passed+1)); echo "PASS $1"
  else failed=$((failed+1)); echo "FAIL $1: expected [$2] got [$3]"; fi
}
U="http://127.0.0.1:$PORT"

r=$(curl -s -X POST --data-binary 'hello world' "$U/pub")
check publish-1-reply "$(printf 'queued messages: 1')" "$(echo "$r" | sed -n 's/^\(queued messages: [0-9]*\).*/\1/p')"

r=$(curl -s -X POST --data-binary 'second message' "$U/pub")
check publish-2-reply "queued messages: 2" "$(echo "$r" | sed -n 's/^\(queued messages: [0-9]*\).*/\1/p')"

hdrs=$(curl -s -D - -o "$D/sub1.body" "$U/sub")
check subscribe-oldest-body "hello world" "$(cat "$D/sub1.body")"
etag=$(echo "$hdrs" | tr -d '\r' | sed -n 's/^[Ee][Tt]ag: //p')
lm=$(echo "$hdrs" | tr -d '\r' | sed -n 's/^Last-Modified: //p')
check subscribe-oldest-etag-tag "0" "$etag"

curl -s -H "If-None-Match: $etag" -H "If-Modified-Since: $lm" -o "$D/sub2.body" "$U/sub"
check subscribe-resume-next-body "second message" "$(cat "$D/sub2.body")"

curl -s -H "Last-Event-ID: $(date -d "$lm" +%s):$etag" -o "$D/sub3.body" "$U/sub"
check subscribe-last-event-id-next-body "second message" "$(cat "$D/sub3.body")"

curl -s -X POST --data-binary 'other channel' "$U/pub2" > /dev/null
curl -s -o "$D/msub.body" "$U/msub"
check multiplexed-subscribe-oldest-body "hello world" "$(cat "$D/msub.body")"

r=$(curl -s -H 'Accept: text/json' "$U/pub")
check channel-info-json-messages "2" "$(echo "$r" | sed -n 's/.*"messages": *\([0-9]*\).*/\1/p')"

code=$(curl -s -o /dev/null -w '%{http_code}' -X DELETE "$U/pub")
check channel-delete-status "200" "$code"
r=$(curl -s "$U/pub")
check channel-after-delete-messages "0" "$(echo "$r" | sed -n 's/^queued messages: *\([0-9]*\).*/\1/p')"

emit_ctrf nchan-http "$passed" "$failed"

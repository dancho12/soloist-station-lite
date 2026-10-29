#!/bin/sh
export PATH="/bin:/usr/bin:/sbin:/usr/sbin:$PATH"
unset LD_LIBRARY_PATH LD_PRELOAD

BASE_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
[ -d "$BASE_DIR/bin" ] || BASE_DIR="/data/opt/soloist"
SOLOIST_BIN="$BASE_DIR/bin/soloist"

run_soloist() {
    "$BASE_DIR/lib64/ld-linux-aarch64.so.1" --library-path "$BASE_DIR/lib64" "$SOLOIST_BIN" "$@"
}

echo "=== Spotify Soloist Status ==="
run_soloist ctl -w 127.0.0.1:9090 status 2>/dev/null || echo "Soloist daemon: NOT RUNNING"
echo ""
echo "=== Current Track ==="
run_soloist ctl -w 127.0.0.1:9090 now 2>/dev/null || echo "No track active"
echo ""
echo "=== Processes ==="
for name in soloist bridge; do
    pid=$(cat "$BASE_DIR/data/$name.pid" 2>/dev/null || true)
    case "$pid" in ''|*[!0-9]*) echo "$name: no PID" ;; *)
        if [ -d "/proc/$pid" ]; then echo "$name: PID $pid"; else echo "$name: stopped"; fi ;;
    esac
done

#!/bin/sh
export PATH="/bin:/usr/bin:/sbin:/usr/sbin:$PATH"
unset LD_LIBRARY_PATH LD_PRELOAD

# Kill the PID from a pid-file only if it still runs our installed executable.
# (pid-files live in /data and survive reboots, so the PID may have been reused).
kill_pidfile() {
    pidfile="$1"; expected="$2"
    [ -f "$pidfile" ] || return 0
    pid=$(cat "$pidfile" 2>/dev/null || true)
    case "$pid" in *[!0-9]*|'') pid='' ;; esac
    if [ -n "$pid" ] && [ "$(readlink "/proc/$pid/exe" 2>/dev/null)" = "/data/opt/soloist/bin/$expected" ]; then
        kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$pidfile"
}

kill_pidfile /data/opt/soloist/data/bridge.pid soloist-bridge

kill_pidfile /data/opt/soloist/data/soloist.pid soloist

echo "Spotify Soloist and Bridge stopped."

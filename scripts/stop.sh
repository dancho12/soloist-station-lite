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
    if [ -n "$pid" ]; then
        target=$(readlink "/proc/$pid/exe" 2>/dev/null || true)
        case "$target" in
            "/data/opt/soloist/bin/$expected"|"/bkupgrade/data/opt/soloist/bin/$expected") valid=1 ;;
            /data/opt/soloist/lib64/ld-linux-aarch64.so.1|/bkupgrade/data/opt/soloist/lib64/ld-linux-aarch64.so.1)
                if tr '\000' '\n' < "/proc/$pid/cmdline" 2>/dev/null | grep -Fxq "/data/opt/soloist/bin/$expected"; then
                    valid=1
                else
                    valid=0
                fi ;;
            *) valid=0 ;;
        esac
        if [ "$valid" = 1 ]; then
            kill "$pid" 2>/dev/null || true
        fi
    fi
    rm -f "$pidfile"
}

kill_pidfile /data/opt/soloist/data/bridge.pid soloist-bridge

guard_file=/data/opt/soloist/data/guard.pid
if [ -f "$guard_file" ]; then
    guard_pid=$(cat "$guard_file" 2>/dev/null || true)
    case "$guard_pid" in ''|*[!0-9]*) guard_pid='' ;; esac
    if [ -n "$guard_pid" ] && tr '\000' '\n' < "/proc/$guard_pid/cmdline" 2>/dev/null | grep -Fxq /data/opt/soloist/start.sh; then
        kill "$guard_pid" 2>/dev/null || true
    fi
    rm -f "$guard_file"
fi

kill_pidfile /data/opt/soloist/data/soloist.pid soloist

echo "Spotify Soloist and Bridge stopped."

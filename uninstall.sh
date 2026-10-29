#!/bin/sh
set -e

export PATH="/bin:/usr/bin:/sbin:/usr/sbin:$PATH"
unset LD_LIBRARY_PATH LD_PRELOAD

echo "=== Удаление Spotify Soloist + Bridge ==="
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Требуются права root!" >&2
    exit 1
fi

INSTALL_DIR=/data/opt/soloist
INIT_SCRIPT=/etc/init.d/S99spotify-connect
if [ ! -f "$INSTALL_DIR/.managed-by-alice-root" ]; then
    echo "ERROR: This installation was not created by the prepared installer; refusing to delete unknown files." >&2
    exit 1
fi
if [ -e "$INIT_SCRIPT" ] && ! cmp -s "$INIT_SCRIPT" "$INSTALL_DIR/S99spotify-connect.installed"; then
    echo "ERROR: The init script changed since installation. Inspect it before uninstalling." >&2
    exit 1
fi

[ ! -x "/data/opt/soloist/stop.sh" ] || /data/opt/soloist/stop.sh
for exe in /proc/[0-9]*/exe; do
    target=$(readlink "$exe" 2>/dev/null || true)
    case "$target" in
        "$INSTALL_DIR"/bin/*|/bkupgrade/data/opt/soloist/bin/*)
            echo "ERROR: A Soloist process is still running ($exe). Stop it before deleting files." >&2
            exit 1 ;;
        "$INSTALL_DIR"/lib64/ld-linux-aarch64.so.1|/bkupgrade/data/opt/soloist/lib64/ld-linux-aarch64.so.1)
            pid=${exe#/proc/}; pid=${pid%/exe}
            if tr '\000' '\n' < "/proc/$pid/cmdline" 2>/dev/null | grep -Fxq "$INSTALL_DIR/bin/soloist"; then
                echo "ERROR: A Soloist process is still running ($exe). Stop it before deleting files." >&2
                exit 1
            fi ;;
    esac
done

if [ -e "$INIT_SCRIPT" ]; then
    mount -o remount,rw /
    trap 'mount -o remount,ro / 2>/dev/null || true' EXIT
    rm -f "$INIT_SCRIPT"
    mount -o remount,ro /
    trap - EXIT
fi

rm -rf "$INSTALL_DIR" /tmp/soloist_cache
rm -f /tmp/soloist.log /tmp/soloist-bridge.log
echo "Spotify Soloist и Bridge успешно удалены."

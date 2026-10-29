#!/bin/sh
# Read-only checks to run on each speaker before attempting an install.
set -u
printf 'model: '
tr '\000' ' ' < /proc/device-tree/compatible 2>/dev/null || true
printf '\narchitecture: '
uname -m
printf 'free /data (KiB): '
df -k /data | awk 'NR==2 {print $4}'
printf 'trusted CA bundle: '
if [ -s /etc/ssl/certs/ca-certificates.crt ]; then
    echo /etc/ssl/certs/ca-certificates.crt
elif [ -s /system/vendor/quasar/ca-certificates.crt ]; then
    echo /system/vendor/quasar/ca-certificates.crt
else
    echo missing
fi
printf 'ALSA devices: '
cat /proc/asound/cards 2>/dev/null || true
printf 'existing Soloist directory: '
if [ -e /data/opt/soloist ]; then echo present; else echo absent; fi
printf 'existing Soloist init script: '
if [ -e /etc/init.d/S99spotify-connect ]; then echo present; else echo absent; fi
printf 'root mount: '
awk '$2 == "/" {print $4}' /proc/mounts

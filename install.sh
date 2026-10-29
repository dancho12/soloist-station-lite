#!/bin/sh
set -e

# Sanitize PATH and library environment so Entware (/opt) or custom LD_LIBRARY_PATH
# cannot conflict with system tools or soloist bundled glibc
export PATH="/bin:/usr/bin:/sbin:/usr/sbin:$PATH"
unset LD_LIBRARY_PATH LD_PRELOAD

echo "=== Spotify Soloist Universal Installer for Yandex Station (aarch64) ==="

# 1. Root check
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Этот скрипт должен выполняться от root на колонке!" >&2
    exit 1
fi

# 2. Arch check
ARCH=$(uname -m)
if [ "$ARCH" != "aarch64" ]; then
    echo "ERROR: Архитектура ядра $ARCH не поддерживается (требуется aarch64)." >&2
    exit 1
fi

# 3. Free space check (need ~40 MB in /data)
FREE_KB=$(df /data | awk 'NR==2 {print $4}')
if [ "$FREE_KB" -lt 35000 ]; then
    echo "ERROR: Недостаточно места в /data (доступно ${FREE_KB} KB, нужно минимум 35000 KB)." >&2
    exit 1
fi

# Never install a repackaged or unverified playback binary. Fetch Soloist from
# Spotify's official ARM64 download immediately before installation.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ ! -s "$SCRIPT_DIR/bin/soloist" ] || [ ! -s "$SCRIPT_DIR/bin/soloist.official.sha256" ]; then
    echo "ERROR: Run prepare-official.ps1 on the PC to stage an official Soloist build." >&2
    exit 1
fi
EXPECTED_SHA=$(cat "$SCRIPT_DIR/bin/soloist.official.sha256")
ACTUAL_SHA=$(sha256sum "$SCRIPT_DIR/bin/soloist" | cut -d' ' -f1)
if [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
    echo "ERROR: Soloist binary does not match the staged official download." >&2
    exit 1
fi
for required in lib64/ld-linux-aarch64.so.1 lib64/libpulse.so.0 scripts/S99spotify-connect scripts/stop.sh scripts/status.sh; do
    if [ ! -s "$SCRIPT_DIR/$required" ]; then
        echo "ERROR: Missing runtime file: $required" >&2
        exit 1
    fi
done

INSTALL_DIR="/data/opt/soloist"
if [ -e "$INSTALL_DIR" ] || [ -e /etc/init.d/S99spotify-connect ]; then
    echo "ERROR: Existing Soloist files found. Inspect and remove them before a fresh install." >&2
    exit 1
fi
if pidof spotiya >/dev/null 2>&1; then
    echo "ERROR: Spotiya is running. Stop it separately before installing Soloist." >&2
    exit 1
fi

CERT_FILE=/etc/ssl/certs/ca-certificates.crt
if [ ! -s "$CERT_FILE" ]; then
    CERT_FILE=/system/vendor/quasar/ca-certificates.crt
fi
if [ ! -s "$CERT_FILE" ]; then
    echo "ERROR: No trusted CA bundle found; system files will not be modified to create one." >&2
    exit 1
fi

# 4. API Key
API_KEY="${1:-}"
if [ -z "$API_KEY" ]; then
    if [ -f "/data/opt/soloist/start.sh" ]; then
        SAVED_KEY=$(grep -o 'API_KEY="[^"]*"' /data/opt/soloist/start.sh 2>/dev/null | cut -d'"' -f2 || true)
    fi
    if [ -n "$SAVED_KEY" ] && [ "$SAVED_KEY" != "dummy" ]; then
        API_KEY="$SAVED_KEY"
        echo "Найден сохранённый API-ключ: ${API_KEY:0:8}..."
    else
        echo ""
        echo "Для работы требуется Soloist API Key от Spotify."
        echo "Получить его можно за 30 секунд (нужен Spotify Premium):"
        echo "https://developer.spotify.com/dashboard/soloist"
        echo ""
        printf "Введите ваш API-ключ (spak_...): "
        if [ -t 0 ]; then
            stty -echo
            trap 'stty echo' EXIT INT TERM
            read -r API_KEY
            stty echo
            trap - EXIT INT TERM
            printf '\n'
        else
            read -r API_KEY
        fi
    fi
fi

if [ -z "$API_KEY" ]; then
    echo "ERROR: API-ключ не может быть пустым!" >&2
    exit 1
fi

# 5. Spotify Web API Credentials (for Alice Voice Track Search)
CLIENT_ID=""
CLIENT_SECRET=""

if [ -f "$SCRIPT_DIR/bin/soloist-bridge" ]; then
if [ -f "/data/opt/soloist/spotify_api.conf" ]; then
    SAVED_CID=$(grep -o 'SPOTIFY_CLIENT_ID="[^"]*"' /data/opt/soloist/spotify_api.conf 2>/dev/null | cut -d'"' -f2 || true)
    SAVED_SEC=$(grep -o 'SPOTIFY_CLIENT_SECRET="[^"]*"' /data/opt/soloist/spotify_api.conf 2>/dev/null | cut -d'"' -f2 || true)
fi

if [ -n "$SAVED_CID" ] && [ -n "$SAVED_SEC" ]; then
    CLIENT_ID="$SAVED_CID"
    CLIENT_SECRET="$SAVED_SEC"
    echo "Найдены сохранённые ключи голосового поиска Spotify Web API."
else
    echo ""
    echo "======================================================================="
    echo " 🎙️  НАСТРОЙКА ГОЛОСОВОГО ПОИСКА ТРЕКОВ ЧЕРЕЗ АЛИСУ (SPOTIFY WEB API)"
    echo "======================================================================="
    echo "Чтобы Алиса могла искать ЛЮБЫЕ песни, альбомы и группы по вашему голосу,"
    echo "нужны бесплатные ключи разработчика Spotify Web API (Client ID и Secret)."
    echo ""
    echo "Как получить за 1 минуту:"
    echo "  1. Откройте: https://developer.spotify.com/dashboard"
    echo "  2. Нажмите 'Create app' (любое имя, Redirect URI: http://localhost:8888/callback)"
    echo "  3. Зайдите в Settings и скопируйте Client ID и Client Secret."
    echo ""
    printf "Введите Spotify Client ID (или Enter для пропуска): "
    read CLIENT_ID
    if [ -n "$CLIENT_ID" ]; then
        printf "Введите Spotify Client Secret: "
        read CLIENT_SECRET
    fi

    if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; then
        printf "\n\033[1;31m***********************************************************************\033[0m\n"
        printf "\033[1;31m*                               ВНИМАНИЕ!                             *\033[0m\n"
        printf "\033[1;31m*  ВЫ ПРОПУСТИЛИ ВВОД КЛЮЧЕЙ ГОЛОСОВОГО ПОИСКА SPOTIFY WEB API!       *\033[0m\n"
        printf "\033[1;31m*                                                                     *\033[0m\n"
        printf "\033[1;31m*  Голосовой поиск песен («Алиса, включи песню ...») работать НЕ      *\033[0m\n"
        printf "\033[1;31m*  БУДЕТ! Колонка сможет работать только как обычный Spotify Connect  *\033[0m\n"
        printf "\033[1;31m*  приёмник (выбор треков только через приложение Spotify с телефона).*\033[0m\n"
        printf "\033[1;31m*                                                                     *\033[0m\n"
        printf "\033[1;31m*  Вы сможете добавить ключи позже в:                                 *\033[0m\n"
        printf "\033[1;31m*  /data/opt/soloist/spotify_api.conf                                 *\033[0m\n"
        printf "\033[1;31m***********************************************************************\033[0m\n\n"
        sleep 2
    fi
fi
fi

# 6. Model & Device Name Detection
DT_COMPAT=""
if [ -f /proc/device-tree/compatible ]; then
    DT_COMPAT=$(tr '\0' ' ' < /proc/device-tree/compatible 2>/dev/null || true)
fi

DETECTED_MODEL="Yandex Station"
case "$DT_COMPAT" in
    *station-micro*|*micro*)
        DETECTED_MODEL="Yandex Station Lite"
        ;;
    *plum*)
        DETECTED_MODEL="Yandex Station Lite 2"
        ;;
    *station-mini2*)
        DETECTED_MODEL="Yandex Station Mini 2"
        ;;
    *station-mini3*|*bergamot*)
        DETECTED_MODEL="Yandex Station Mini 3"
        ;;
    *station-mini*)
        DETECTED_MODEL="Yandex Station Mini"
        ;;
    *station-midi*|*midi*)
        DETECTED_MODEL="Yandex Station 2"
        ;;
    *cucumber*|*amlogic,a5*|*amlogic,\ a5*)
        DETECTED_MODEL="Yandex Station Midi"
        ;;
    *pickle*)
        DETECTED_MODEL="Yandex Station Mini 3 Pro"
        ;;
esac

echo "Определена модель: $DETECTED_MODEL ($ARCH)"

DEVICE_NAME="${2:-$DETECTED_MODEL}"

# These values are written into start.sh inside double quotes: refuse characters that would break it
case "$API_KEY" in
    *[!A-Za-z0-9_-]*) echo "ERROR: API-ключ содержит недопустимые символы." >&2; exit 1 ;;
esac
case "$DEVICE_NAME" in
    *[\"\$\`\\]*) echo "ERROR: Имя устройства не должно содержать \" \$ \` или \\." >&2; exit 1 ;;
esac

# 7. Create directories
mkdir -p "$INSTALL_DIR/bin" "$INSTALL_DIR/lib64" "$INSTALL_DIR/scripts" "$INSTALL_DIR/data" "/tmp/soloist_cache"
printf 'soloist-station-lite managed install\n' > "$INSTALL_DIR/.managed-by-alice-root"

# 8. Copy files
echo "Копирование бинарников и библиотек..."
cp -f "$SCRIPT_DIR/bin/soloist" "$INSTALL_DIR/bin/soloist"
if [ -f "$SCRIPT_DIR/bin/soloist-bridge" ]; then
    cp -f "$SCRIPT_DIR/bin/soloist-bridge" "$INSTALL_DIR/bin/soloist-bridge"
    chmod 755 "$INSTALL_DIR/bin/soloist-bridge"
fi
if [ -f "$SCRIPT_DIR/bin/curl" ]; then
    cp -f "$SCRIPT_DIR/bin/curl" "$INSTALL_DIR/bin/curl"
    chmod 755 "$INSTALL_DIR/bin/curl"
fi
cp -af "$SCRIPT_DIR/lib64/"* "$INSTALL_DIR/lib64/"
cp -f "$SCRIPT_DIR/scripts/stop.sh" "$INSTALL_DIR/stop.sh"
cp -f "$SCRIPT_DIR/scripts/status.sh" "$INSTALL_DIR/status.sh"
if [ -f "$SCRIPT_DIR/uninstall.sh" ]; then
    cp -f "$SCRIPT_DIR/uninstall.sh" "$INSTALL_DIR/uninstall.sh"
    chmod 755 "$INSTALL_DIR/uninstall.sh"
fi
if [ -f "$SCRIPT_DIR/scripts/toggle.sh" ]; then
    cp -f "$SCRIPT_DIR/scripts/toggle.sh" "$INSTALL_DIR/scripts/toggle.sh"
    chmod 755 "$INSTALL_DIR/scripts/toggle.sh"
fi
if [ -f "$SCRIPT_DIR/scripts/search_and_play.sh" ]; then
    cp -f "$SCRIPT_DIR/scripts/search_and_play.sh" "$INSTALL_DIR/scripts/search_and_play.sh"
    chmod 755 "$INSTALL_DIR/scripts/search_and_play.sh"
fi

for helper in control.sh request_state.sh soloist-cli soloist-service.sh; do
    if [ -f "$SCRIPT_DIR/scripts/$helper" ]; then
        cp -f "$SCRIPT_DIR/scripts/$helper" "$INSTALL_DIR/scripts/$helper"
        chmod 755 "$INSTALL_DIR/scripts/$helper"
    fi
done

if [ -f "$SCRIPT_DIR/scripts/soloist-cli" ]; then
    cp -f "$SCRIPT_DIR/scripts/soloist-cli" "$INSTALL_DIR/bin/soloist-cli"
    chmod 755 "$INSTALL_DIR/bin/soloist-cli"
    mkdir -p /data/opt/bin
    ln -sf "$INSTALL_DIR/bin/soloist-cli" /data/opt/bin/soloist 2>/dev/null || true
    ln -sf "$INSTALL_DIR/bin/soloist-cli" /data/opt/bin/soloistctl 2>/dev/null || true
fi

printf "v1.2.0\n" > "$INSTALL_DIR/version"

# Spotify Search API Credentials
if [ -n "$CLIENT_ID" ] && [ -n "$CLIENT_SECRET" ]; then
    cat << EOF_CONF > "$INSTALL_DIR/spotify_api.conf"
SPOTIFY_CLIENT_ID="$CLIENT_ID"
SPOTIFY_CLIENT_SECRET="$CLIENT_SECRET"
EOF_CONF
    chmod 600 "$INSTALL_DIR/spotify_api.conf"
    echo "Конфигурация голосового поиска успешно сохранена в $INSTALL_DIR/spotify_api.conf"
elif [ -f "$SCRIPT_DIR/spotify_api.conf" ] && [ ! -f "$INSTALL_DIR/spotify_api.conf" ]; then
    cp -f "$SCRIPT_DIR/spotify_api.conf" "$INSTALL_DIR/spotify_api.conf"
    chmod 600 "$INSTALL_DIR/spotify_api.conf"
elif [ -f "$SCRIPT_DIR/spotify_api.conf.example" ] && [ ! -f "$INSTALL_DIR/spotify_api.conf" ]; then
    cp -f "$SCRIPT_DIR/spotify_api.conf.example" "$INSTALL_DIR/spotify_api.conf.example"
fi

chmod 755 "$INSTALL_DIR/bin/soloist" "$INSTALL_DIR/lib64/ld-linux-aarch64.so.1"
chmod 755 "$INSTALL_DIR/stop.sh" "$INSTALL_DIR/status.sh"

# 9. Generate start.sh. No Spotify DNS overrides, proxy, or CA edits.
echo "Генерация start.sh..."
cat << START_EOF > "$INSTALL_DIR/start.sh"
#!/bin/sh
set -e

# Sanitize PATH and library environment so Entware (/opt) or custom LD_LIBRARY_PATH
# cannot conflict with system tools or soloist bundled glibc
export PATH="/bin:/usr/bin:/sbin:/usr/sbin:\$PATH"
unset LD_LIBRARY_PATH LD_PRELOAD

mkdir -p /data/opt/soloist/data /tmp/soloist_cache/cache /tmp/soloist_cache/Storage /data/opt/soloist/data/cache /data/opt/soloist/scripts
if [ ! -L /data/opt/soloist/data/cache/Storage ]; then
    rm -rf /data/opt/soloist/data/cache/Storage 2>/dev/null || true
    ln -sfn /tmp/soloist_cache/Storage /data/opt/soloist/data/cache/Storage 2>/dev/null || true
fi
/data/opt/soloist/stop.sh >/dev/null 2>&1 || true

# 0. Enable zram compressed swap (64MB) if available and inactive to prevent OOM
if [ -e /dev/zram0 ] && [ "\$(cat /sys/block/zram0/disksize 2>/dev/null)" = "0" ]; then
    echo 67108864 > /sys/block/zram0/disksize 2>/dev/null || true
    mkswap /dev/zram0 >/dev/null 2>&1 || true
    swapon /dev/zram0 >/dev/null 2>&1 || true
    sysctl -w vm.swappiness=20 >/dev/null 2>&1 || true
    sysctl -w vm.vfs_cache_pressure=150 >/dev/null 2>&1 || true
fi

for i in \$(seq 1 45); do
    if ip -4 addr show wlan0 2>/dev/null | grep -q "inet "; then
        if ping -c 1 -W 1 1.1.1.1 >/dev/null 2>&1 || ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1; then
            break
        fi
    fi
    sleep 1
done
sleep 2

export APULSE_PLAYBACK_DEVICE=plug:default
export APULSE_DIAG=0
export CURL_CA_BUNDLE="$CERT_FILE"
export SSL_CERT_FILE="$CERT_FILE"
export MALLOC_ARENA_MAX=1
export MALLOC_TRIM_THRESHOLD_=131072
export MALLOC_MMAP_THRESHOLD_=131072

API_KEY="$API_KEY"

nohup /data/opt/soloist/lib64/ld-linux-aarch64.so.1 \\
    --library-path /data/opt/soloist/lib64 \\
    /data/opt/soloist/bin/soloist \\
    -n "$DEVICE_NAME" \\
    -k "\$API_KEY" \\
    -D /data/opt/soloist/data \\
    -C /tmp/soloist_cache \\
    -w 127.0.0.1:9090 \\
    --initial-volume 40 \\
    > /tmp/soloist.log 2>&1 &

echo \$! > /data/opt/soloist/data/soloist.pid
echo "Spotify Soloist (arm64) started, PID=\$(cat /data/opt/soloist/data/soloist.pid)"

sleep 1

# The Quasar voice/button bridge is intentionally opt-in. It can conflict with
# native Yandex Music and needs separate validation for Mini 2 and Mini 3.
if [ -f /data/opt/soloist/bridge-enabled ] && [ -x /data/opt/soloist/bin/soloist-bridge ]; then
    if /sbin/start-stop-daemon -S -b -m -p /data/opt/soloist/data/bridge.pid -a /bin/sh -- -c "exec /data/opt/soloist/bin/soloist-bridge >> /tmp/soloist-bridge.log 2>&1"; then
        echo "Soloist Bridge started, PID=\$(cat /data/opt/soloist/data/bridge.pid 2>/dev/null)"
    else
        echo "Soloist Bridge did not start" >&2
    fi
fi

# Activation & RAM cache guard
(
    # 1. Wait for daemon to become ready and activate device if logged in
    for attempt in \$(seq 1 15); do
        sleep 2
        STATUS=\$(/data/opt/soloist/lib64/ld-linux-aarch64.so.1 --library-path /data/opt/soloist/lib64 /data/opt/soloist/bin/soloist ctl -w 127.0.0.1:9090 status 2>/dev/null || true)
        if echo "\$STATUS" | grep -qi "logged in: yes"; then
            /data/opt/soloist/lib64/ld-linux-aarch64.so.1 --library-path /data/opt/soloist/lib64 /data/opt/soloist/bin/soloist ctl -w 127.0.0.1:9090 activate >/dev/null 2>&1 || true
            break
        fi
    done

    # 2. RAM guard: keep audio stream cache under 20MB so tmpfs never exhausts RAM
    while [ -x /data/opt/soloist/bin/soloist ]; do
        sleep 120
        if [ -d /tmp/soloist_cache/cache ]; then
            CACHE_KB=\$(du -sk /tmp/soloist_cache/cache 2>/dev/null | awk '{print \$1}')
            if [ "\${CACHE_KB:-0}" -gt 20480 ]; then
                find /tmp/soloist_cache/cache -type f -amin +10 -delete 2>/dev/null || true
                CACHE_KB_AFTER=\$(du -sk /tmp/soloist_cache/cache 2>/dev/null | awk '{print \$1}')
                if [ "\${CACHE_KB_AFTER:-0}" -gt 20480 ]; then
                    rm -rf /tmp/soloist_cache/cache/* 2>/dev/null || true
                fi
            fi
        fi
    done
) &
echo \$! > /data/opt/soloist/data/guard.pid
START_EOF
chmod 700 "$INSTALL_DIR/start.sh"   # contains the Soloist API key

# 10. Keep the first trial in /data only. Enable persistent startup separately
# after playback and rollback have been checked on the actual station.
if [ "${SOLOIST_ENABLE_AUTOSTART:-0}" = 1 ]; then
    echo "Настройка автозапуска при включении колонки..."
    mount -o remount,rw /
    trap 'mount -o remount,ro / 2>/dev/null || true' EXIT
    cp -f "$SCRIPT_DIR/scripts/S99spotify-connect" /etc/init.d/S99spotify-connect
    chmod 755 /etc/init.d/S99spotify-connect
    cp -f "$SCRIPT_DIR/scripts/S99spotify-connect" "$INSTALL_DIR/S99spotify-connect.installed"
    mount -o remount,ro /
    trap - EXIT
else
    echo "Пробный запуск: автозапуск не установлен; корневая ФС не менялась."
fi

# 12. Start service
echo "Запуск службы..."
"$INSTALL_DIR/start.sh"
sleep 2
SOLOIST_PID=$(cat "$INSTALL_DIR/data/soloist.pid" 2>/dev/null || true)
if [ -z "$SOLOIST_PID" ] || ! kill -0 "$SOLOIST_PID" 2>/dev/null ||
   ! "$INSTALL_DIR/lib64/ld-linux-aarch64.so.1" --library-path "$INSTALL_DIR/lib64" \
      "$INSTALL_DIR/bin/soloist" ctl -w 127.0.0.1:9090 status >/dev/null 2>&1; then
    echo "ERROR: Soloist did not stay running; inspect /tmp/soloist.log." >&2
    exit 1
fi

echo ""
echo "=== Установка успешно завершена! ==="
echo "Имя устройства в Spotify: $DEVICE_NAME"
echo ""
if [ -f "$INSTALL_DIR/bridge-enabled" ] && [ -x "$INSTALL_DIR/bin/soloist-bridge" ]; then
    echo "Мост Quasar включён; управление голосом и кнопками требует проверки на устройстве."
else
    echo "Мост Quasar выключен; голос и кнопки остаются у штатной Алисы."
fi
echo ""
if [ -e /etc/init.d/S99spotify-connect ]; then
    echo "Автозагрузка включена через /etc/init.d/S99spotify-connect"
else
    echo "Автозагрузка выключена; после перезагрузки пробный Soloist не запустится."
fi
echo ""
echo "Статус: $INSTALL_DIR/status.sh"
echo "Остановить: $INSTALL_DIR/stop.sh"
echo "Запустить: $INSTALL_DIR/start.sh"
echo "=========================================================="

# 12. Cleanup temporary installer files to prevent cluttering /data
if [ -d "/data/local/tmp/soloist-station-lite" ] && [ "$SCRIPT_DIR" = "/data/local/tmp/soloist-station-lite" ]; then
    echo "Очистка временных файлов установки..."
    rm -f /data/local/tmp/soloist-station-lite.tar.gz 2>/dev/null || true
    # Remove installer directory on shell exit
    trap 'rm -rf /data/local/tmp/soloist-station-lite 2>/dev/null || true' EXIT
fi

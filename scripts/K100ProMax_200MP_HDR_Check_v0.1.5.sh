#!/system/bin/sh
# Read-only diagnostic for K100 Pro Max 200MP HDR module v0.1.5.
# Run as root while com.android.camera remains open in 200MP mode.

module=dev.songyuan.hdr
camera=com.android.camera
expected_hash=0084fc90461eb6c8473d768532ed40e06febe8160f5974dd2998b79654856d87

if [ "$(id -u)" != 0 ]; then
    echo 'Run as root: su -c "sh /sdcard/Download/K100ProMax_200MP_HDR_Check_v0.1.5.sh"'
    exit 1
fi

user_id=$(am get-current-user 2>/dev/null | tail -n 1)
case "$user_id" in ''|*[!0-9]*) user_id=0 ;; esac
printf '%s\n' '=== Device ==='
printf 'device=%s sdk=%s user=%s logd=%s\n' \
    "$(getprop ro.product.device)" "$(getprop ro.build.version.sdk)" \
    "$user_id" "$(getprop init.svc.logd)"

package_path() {
    pm path --user "$user_id" "$1" 2>/dev/null | sed -n 's/^package://p' | head -n 1
}

module_apk=$(package_path "$module")
printf '\n%s\n' '=== Installed module ==='
printf 'module_apk=%s\n' "${module_apk:-unavailable}"
if [ -n "$module_apk" ] && [ -r "$module_apk" ]; then
    actual_hash=$(sha256sum "$module_apk" 2>/dev/null | awk '{print $1}')
    printf 'module_sha256=%s\n' "${actual_hash:-unavailable}"
    if [ "$actual_hash" = "$expected_hash" ]; then
        echo 'module_build=matches_v0.1.5'
    else
        echo 'module_build=does_not_match_v0.1.5'
    fi
fi

printf '\n%s\n' '=== Camera process ==='
camera_pids=$(pidof "$camera" 2>/dev/null)
printf 'camera_pids=%s\n' "${camera_pids:-none}"
for pid in $camera_pids; do
    printf 'camera_pid=%s\n' "$pid"
    awk '/^Uid:/ {print "camera_uid=" $2; print "camera_user=" int($2 / 100000)}' \
        "/proc/$pid/status" 2>/dev/null
    if [ -r "/proc/$pid/stat" ]; then
        printf 'camera_start_ticks=%s\n' "$(awk '{print $22}' "/proc/$pid/stat" 2>/dev/null)"
    fi
done

printf '\n%s\n' '=== Module status journal (read-only) ==='
for root in /data/user /data/user_de; do
    app="$root/$user_id/$camera"
    cache="$app/cache"
    status="$cache/songyuan200hdr-status.properties"
    printf '\npath=%s\n' "$cache"
    ls -ldZ "$app" "$cache" 2>&1
    if [ -f "$status" ]; then
        ls -lZ "$status" 2>&1
        echo '--- status properties ---'
        cat "$status"
    else
        echo 'status_file=missing'
    fi
done

printf '\n%s\n' '=== LSPosed module logs ==='
pattern='Songyuan200HDR|dev[.]songyuan[.]hdr|K100 Pro Max 200MP HDR'
found=0
for folder in /data/adb/lspd/log /data/adb/vector/log; do
    [ -d "$folder" ] || continue
    for log in $(ls -t "$folder"/modules_*.log "$folder"/verbose_*.log 2>/dev/null | head -n 4); do
        [ -r "$log" ] || continue
        matches=$(tail -n 4000 "$log" 2>/dev/null | grep -Ei "$pattern" | tail -n 12)
        if [ -n "$matches" ]; then
            found=1
            printf '%s\n%s\n' "${log##*/}" "$matches"
        fi
    done
done
[ "$found" -eq 1 ] || echo 'framework_log_match=none'

printf '\n%s\n' '=== Android logcat ==='
if [ "$(getprop init.svc.logd)" = stopped ]; then
    echo 'logd=stopped; logcat flags may be unavailable'
fi
matches=$(logcat -b all -d -t 1200 2>&1 | grep -Ei "$pattern" | tail -n 16)
if [ -n "$matches" ]; then
    printf '%s\n' "$matches"
else
    echo 'target_logcat_match=none'
fi
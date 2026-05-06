#!/bin/bash
# ВКО Simulation — Командный Пункт ВКО (КП)
# Receives messages from all subsystems, maintains journals, DB, health checks.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_DIR/config.sh"
source "$PROJECT_DIR/lib.sh"

NAME="KP"

check_environment "$NAME"
acquire_lock "$NAME" || exit 1

# Trap for clean shutdown
cleanup() {
    echo "[$NAME] Завершение работы..."
    release_lock "$NAME"
    exit 0
}
trap cleanup SIGINT SIGTERM

# Initialize DB
db_init

# Track last health check time
declare -A last_ping_time
declare -A subsystem_alive
HEALTH_CHECK_COUNT=0
SUBSYSTEMS=("RLS1" "RLS2" "RLS3" "SPRO" "ZRDN1" "ZRDN2" "ZRDN3")
for sub in "${SUBSYSTEMS[@]}"; do
    subsystem_alive["$sub"]="starting"
    last_ping_time["$sub"]=0
done

echo "[$NAME] Командный пункт ВКО запущен. PID=$$"
log_to_file "$LOGS_DIR/kp.log" "[$NAME] Запуск КП ВКО"

# ─── Process a single incoming message ─────────────────────────────────────
process_message() {
    local file="$1"
    local ciphertext plaintext ts sender msg_type target_id x y info

    ciphertext=$(cat "$file" 2>/dev/null)
    [[ -z "$ciphertext" ]] && { rm -f "$file"; return; }

    plaintext=$(decrypt_message "$ciphertext" 2>/dev/null)
    if [[ -z "$plaintext" ]]; then
        log_to_file "$LOGS_DIR/kp.log" "[SECURITY] Попытка НСД: нерасшифрованное сообщение в файле $file"
        rm -f "$file"
        return
    fi

    # Parse: timestamp|sender|msg_type|target_id|x|y|extra
    IFS='|' read -r ts sender msg_type target_id x y info <<< "$plaintext"

    # Log to main journal
    local display_msg=""
    case "$msg_type" in
        detected)
            display_msg="$sender обнаружена цель ID:$target_id с координатами $x $y"
            ;;
        direction_spro)
            display_msg="$sender цель движется в направлении СПРО ID:$target_id"
            ;;
        shot)
            display_msg="$sender выстрел по цели ID:$target_id $info"
            ;;
        hit)
            display_msg="$sender цель уничтожена ID:$target_id $info"
            ;;
        miss)
            display_msg="$sender промах по цели ID:$target_id $info"
            ;;
        no_ammo)
            display_msg="$sender боекомплект израсходован"
            ;;
        ammo_restored)
            display_msg="$sender боекомплект пополнен $info"
            ;;
        pong)
            display_msg="$sender работоспособность подтверждена"
            subsystem_alive["$sender"]="alive"
            ;;
        status)
            display_msg="$sender статус: $info"
            ;;
        *)
            display_msg="$sender $msg_type ID:$target_id $info"
            ;;
    esac

    log_to_file "$LOGS_DIR/kp.log" "$display_msg"

    # Log to per-subsystem journal
    local sub_log="${LOGS_DIR}/${sender,,}.log"
    log_to_file "$sub_log" "$msg_type ID:$target_id $info"

    # Log to database
    db_log_event "$ts" "$sender" "$msg_type" "$target_id" "$x" "$y" "$info"

    # Track destruction stats in DB
    case "$msg_type" in
        hit|miss)
            local ttype="${target_id: -1:1}"  # last char of ID = type
            local tname=""
            case "$ttype" in
                b) tname="Бал.блок" ;;
                s) tname="Самолет" ;;
                r) tname="К.ракета" ;;
                *) tname="Неизвестно" ;;
            esac
            db_log_destruction "$ts" "$sender" "$target_id" "$tname" "$msg_type" "$x" "$y"
            ;;
    esac

    # Auto-resupply when ammo is depleted
    if [[ "$msg_type" == "no_ammo" ]]; then
        log_to_file "$LOGS_DIR/kp.log" "[$NAME] Отправка команды пополнения для $sender"
        send_kp_command "$sender" "resupply" "$AMMO_RESUPPLY_AMOUNT"
    fi

    rm -f "$file"
}

# ─── Health check ──────────────────────────────────────────────────────────
perform_health_check() {
    local now
    now=$(date +%s)
    ((HEALTH_CHECK_COUNT++))

    for sub in "${SUBSYSTEMS[@]}"; do
        local last="${last_ping_time[$sub]}"
        if (( now - last >= HEALTH_CHECK_INTERVAL )); then
            send_kp_command "$sub" "ping" "health_check"
            last_ping_time["$sub"]=$now

            # Log failure only after first check — give subsystems time to respond
            if [[ "${subsystem_alive[$sub]}" == "unknown" && $HEALTH_CHECK_COUNT -gt 1 ]]; then
                log_to_file "$LOGS_DIR/kp.log" "[$NAME] $sub не отвечает на проверку работоспособности"
                db_log_health "$(timestamp)" "$sub" "unreachable"
            fi
            subsystem_alive["$sub"]="unknown"
        fi
    done
}

# ─── Main loop ─────────────────────────────────────────────────────────────
echo "[$NAME] Начало основного цикла..."
# Give subsystems time to start up before first health check
sleep 2
while true; do
    # Process all incoming messages
    for file in "$TO_KP_DIR"/*; do
        [[ -f "$file" ]] || continue
        process_message "$file"
    done

    # Health checks
    perform_health_check

    sleep "$SLEEP_TIME"
done

cleanup

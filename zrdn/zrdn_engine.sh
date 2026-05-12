#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_DIR/config.sh"
source "$PROJECT_DIR/lib.sh"

check_environment "$ZRDN_NAME"
acquire_lock "$ZRDN_NAME" || exit 1

cleanup() {
    echo "[$ZRDN_NAME] Завершение работы..."
    release_lock "$ZRDN_NAME"
    exit 0
}
trap cleanup SIGINT SIGTERM

AMMO=$ZRDN_AMMO_INITIAL
LAST_RESUPPLY_TIME=0

declare -A first_x
declare -A first_y
declare -A detected_sent
declare -A ignore_target
declare -A shot_pending
declare -A shot_x
declare -A shot_y
declare -A shot_seen_after
declare -A shot_seen_x
declare -A shot_seen_y
declare -A last_seen

echo "[$ZRDN_NAME] ЗРДН запущен. Координаты: ($ZRDN_X, $ZRDN_Y), Радиус: $((ZRDN_RANGE/1000)) км"
echo "[$ZRDN_NAME] Боекомплект: $AMMO ракет"
log_to_file "$LOGS_DIR/${ZRDN_NAME,,}.log" "[$ZRDN_NAME] Запуск. X=$ZRDN_X Y=$ZRDN_Y, Радиус=$ZRDN_RANGE, БК=$AMMO"

process_kp_commands() {
    local cmd
    cmd=$(read_kp_command "$ZRDN_NAME" 2>/dev/null)
    [[ -z "$cmd" ]] && return

    IFS='|' read -r ts sender cmd_type payload <<< "$cmd"

    case "$cmd_type" in
        ping)
            send_to_kp "$ZRDN_NAME" "pong" "" "0" "0" "работоспособен, БК=$AMMO"
            ;;
        resupply)
            AMMO=$((AMMO + payload))
            LAST_RESUPPLY_TIME=$(date +%s)
            log_to_file "$LOGS_DIR/${ZRDN_NAME,,}.log" "[$ZRDN_NAME] Пополнение БК на $payload. БК: $AMMO"
            send_to_kp "$ZRDN_NAME" "ammo_restored" "" "0" "0" "пополнено по команде КП на $payload, БК=$AMMO"
            ;;
    esac
}

cleanup_stale() {
    local now target_id
    now=$(date +%s)
    for target_id in "${!last_seen[@]}"; do
        if (( now - ${last_seen[$target_id]} > 12 )); then
            unset "last_seen[$target_id]"
            unset "first_x[$target_id]"
            unset "first_y[$target_id]"
            unset "detected_sent[$target_id]"
            unset "ignore_target[$target_id]"
            unset "shot_pending[$target_id]"
            unset "shot_x[$target_id]"
            unset "shot_y[$target_id]"
            unset "shot_seen_after[$target_id]"
            unset "shot_seen_x[$target_id]"
            unset "shot_seen_y[$target_id]"
        fi
    done
}

echo "[$ZRDN_NAME] Начало сканирования..."
while true; do
    process_kp_commands
    declare -A present_now=()

    while read -r target_id tx ty; do
        [[ -n "$target_id" ]] || continue
        present_now[$target_id]=1
        last_seen[$target_id]=$(date +%s)

        if [[ "${shot_pending[$target_id]:-0}" -eq 1 ]]; then
            if [[ "$tx" != "${shot_x[$target_id]}" || "$ty" != "${shot_y[$target_id]}" ]]; then
                if [[ "${shot_seen_after[$target_id]:-0}" -eq 0 ]]; then
                    shot_seen_after[$target_id]=1
                    shot_seen_x[$target_id]="$tx"
                    shot_seen_y[$target_id]="$ty"
                elif [[ "$tx" != "${shot_seen_x[$target_id]}" || "$ty" != "${shot_seen_y[$target_id]}" ]]; then
                    log_to_file "$LOGS_DIR/${ZRDN_NAME,,}.log" "[$ZRDN_NAME] Промах по цели ID:$target_id"
                    send_to_kp "$ZRDN_NAME" "miss" "$target_id" "$tx" "$ty" "Промах"
                    shot_pending[$target_id]=0
                    shot_seen_after[$target_id]=0
                fi
            fi
            continue
        fi

        if [[ "$target_id" =~ b$ ]]; then
            ignore_target[$target_id]=1
            continue
        fi

        [[ "${ignore_target[$target_id]:-0}" -eq 1 ]] && continue

        if ! in_circle "$tx" "$ty" "$ZRDN_X" "$ZRDN_Y" "$ZRDN_RANGE"; then
            continue
        fi

        if [[ "${detected_sent[$target_id]:-0}" -eq 0 ]]; then
            log_to_file "$LOGS_DIR/${ZRDN_NAME,,}.log" "Обнаружена цель ID:$target_id в зоне ($tx, $ty)"
            send_to_kp "$ZRDN_NAME" "detected" "$target_id" "$tx" "$ty" "первая засечка в зоне ЗРДН"
            detected_sent[$target_id]=1
        fi

        if [[ -z "${first_x[$target_id]:-}" ]]; then
            first_x[$target_id]="$tx"
            first_y[$target_id]="$ty"
            continue
        fi

        speed_ms=$(calc_distance "${first_x[$target_id]}" "${first_y[$target_id]}" "$tx" "$ty")
        if (( speed_ms == 0 )); then
            continue
        fi
        unset "first_x[$target_id]"
        unset "first_y[$target_id]"

        log_to_file "$LOGS_DIR/${ZRDN_NAME,,}.log" \
            "2-я засечка ID:$target_id скорость:$speed_ms м/с"

        if (( AMMO <= 0 )); then
            log_to_file "$LOGS_DIR/${ZRDN_NAME,,}.log" "[$ZRDN_NAME] Нет ракет!"
            send_to_kp "$ZRDN_NAME" "no_ammo" "$target_id" "$tx" "$ty" "боекомплект израсходован"
            continue
        fi

        ((AMMO--))
        echo "$ZRDN_NAME" > "$DESTROY_DIR/$target_id" 2>/dev/null
        log_to_file "$LOGS_DIR/${ZRDN_NAME,,}.log" \
            "[$ZRDN_NAME] Выстрел по цели ID:$target_id. Осталось ракет: $AMMO"
        send_to_kp "$ZRDN_NAME" "shot" "$target_id" "$tx" "$ty" "выстрел, осталось $AMMO"

        shot_pending[$target_id]=1
        shot_x[$target_id]="$tx"
        shot_y[$target_id]="$ty"
        shot_seen_after[$target_id]=0
        shot_seen_x[$target_id]="$tx"
        shot_seen_y[$target_id]="$ty"

    done < <(list_latest_targets)

    for target_id in "${!shot_pending[@]}"; do
        [[ "${shot_pending[$target_id]}" -eq 1 ]] || continue
        if [[ -z "${present_now[$target_id]:-}" ]]; then
            log_to_file "$LOGS_DIR/${ZRDN_NAME,,}.log" "[$ZRDN_NAME] Цель ID:$target_id УНИЧТОЖЕНА"
            send_to_kp "$ZRDN_NAME" "hit" "$target_id" "0" "0" "цель уничтожена"
            shot_pending[$target_id]=0
            shot_seen_after[$target_id]=0
            ignore_target[$target_id]=1
        fi
    done

    now_ts=$(date +%s)
    if (( AMMO < AMMO_RESUPPLY_THRESHOLD && (now_ts - LAST_RESUPPLY_TIME) >= AMMO_RESUPPLY_INTERVAL )); then
        AMMO=$((AMMO + AMMO_RESUPPLY_AMOUNT))
        LAST_RESUPPLY_TIME=$now_ts
        log_to_file "$LOGS_DIR/${ZRDN_NAME,,}.log" "[$ZRDN_NAME] Автопополнение БК на $AMMO_RESUPPLY_AMOUNT. БК: $AMMO"
        send_to_kp "$ZRDN_NAME" "ammo_restored" "" "0" "0" "пополнено на $AMMO_RESUPPLY_AMOUNT, БК=$AMMO"
    fi

    cleanup_stale
    sleep "$SLEEP_TIME"
done

cleanup

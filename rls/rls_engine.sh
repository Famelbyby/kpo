#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_DIR/config.sh"
source "$PROJECT_DIR/lib.sh"

check_environment "$RLS_NAME"
acquire_lock "$RLS_NAME" || exit 1

cleanup() {
    echo "[$RLS_NAME] Завершение работы..."
    release_lock "$RLS_NAME"
    exit 0
}
trap cleanup SIGINT SIGTERM

declare -A first_x
declare -A first_y
declare -A detected_sent
declare -A closed
declare -A last_seen

echo "[$RLS_NAME] РЛС типа $RLS_TYPE запущена. Координаты: ($RLS_X, $RLS_Y)"
echo "[$RLS_NAME] Азимут: ${RLS_AZIMUTH}°, Угол обзора: ${RLS_ANGLE}°, Дальность: $((RLS_RANGE/1000)) км"
log_to_file "$LOGS_DIR/${RLS_NAME,,}.log" "[$RLS_NAME] Запуск. Тип: $RLS_TYPE, X=$RLS_X Y=$RLS_Y, Азимут=$RLS_AZIMUTH°, Угол=$RLS_ANGLE°"

process_kp_commands() {
    local cmd
    cmd=$(read_kp_command "$RLS_NAME" 2>/dev/null)
    [[ -z "$cmd" ]] && return

    IFS='|' read -r ts sender cmd_type payload <<< "$cmd"

    case "$cmd_type" in
        ping)
            send_to_kp "$RLS_NAME" "pong" "" "0" "0" "работоспособна"
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
            unset "closed[$target_id]"
        fi
    done
}

echo "[$RLS_NAME] Начало сканирования целей..."
while true; do
    while read -r target_id tx ty; do
        [[ -n "$target_id" ]] || continue
        last_seen[$target_id]=$(date +%s)

        [[ "${closed[$target_id]:-0}" -eq 1 ]] && continue

        if ! in_rls_sector "$tx" "$ty" "$RLS_X" "$RLS_Y" "$RLS_RANGE" "$RLS_AZIMUTH" "$RLS_ANGLE"; then
            continue
        fi

        if [[ "${detected_sent[$target_id]:-0}" -eq 0 ]]; then
            log_to_file "$LOGS_DIR/${RLS_NAME,,}.log" "Обнаружена цель ID:$target_id ($tx, $ty)"
            send_to_kp "$RLS_NAME" "detected" "$target_id" "$tx" "$ty" "первая засечка"
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

        target_type=$(classify_target "$speed_ms")
        if [[ "$target_type" == "Неизвестно" ]]; then
            continue
        fi

        log_to_file "$LOGS_DIR/${RLS_NAME,,}.log" \
            "2-я засечка ID:$target_id скорость:$speed_ms м/с тип:$target_type ($tx, $ty)"
        send_to_kp "$RLS_NAME" "detected" "$target_id" "$tx" "$ty" \
            "2-я засечка, скорость $speed_ms м/с, тип $target_type"

        if [[ "$target_type" == "Бал.блок" ]]; then
            bearing_to_spro=$(calc_bearing "$tx" "$ty" "$SPRO_CENTER_X" "$SPRO_CENTER_Y")
            bearing_of_target=$(calc_bearing "${first_x[$target_id]}" "${first_y[$target_id]}" "$tx" "$ty")
            diff=$(awk -v a="$bearing_of_target" -v b="$bearing_to_spro" '
            BEGIN { d = a - b; if (d < 0) d = -d; if (d > 180) d = 360 - d; printf "%.0f\n", d }')
            if (( diff <= 45 )); then
                log_to_file "$LOGS_DIR/${RLS_NAME,,}.log" \
                    "Цель ID:$target_id движется к СПРО (отклонение ${diff}°)"
                send_to_kp "$RLS_NAME" "direction_spro" "$target_id" "$tx" "$ty" \
                    "БР движется к СПРО, скорость $speed_ms м/с, отклонение ${diff}°"
            fi
        fi

        closed[$target_id]=1
    done < <(list_latest_targets)

    cleanup_stale
    process_kp_commands
    sleep "$SLEEP_TIME"
done

cleanup

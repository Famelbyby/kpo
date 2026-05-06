#!/bin/bash
# ВКО Simulation — Система ПРО (СПРО), Москва, радиус 1200 км
# Detects and destroys ballistic targets (warheads).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_DIR/config.sh"
source "$PROJECT_DIR/lib.sh"

NAME="$SPRO_NAME"
MY_X="$SPRO_X"; MY_Y="$SPRO_Y"; MY_RANGE="$SPRO_RANGE"

check_environment "$NAME"
acquire_lock "$NAME" || exit 1

cleanup() {
    echo "[$NAME] Завершение работы..."
    release_lock "$NAME"
    exit 0
}
trap cleanup SIGINT SIGTERM

AMMO=$SPRO_AMMO_INITIAL
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

echo "[$NAME] СПРО запущена. Координаты: ($MY_X, $MY_Y), Радиус: $((MY_RANGE/1000)) км"
echo "[$NAME] Боекомплект: $AMMO противоракет"
log_to_file "$LOGS_DIR/${NAME,,}.log" "[$NAME] Запуск. X=$MY_X Y=$MY_Y, Радиус=$MY_RANGE, БК=$AMMO"

# ─── KP commands ─────────────────────────────────────────────────────────
process_kp_commands() {
    local cmd
    cmd=$(read_kp_command "$NAME" 2>/dev/null)
    [[ -z "$cmd" ]] && return

    IFS='|' read -r ts sender cmd_type payload <<< "$cmd"

    case "$cmd_type" in
        ping)
            send_to_kp "$NAME" "pong" "" "0" "0" "работоспособна, БК=$AMMO"
            ;;
        resupply)
            AMMO=$((AMMO + payload))
            log_to_file "$LOGS_DIR/${NAME,,}.log" "[$NAME] Пополнение БК на $payload. Текущий БК: $AMMO"
            send_to_kp "$NAME" "ammo_restored" "" "0" "0" "пополнено по команде КП на $payload, БК=$AMMO"
            ;;
    esac
}

# ─── Cleanup stale state ─────────────────────────────────────────────────
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

# ─── Main loop ────────────────────────────────────────────────────────────
echo "[$NAME] Начало сканирования..."
while true; do
    declare -A present_now=()

    while read -r target_id tx ty; do
        [[ -n "$target_id" ]] || continue
        present_now[$target_id]=1
        last_seen[$target_id]=$(date +%s)

        # ── Shot pending tracking ──────────────────────────────────────
        if [[ "${shot_pending[$target_id]:-0}" -eq 1 ]]; then
            if [[ "$tx" != "${shot_x[$target_id]}" || "$ty" != "${shot_y[$target_id]}" ]]; then
                if [[ "${shot_seen_after[$target_id]:-0}" -eq 0 ]]; then
                    shot_seen_after[$target_id]=1
                    shot_seen_x[$target_id]="$tx"
                    shot_seen_y[$target_id]="$ty"
                elif [[ "$tx" != "${shot_seen_x[$target_id]}" || "$ty" != "${shot_seen_y[$target_id]}" ]]; then
                    log_to_file "$LOGS_DIR/${NAME,,}.log" "[$NAME] Промах по цели ID:$target_id"
                    send_to_kp "$NAME" "miss" "$target_id" "$tx" "$ty" "Промах"
                    shot_pending[$target_id]=0
                    shot_seen_after[$target_id]=0
                fi
            fi
            continue
        fi

        # ── Type check by ID suffix ────────────────────────────────────
        # SPRO engages only ballistic targets (ID suffix 'b')
        if [[ ! "$target_id" =~ b$ ]]; then
            ignore_target[$target_id]=1
            continue
        fi

        [[ "${ignore_target[$target_id]:-0}" -eq 1 ]] && continue

        # ── Zone check ─────────────────────────────────────────────────
        if ! in_circle "$tx" "$ty" "$MY_X" "$MY_Y" "$MY_RANGE"; then
            continue
        fi

        # ── First detection ────────────────────────────────────────────
        if [[ "${detected_sent[$target_id]:-0}" -eq 0 ]]; then
            log_to_file "$LOGS_DIR/${NAME,,}.log" "Обнаружена цель ID:$target_id в зоне СПРО ($tx, $ty)"
            send_to_kp "$NAME" "detected" "$target_id" "$tx" "$ty" "первая засечка в зоне СПРО"
            detected_sent[$target_id]=1
        fi

        # ── Store first sighting ───────────────────────────────────────
        if [[ -z "${first_x[$target_id]:-}" ]]; then
            first_x[$target_id]="$tx"
            first_y[$target_id]="$ty"
            continue
        fi

        # ── Compute speed (distance ≈ m/s since 1 cycle ≈ 1 sec) ──────
        speed_ms=$(calc_distance "${first_x[$target_id]}" "${first_y[$target_id]}" "$tx" "$ty")
        if (( speed_ms == 0 )); then
            continue
        fi
        unset "first_x[$target_id]"
        unset "first_y[$target_id]"

        log_to_file "$LOGS_DIR/${NAME,,}.log" \
            "2-я засечка ID:$target_id скорость:$speed_ms м/с"

        # ── Fire if we have ammo ───────────────────────────────────────
        if (( AMMO <= 0 )); then
            log_to_file "$LOGS_DIR/${NAME,,}.log" "[$NAME] Нет противоракет!"
            send_to_kp "$NAME" "no_ammo" "$target_id" "$tx" "$ty" "боекомплект израсходован"
            continue
        fi

        ((AMMO--))
        echo "$NAME" > "$DESTROY_DIR/$target_id" 2>/dev/null
        log_to_file "$LOGS_DIR/${NAME,,}.log" \
            "[$NAME] Выстрел по цели ID:$target_id. Осталось ракет: $AMMO"
        send_to_kp "$NAME" "shot" "$target_id" "$tx" "$ty" "выстрел, осталось $AMMO"

        shot_pending[$target_id]=1
        shot_x[$target_id]="$tx"
        shot_y[$target_id]="$ty"
        shot_seen_after[$target_id]=0
        shot_seen_x[$target_id]="$tx"
        shot_seen_y[$target_id]="$ty"

    done < <(list_latest_targets)

    # ── Check destroyed: targets that disappeared after shot ────────────
    for target_id in "${!shot_pending[@]}"; do
        [[ "${shot_pending[$target_id]}" -eq 1 ]] || continue
        if [[ -z "${present_now[$target_id]:-}" ]]; then
            log_to_file "$LOGS_DIR/${NAME,,}.log" "[$NAME] Цель ID:$target_id УНИЧТОЖЕНА"
            send_to_kp "$NAME" "hit" "$target_id" "0" "0" "цель уничтожена СПРО"
            shot_pending[$target_id]=0
            shot_seen_after[$target_id]=0
            ignore_target[$target_id]=1
        fi
    done

    # ── Ammo resupply ──────────────────────────────────────────────────
    now_ts=$(date +%s)
    if (( AMMO < AMMO_RESUPPLY_THRESHOLD && (now_ts - LAST_RESUPPLY_TIME) >= AMMO_RESUPPLY_INTERVAL )); then
        AMMO=$((AMMO + AMMO_RESUPPLY_AMOUNT))
        LAST_RESUPPLY_TIME=$now_ts
        log_to_file "$LOGS_DIR/${NAME,,}.log" "[$NAME] Автопополнение БК на $AMMO_RESUPPLY_AMOUNT. БК: $AMMO"
        send_to_kp "$NAME" "ammo_restored" "" "0" "0" "пополнено на $AMMO_RESUPPLY_AMOUNT, БК=$AMMO"
    fi

    cleanup_stale
    process_kp_commands
    sleep "$SLEEP_TIME"
done

cleanup

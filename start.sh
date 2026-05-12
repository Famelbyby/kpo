#!/usr/bin/env bash
(( BASH_VERSINFO[0] < 4 )) && { echo "[ОШИБКА] Требуется Bash >= 4"; exit 1; }

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$PROJECT_DIR/config.sh"

echo "========================================"
echo "  ВКО Simulation — Запуск системы"
echo "========================================"

OS="$(uname -s)"
if [[ "$OS" != "Linux" && "$OS" != "Darwin" ]]; then
    echo "[ОШИБКА] Недопустимая ОС: $OS. Требуется Linux."
    exit 1
fi
echo "[OK] ОС: $OS"
echo "[OK] Bash: $BASH_VERSION"

[[ "$(id -u)" -eq 0 ]] && { echo "[ОШИБКА] Запуск от root запрещён"; exit 1; }
echo "[OK] Пользователь: $(whoami)"

mkdir -p "$TARGET_DIR" "$DESTROY_DIR" "$TO_KP_DIR" "$FROM_KP_DIR" \
         "$LOGS_DIR" "$DB_DIR" "$TEMP_DIR" "$PIDS_DIR" 2>/dev/null
echo "[OK] Рабочие каталоги созданы"

rm -f "$PIDS_DIR"/*.pid 2>/dev/null
rm -f "$TO_KP_DIR"/* "$FROM_KP_DIR"/* 2>/dev/null

source "$PROJECT_DIR/lib.sh"
db_init
echo "[OK] База данных инициализирована: $DB_FILE"

for tool in openssl sqlite3 bc xxd; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "[ОШИБКА] Утилита '$tool' не найдена"
        exit 1
    }
done
echo "[OK] Все необходимые утилиты найдены"
echo ""
echo "--- Запуск Генератора целей ---"
if [[ -x "$PROJECT_DIR/GenTargets.sh" ]]; then
    "$BASH" "$PROJECT_DIR/GenTargets.sh" &
    GEN_PID=$!
    echo "$GEN_PID" > "$PIDS_DIR/GenTargets.pid"
    echo "[OK] GenTargets.sh запущен (PID: $GEN_PID)"
    sleep 1
else
    echo "[ПРЕДУПРЕЖДЕНИЕ] GenTargets.sh не найден или не исполняемый"
    echo "  Цели нужно генерировать вручную в $TARGET_DIR"
fi

echo ""
echo "--- Запуск Командного Пункта ---"
"$BASH" "$PROJECT_DIR/kp/kp.sh" &
KP_PID=$!
echo "[OK] КП ВКО запущен (PID: $KP_PID)"
sleep 1

echo ""
echo "--- Запуск подсистем ---"

"$BASH" "$PROJECT_DIR/rls/rls1.sh" &
RLS1_PID=$!
echo "[OK] RLS-1 (Днепр, Minsk) PID: $RLS1_PID"

"$BASH" "$PROJECT_DIR/rls/rls2.sh" &
RLS2_PID=$!
echo "[OK] RLS-2 (Воронеж-ДМ) PID: $RLS2_PID"

"$BASH" "$PROJECT_DIR/rls/rls3.sh" &
RLS3_PID=$!
echo "[OK] RLS-3 (Днепр, Omsk) PID: $RLS3_PID"
sleep 0.5

"$BASH" "$PROJECT_DIR/spro/spro.sh" &
SPRO_PID=$!
echo "[OK] СПРО (Habarovsk, r=1200 км) PID: $SPRO_PID"
sleep 0.5

"$BASH" "$PROJECT_DIR/zrdn/zrdn1.sh" &
ZRDN1_PID=$!
echo "[OK] ЗРДН-1 (Krasnodar, r=600 км) PID: $ZRDN1_PID"

"$BASH" "$PROJECT_DIR/zrdn/zrdn2.sh" &
ZRDN2_PID=$!
echo "[OK] ЗРДН-2 (Odessa, r=400 км) PID: $ZRDN2_PID"

"$BASH" "$PROJECT_DIR/zrdn/zrdn3.sh" &
ZRDN3_PID=$!
echo "[OK] ЗРДН-3 (Orenburg, r=550 км) PID: $ZRDN3_PID"
sleep 1

echo ""
echo "--- Проверка запущенных процессов ---"
ALL_OK=true

declare -A COMP_PIDS
COMP_PIDS=(
    ["GenTargets"]="$GEN_PID"
    ["KP"]="$KP_PID"
    ["RLS1"]="$RLS1_PID"
    ["RLS2"]="$RLS2_PID"
    ["RLS3"]="$RLS3_PID"
    ["SPRO"]="$SPRO_PID"
    ["ZRDN1"]="$ZRDN1_PID"
    ["ZRDN2"]="$ZRDN2_PID"
    ["ZRDN3"]="$ZRDN3_PID"
)

for comp in "${!COMP_PIDS[@]}"; do
    pid="${COMP_PIDS[$comp]}"
    if kill -0 "$pid" 2>/dev/null; then
        echo "[OK] $comp (PID: $pid)"
    else
        echo "[ПРЕДУПРЕЖДЕНИЕ] $comp не запустился (PID $pid не отвечает)"
        ALL_OK=false
    fi
done

echo ""
echo "========================================"
if $ALL_OK; then
    echo "  Система ВКО запущена успешно"
else
    echo "  Система запущена (есть предупреждения)"
fi
echo "  Журнал: $LOGS_DIR/kp.log"
echo "  БД:     $DB_FILE"
echo "========================================"
echo ""
echo "Для остановки: ./stop.sh"
echo "Для просмотра логов: tail -f $LOGS_DIR/kp.log"
echo "Для статистики: sqlite3 $DB_FILE <запрос>"
echo ""
echo "Нажмите Ctrl+C для остановки всех подсистем..."
trap 'echo ""; echo "Получен сигнал остановки..."; "$PROJECT_DIR/stop.sh" silent' SIGINT SIGTERM
wait

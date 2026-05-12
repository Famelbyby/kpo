#!/bin/bash
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIDS_DIR="$PROJECT_DIR/temp/pids"

SILENT=false
[[ "$1" == "silent" ]] && SILENT=true

$SILENT || echo "========================================"
$SILENT || echo "  ВКО Simulation — Остановка системы"
$SILENT || echo "========================================"

STOPPED=0
FAILED=0

for pidfile in "$PIDS_DIR"/*.pid; do
    [[ -f "$pidfile" ]] || continue
    pid=$(cat "$pidfile" 2>/dev/null)
    name=$(basename "$pidfile" .pid)
    [[ -z "$pid" ]] && { rm -f "$pidfile"; continue; }

    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null
        sleep 0.2
        if kill -0 "$pid" 2>/dev/null; then
            kill -9 "$pid" 2>/dev/null
            sleep 0.1
        fi
        if kill -0 "$pid" 2>/dev/null; then
            $SILENT || echo "[ОШИБКА] $name (PID $pid) не удалось остановить"
            ((FAILED++))
        else
            $SILENT || echo "[OK] $name остановлен (PID $pid)"
            ((STOPPED++))
        fi
    else
        $SILENT || echo "[ПРОПУСК] $name (PID $pid не существует)"
    fi
    rm -f "$pidfile"
done

rm -f "$PIDS_DIR"/*.pid 2>/dev/null

$SILENT || echo ""
$SILENT || echo "========================================"
$SILENT || echo "  Остановлено: $STOPPED | Ошибок: $FAILED"
$SILENT || echo "========================================"

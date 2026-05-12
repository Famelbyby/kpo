#!/bin/bash
check_environment() {
    local subsystem_name="$1"

    (( BASH_VERSINFO[0] < 4 )) && {
        echo "[ERROR] $subsystem_name: Требуется Bash >= 4, текущий: $BASH_VERSION" >&2
        exit 1
    }
    
    local os
    os="$(uname -s)"
    if [[ "$os" != "Linux" && "$os" != "Darwin" ]]; then
        echo "[ERROR] $subsystem_name: Недопустимая ОС: $os. Требуется Linux." >&2
        exit 1
    fi

    if [[ "$(id -u)" -eq 0 ]]; then
        echo "[ERROR] $subsystem_name: Запуск от root запрещён." >&2
        exit 1
    fi
}

acquire_lock() {
    local name="$1"
    local pidfile="$PIDS_DIR/${name}.pid"

    if [[ -f "$pidfile" ]]; then
        local old_pid
        old_pid="$(cat "$pidfile" 2>/dev/null)"
        if kill -0 "$old_pid" 2>/dev/null; then
            echo "[ERROR] $name: Экземпляр уже запущен (PID $old_pid)" >&2
            return 1
        fi
        # Stale PID file — remove it
        rm -f "$pidfile"
    fi

    echo $$ > "$pidfile"
    return 0
}

release_lock() {
    local name="$1"
    rm -f "$PIDS_DIR/${name}.pid"
}

timestamp() {
    # Cross-platform timestamp with milliseconds
    perl -MTime::HiRes=gettimeofday -e '
        ($s, $us) = gettimeofday();
        @t = localtime($s);
        printf "%02d.%02d %02d:%02d:%02d:%03d",
            $t[4]+1, $t[3], $t[2], $t[1], $t[0], $us/1000;
    ' 2>/dev/null || date '+%d.%m %H:%M:%S.000'
}

epoch_ms() {
    perl -MTime::HiRes=time -e 'printf "%.0f\n", time() * 1000' 2>/dev/null || date +%s000
}

extract_id_from_filename() {
    local filename="$1"
    local hex_id=""
    local i
    for ((i = 2; i < 28; i += 4)); do
        hex_id+="${filename:$i:2}"
    done
    # Convert hex to ASCII (7-char target ID, last char = type: b/s/r)
    echo -n "$hex_id" | xxd -r -p 2>/dev/null
}

read_target_coords() {
    local filepath="$1"
    awk '{ gsub(/[^0-9-]/, "", $2); gsub(/[^0-9-]/, "", $4); print $2, $4 }' "$filepath" 2>/dev/null
}

list_latest_targets() {
    local id m file x y
    declare -A best_file
    declare -A best_mtime

    for file in "$TARGET_DIR"/*; do
        [[ -f "$file" ]] || continue
        id=$(extract_id_from_filename "$(basename "$file")")
        [[ -z "$id" || ${#id} -ne 7 ]] && continue

        m=$(perl -e 'print((stat(shift))[9])' "$file" 2>/dev/null || echo 0)
        [[ "$m" == "0" ]] && continue

        if [[ -z "${best_mtime[$id]:-}" || "$m" -gt "${best_mtime[$id]}" ]]; then
            best_mtime[$id]="$m"
            best_file[$id]="$file"
        fi
    done

    for id in "${!best_file[@]}"; do
        local coords
        coords=$(read_target_coords "${best_file[$id]}")
        [[ -z "$coords" ]] && continue
        read -r x y <<< "$coords"
        [[ -z "$x" || -z "$y" ]] && continue
        printf '%s %s %s\n' "$id" "$x" "$y"
    done
}

calc_distance() {
    x1=$1
    y1=$2
    x2=$3
    y2=$4

    dx=$((x2 - x1))
    dy=$((y2 - y1))

    dx_squared=$((dx * dx))
    dy_squared=$((dy * dy))

    sum_of_squares=$((dx_squared + dy_squared))
    distance=$(echo "scale=0; sqrt($sum_of_squares)" | bc -l)

    printf "%.0f\n" "$distance"
}


calc_bearing() {
    awk -v x1="$1" -v y1="$2" -v x2="$3" -v y2="$4" '
    BEGIN {
        dx = x2 - x1; dy = y2 - y1
        if (dx == 0 && dy == 0) { print 0; exit }
        pi = 3.141592653589793
        bearing = atan2(dx, dy) * 180.0 / pi
        if (bearing < 0) bearing += 360.0
        printf "%.2f\n", bearing
    }'
}

in_circle() {
    local tx="$1" ty="$2" cx="$3" cy="$4" radius="$5"
    local dist
    dist=$(calc_distance "$tx" "$ty" "$cx" "$cy")
    (( dist <= radius ))
}

in_rls_sector() {
    local tx="$1" ty="$2"
    local rx="$3" ry="$4"
    local rng="$5"
    local azimuth="$6"
    local angle="$7"

    local dist
    dist=$(calc_distance "$tx" "$ty" "$rx" "$ry")
    if (( dist > rng )); then
        return 1
    fi

    local bearing half_angle left right
    bearing=$(calc_bearing "$rx" "$ry" "$tx" "$ty")

    awk -v b="$bearing" -v az="$azimuth" -v ang="$angle" '
    BEGIN {
        half = ang / 2.0
        left = az - half
        right = az + half

        # Normalize left to [0, 360)
        while (left < 0) left += 360
        while (left >= 360) left -= 360

        # Normalize right to [0, 360)
        while (right < 0) right += 360
        while (right >= 360) right -= 360

        in_range = 0
        if (left <= right) {
            if (b >= left && b <= right) in_range = 1
        } else {
            # Wraps around 0
            if (b >= left || b <= right) in_range = 1
        }
        exit(in_range ? 0 : 1)
    }'
}

classify_target() {
    local speed="$1"
    if (( speed >= BALLISTIC_MIN_SPEED && speed <= BALLISTIC_MAX_SPEED )); then
        echo "Бал.блок"
    elif (( speed >= CRUISE_MIN_SPEED && speed <= CRUISE_MAX_SPEED )); then
        echo "К.ракета"
    elif (( speed >= AIRCRAFT_MIN_SPEED && speed <= AIRCRAFT_MAX_SPEED )); then
        echo "Самолет"
    else
        echo "Неизвестно"
    fi
}

classify_target_code() {
    local speed="$1"
    if (( speed >= BALLISTIC_MIN_SPEED && speed <= BALLISTIC_MAX_SPEED )); then
        echo "b"
    elif (( speed >= CRUISE_MIN_SPEED && speed <= CRUISE_MAX_SPEED )); then
        echo "r"
    elif (( speed >= AIRCRAFT_MIN_SPEED && speed <= AIRCRAFT_MAX_SPEED )); then
        echo "s"
    else
        echo "u"
    fi
}

encrypt_message() {
    local plaintext="$1"
    local checksum
    checksum=$(echo -n "$plaintext" | shasum -a 256 2>/dev/null | awk '{print $1}' ||
               echo -n "$plaintext" | sha256sum 2>/dev/null | awk '{print $1}')
    local msg="${plaintext}|${checksum}"
    echo -n "$msg" | openssl enc -"$ENCRYPTION_ALG" -pbkdf2 -pass "pass:$ENCRYPTION_KEY" -base64 -A 2>/dev/null | tr -d '\n'
}

decrypt_message() {
    local ciphertext="$1"
    local msg checksum computed_checksum plaintext

    msg=$(echo -n "$ciphertext" | openssl enc -"$ENCRYPTION_ALG" -pbkdf2 -pass "pass:$ENCRYPTION_KEY" -base64 -A -d 2>/dev/null)
    if [[ -z "$msg" ]]; then
        echo "[SECURITY] Ошибка расшифровки сообщения" >&2
        return 1
    fi

    plaintext="${msg%|*}"
    checksum="${msg##*|}"

    computed_checksum=$(echo -n "$plaintext" | shasum -a 256 2>/dev/null | awk '{print $1}' ||
                        echo -n "$plaintext" | sha256sum 2>/dev/null | awk '{print $1}')

    if [[ "$checksum" != "$computed_checksum" ]]; then
        echo "[SECURITY] Нарушение целостности сообщения! Ожидался: $checksum, получен: $computed_checksum" >&2
        return 1
    fi

    echo "$plaintext"
    return 0
}

send_to_kp() {
    local sender="$1" msg_type="$2" target_id="$3" x="$4" y="$5" extra="$6"
    local ts plaintext encrypted filename

    ts="$(timestamp)"
    plaintext="${ts}|${sender}|${msg_type}|${target_id}|${x}|${y}|${extra}"
    encrypted=$(encrypt_message "$plaintext")

    if [[ -z "$encrypted" ]]; then
        echo "[ERROR] $sender: Ошибка шифрования сообщения" >&2
        return 1
    fi

    filename="${TO_KP_DIR}/msg_$(epoch_ms)_$(printf '%04d' $((RANDOM % 10000)))"
    echo "$encrypted" > "$filename"
    return 0
}

read_kp_command() {
    local subsystem="$1"
    local cmd_file pattern file content plaintext

    pattern="${FROM_KP_DIR}/${subsystem}_*"
    for file in $pattern; do
        [[ -f "$file" ]] || continue
        content=$(cat "$file" 2>/dev/null)
        rm -f "$file" 2>/dev/null

        plaintext=$(decrypt_message "$content" 2>/dev/null)
        if [[ -n "$plaintext" ]]; then
            echo "$plaintext"
            return 0
        fi
    done
    return 1
}

send_kp_command() {
    local subsystem="$1" cmd_type="$2" payload="$3"
    local ts plaintext encrypted filename

    ts="$(timestamp)"
    plaintext="${ts}|KP|${cmd_type}|${payload}"
    encrypted=$(encrypt_message "$plaintext")

    if [[ -z "$encrypted" ]]; then
        echo "[ERROR] KP: Ошибка шифрования команды для $subsystem" >&2
        return 1
    fi

    filename="${FROM_KP_DIR}/${subsystem}_$(epoch_ms)_$(printf '%04d' $((RANDOM % 10000)))"
    echo "$encrypted" > "$filename"
    return 0
}

log_to_file() {
    local logfile="$1" message="$2"

    if [[ -f "$logfile" ]]; then
        local lines
        lines=$(wc -l < "$logfile" 2>/dev/null || echo 0)
        if (( lines >= MAX_LOG_LINES )); then
            local i
            for ((i = MAX_LOG_ROTATIONS; i >= 1; i--)); do
                [[ -f "${logfile}.${i}" ]] && mv "${logfile}.${i}" "${logfile}.$((i + 1))" 2>/dev/null
            done
            mv "$logfile" "${logfile}.1" 2>/dev/null
            echo "$(timestamp) [ROTATE] Лог ротирован, предыдущий: ${logfile}.1" > "$logfile"
        fi
    fi

    echo "$(timestamp) $message" >> "$logfile"
}

db_init() {
    sqlite3 "$DB_FILE" <<'SQL'
CREATE TABLE IF NOT EXISTS journal (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ts TEXT NOT NULL,
    subsystem TEXT NOT NULL,
    msg_type TEXT NOT NULL,
    target_id TEXT,
    x INTEGER,
    y INTEGER,
    info TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS health_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ts TEXT NOT NULL,
    subsystem TEXT NOT NULL,
    status TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS destruction_stats (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ts TEXT NOT NULL,
    subsystem TEXT NOT NULL,
    target_id TEXT,
    target_type TEXT,
    result TEXT NOT NULL,
    x INTEGER,
    y INTEGER
);
SQL
}

db_log_event() {
    local ts="$1" subsystem="$2" msg_type="$3" target_id="${4:-NULL}" x="${5:-0}" y="${6:-0}" info="${7:-}"
    sqlite3 "$DB_FILE" "INSERT INTO journal (ts, subsystem, msg_type, target_id, x, y, info) VALUES ('$ts', '$subsystem', '$msg_type', '$target_id', $x, $y, '$info');" 2>/dev/null
}

db_log_health() {
    local ts="$1" subsystem="$2" status="$3"
    sqlite3 "$DB_FILE" "INSERT INTO health_log (ts, subsystem, status) VALUES ('$ts', '$subsystem', '$status');" 2>/dev/null
}

db_log_destruction() {
    local ts="$1" subsystem="$2" target_id="$3" target_type="$4" result="$5" x="${6:-0}" y="${7:-0}"
    sqlite3 "$DB_FILE" "INSERT INTO destruction_stats (ts, subsystem, target_id, target_type, result, x, y) VALUES ('$ts', '$subsystem', '$target_id', '$target_type', '$result', $x, $y);" 2>/dev/null
}

db_stats_top_destroyers() {
    sqlite3 "$DB_FILE" <<'SQL'
SELECT subsystem, COUNT(*) as kills
FROM destruction_stats
WHERE result = 'hit'
GROUP BY subsystem
ORDER BY kills DESC;
SQL
}

db_stats_accuracy() {
    sqlite3 "$DB_FILE" <<'SQL'
SELECT
    subsystem,
    SUM(CASE WHEN result='hit' THEN 1 ELSE 0 END) as hits,
    SUM(CASE WHEN result='miss' THEN 1 ELSE 0 END) as misses,
    ROUND(100.0 * SUM(CASE WHEN result='hit' THEN 1 ELSE 0 END) /
          NULLIF(SUM(CASE WHEN result IN ('hit','miss') THEN 1 ELSE 0 END), 0), 1) as accuracy_pct
FROM destruction_stats
GROUP BY subsystem
ORDER BY accuracy_pct DESC;
SQL
}

db_stats_targets_by_type() {
    sqlite3 "$DB_FILE" <<'SQL'
SELECT
    CASE
        WHEN target_type LIKE '%блок%' OR target_type LIKE '%ББ%' THEN 'Бал.блоки'
        WHEN target_type LIKE '%ракет%' OR target_type LIKE '%К.%' THEN 'К.ракеты'
        WHEN target_type LIKE '%Самолет%' OR target_type LIKE '%самолет%' THEN 'Самолеты'
        ELSE 'Прочее'
    END as type,
    COUNT(*) as count
FROM destruction_stats
GROUP BY type
ORDER BY count DESC;
SQL
}

db_stats_full_journal() {
    sqlite3 "$DB_FILE" "SELECT ts, subsystem, msg_type, target_id, x, y, info FROM journal ORDER BY ts DESC LIMIT 50;"
}

db_stats_recent_activity() {
    sqlite3 "$DB_FILE" <<'SQL'
SELECT subsystem, msg_type, COUNT(*) as cnt
FROM journal
GROUP BY subsystem, msg_type
ORDER BY subsystem, cnt DESC;
SQL
}

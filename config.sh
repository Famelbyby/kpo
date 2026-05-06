#!/bin/bash
# ВКО Simulation — Shared Configuration
# Variant: RLS1-Novosibirsk, RLS2-Donetsk, RLS3-(12000,5000),
#          SPRO-Moscow, ZRDN1-Tomsk, ZRDN2-Yakutsk, ZRDN3-(11000,5000)

# Check Bash version
(( BASH_VERSINFO[0] < 4 )) && { echo "Требуется Bash >= 4"; exit 1; }

# Project root (absolute path of this script's directory)
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Directory structure
TARGET_DIR="/tmp/GenTargets/Targets"
DESTROY_DIR="/tmp/GenTargets/Destroy"
MESSAGES_DIR="$PROJECT_DIR/messages"
TO_KP_DIR="$MESSAGES_DIR/to_kp"
FROM_KP_DIR="$MESSAGES_DIR/from_kp"
LOGS_DIR="$PROJECT_DIR/logs"
DB_DIR="$PROJECT_DIR/db"
TEMP_DIR="$PROJECT_DIR/temp"
PIDS_DIR="$TEMP_DIR/pids"
DB_FILE="$DB_DIR/vko.db"

# Ensure directories exist
mkdir -p "$TARGET_DIR" "$DESTROY_DIR" "$TO_KP_DIR" "$FROM_KP_DIR" \
         "$LOGS_DIR" "$DB_DIR" "$TEMP_DIR" "$PIDS_DIR" 2>/dev/null

# Encryption parameters
ENCRYPTION_KEY="VKO_SECRET_KEY_2024"
ENCRYPTION_ALG="aes-256-cbc"

# Timing
CHECK_INTERVAL=0.5          # seconds between scans
SLEEP_TIME=0.5              # actual sleep in main loop

# Ammo
SPRO_AMMO_INITIAL=10
ZRDN_AMMO_INITIAL=20
AMMO_RESUPPLY_AMOUNT=5
AMMO_RESUPPLY_THRESHOLD=3
AMMO_RESUPPLY_INTERVAL=30   # seconds

# Log rotation
MAX_LOG_LINES=5000
MAX_LOG_ROTATIONS=2

# Health checks
HEALTH_CHECK_INTERVAL=10    # seconds
PING_TIMEOUT=5              # seconds

# Target speed ranges (m/s)
BALLISTIC_MIN_SPEED=8000
BALLISTIC_MAX_SPEED=10000
AIRCRAFT_MIN_SPEED=50
AIRCRAFT_MAX_SPEED=249
CRUISE_MIN_SPEED=250
CRUISE_MAX_SPEED=1000

# Target type suffix in ID (last char)
# b = ballistic (ББ БР), s = aircraft (Самолет), r = cruise missile (К.ракета)

# ─── My Variant: Component Parameters ─────────────────────────────────────

# RLS-1: Voronezh-DM (5Н86), Novosibirsk — range 4000 km, angle 200°, azimuth 270°
RLS1_NAME="RLS1"
RLS1_X=6150000; RLS1_Y=3700000
RLS1_RANGE=4000000; RLS1_AZIMUTH=270; RLS1_ANGLE=200
RLS1_TYPE="Воронеж-ДМ"

# RLS-2: Dnepr (5Н79), Donetsk — range 3500 km, angle 120°, azimuth 180°
RLS2_NAME="RLS2"
RLS2_X=3200000; RLS2_Y=3000000
RLS2_RANGE=3500000; RLS2_AZIMUTH=180; RLS2_ANGLE=120
RLS2_TYPE="Днепр"

# RLS-3: Daryal (5Н86), x=12000 y=5000 — range 6000 km, angle 90°, azimuth 135°
RLS3_NAME="RLS3"
RLS3_X=12000000; RLS3_Y=5000000
RLS3_RANGE=6000000; RLS3_AZIMUTH=135; RLS3_ANGLE=90
RLS3_TYPE="Дарьял"

# SPRO: Moscow — radius 1200 km
SPRO_NAME="SPRO"
SPRO_X=3200000; SPRO_Y=3800000
SPRO_RANGE=1200000

# ZRDN-1: Tomsk — radius 350 km
ZRDN1_NAME="ZRDN1"
ZRDN1_X=6250000; ZRDN1_Y=3850000
ZRDN1_RANGE=350000

# ZRDN-2: Yakutsk — radius 500 km
ZRDN2_NAME="ZRDN2"
ZRDN2_X=9200000; ZRDN2_Y=4650000
ZRDN2_RANGE=500000

# ZRDN-3: x=11000 y=5000 — radius 600 km
ZRDN3_NAME="ZRDN3"
ZRDN3_X=11000000; ZRDN3_Y=5000000
ZRDN3_RANGE=600000

# SPRO center for RLS direction checks (Moscow)
SPRO_CENTER_X=3200000; SPRO_CENTER_Y=3800000

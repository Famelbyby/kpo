#!/bin/bash
# ВКО Simulation — ZRDN-3: x=11000 y=5000, r=600 км
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_DIR/config.sh"
ZRDN_NAME="$ZRDN3_NAME"; ZRDN_X="$ZRDN3_X"; ZRDN_Y="$ZRDN3_Y"
ZRDN_RANGE="$ZRDN3_RANGE"
source "$SCRIPT_DIR/zrdn_engine.sh"

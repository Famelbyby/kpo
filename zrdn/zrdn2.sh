#!/bin/bash
# ВКО Simulation — ZRDN-2: Якутск, r=500 км
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_DIR/config.sh"
ZRDN_NAME="$ZRDN2_NAME"; ZRDN_X="$ZRDN2_X"; ZRDN_Y="$ZRDN2_Y"
ZRDN_RANGE="$ZRDN2_RANGE"
source "$SCRIPT_DIR/zrdn_engine.sh"

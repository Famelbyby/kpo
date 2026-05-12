#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_DIR/config.sh"
ZRDN_NAME="$ZRDN1_NAME"; ZRDN_X="$ZRDN1_X"; ZRDN_Y="$ZRDN1_Y"
ZRDN_RANGE="$ZRDN1_RANGE"
source "$SCRIPT_DIR/zrdn_engine.sh"

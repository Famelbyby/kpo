#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_DIR/config.sh"
RLS_NAME="$RLS3_NAME"; RLS_X="$RLS3_X"; RLS_Y="$RLS3_Y"
RLS_RANGE="$RLS3_RANGE"; RLS_AZIMUTH="$RLS3_AZIMUTH"; RLS_ANGLE="$RLS3_ANGLE"
RLS_TYPE="$RLS3_TYPE"
source "$SCRIPT_DIR/rls_engine.sh"

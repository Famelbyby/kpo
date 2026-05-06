#!/bin/bash
# ВКО Simulation — RLS-2: Днепр, Донецк
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_DIR/config.sh"
RLS_NAME="$RLS2_NAME"; RLS_X="$RLS2_X"; RLS_Y="$RLS2_Y"
RLS_RANGE="$RLS2_RANGE"; RLS_AZIMUTH="$RLS2_AZIMUTH"; RLS_ANGLE="$RLS2_ANGLE"
RLS_TYPE="$RLS2_TYPE"
source "$SCRIPT_DIR/rls_engine.sh"

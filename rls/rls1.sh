#!/bin/bash
# ВКО Simulation — RLS-1: Воронеж-ДМ, Новосибирск
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_DIR/config.sh"
RLS_NAME="$RLS1_NAME"; RLS_X="$RLS1_X"; RLS_Y="$RLS1_Y"
RLS_RANGE="$RLS1_RANGE"; RLS_AZIMUTH="$RLS1_AZIMUTH"; RLS_ANGLE="$RLS1_ANGLE"
RLS_TYPE="$RLS1_TYPE"
source "$SCRIPT_DIR/rls_engine.sh"

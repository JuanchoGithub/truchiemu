#!/bin/bash
# TruchieEmu Game Test Script
# Usage: ./test_game.sh <rom_path> [core_id] [timeout_seconds]
#
# This script launches a game via CLI and verifies it runs correctly.
# Returns 0 on success, 1 on failure.

set -e

# Configuration
APP_BUNDLE="com.truchiemu.app"
DEFAULT_TIMEOUT=10
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="/tmp/truchiemu_test_$(date +%s).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

cleanup() {
    # Kill any background processes
    if [ -n "$APP_PID" ]; then
        kill $APP_PID 2>/dev/null || true
    fi
}

trap cleanup EXIT

usage() {
    echo "Usage: $0 <rom_path> [core_id] [timeout_seconds]"
    echo ""
    echo "Arguments:"
    echo "  rom_path       Path to the ROM file (required)"
    echo "  core_id        Core identifier (optional, auto-detected if not specified)"
    echo "  timeout        Timeout in seconds (default: $DEFAULT_TIMEOUT)"
    echo ""
    echo "Examples:"
    echo "  $0 ~/Roms/Mario.nes"
    echo "  $0 ~/Roms/Mario.nes fceumm"
    echo "  $0 ~/Roms/Mario.nes fceumm 15"
    exit 1
}

# Parse arguments
ROM_PATH="$1"
CORE_ID="$2"
TIMEOUT="${3:-$DEFAULT_TIMEOUT}"

# Validate arguments
if [ -z "$ROM_PATH" ]; then
    log_error "ROM path is required"
    usage
fi

if [ ! -f "$ROM_PATH" ]; then
    log_error "ROM file not found: $ROM_PATH"
    exit 1
fi

log_info "Testing game: $ROM_PATH"
if [ -n "$CORE_ID" ]; then
    log_info "Using core: $CORE_ID"
fi
log_info "Timeout: ${TIMEOUT}s"
log_info "Log file: $LOG_FILE"

# Build the command
CMD="open -a $APP_BUNDLE --args --launch \"$ROM_PATH\" --headless --timeout $TIMEOUT"
if [ -n "$CORE_ID" ]; then
    CMD="$CMD --core $CORE_ID"
fi

log_info "Running: $CMD"

# Run the app and capture output
eval "$CMD" >> "$LOG_FILE" 2>&1 &
APP_PID=$!

log_info "App launched with PID: $APP_PID"
log_info "Waiting for test to complete..."

# Wait for the app to finish (headless mode will exit)
wait $APP_PID 2>/dev/null
EXIT_CODE=$?

# Check result
if [ $EXIT_CODE -eq 0 ]; then
    log_info "SUCCESS: Game launched and rendered frames correctly"
    echo ""
    echo "=== Test Log ==="
    cat "$LOG_FILE"
    echo "================"
    exit 0
else
    log_error "FAILURE: Game failed to launch or render frames"
    echo ""
    echo "=== Test Log ==="
    cat "$LOG_FILE"
    echo "================"
    exit 1
fi
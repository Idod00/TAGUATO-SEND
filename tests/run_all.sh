#!/bin/bash
# ============================================
# TAGUATO-SEND — Full test suite runner
# ============================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load shared helpers
# shellcheck source=helpers/common.sh
source "$SCRIPT_DIR/helpers/common.sh"

# Resolve admin token
ADMIN_TOKEN="${ADMIN_TOKEN:-$(grep '^ADMIN_TOKEN=' .env 2>/dev/null | cut -d= -f2)}"
if [ -z "$ADMIN_TOKEN" ]; then
    echo "ERROR: ADMIN_TOKEN not set. Export it or add ADMIN_TOKEN=<token> to .env"
    exit 1
fi
export ADMIN_TOKEN

echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN} TAGUATO-SEND — Full Test Suite${NC}"
echo -e "${CYAN}============================================${NC}"

# Setup test data
# shellcheck source=helpers/setup.sh
source "$SCRIPT_DIR/helpers/setup.sh"

# Register teardown on exit
cleanup() {
    # shellcheck source=helpers/teardown.sh
    source "$SCRIPT_DIR/helpers/teardown.sh"
}
trap cleanup EXIT

# Run all test files in order
for test_file in "$SCRIPT_DIR"/[0-9][0-9]_*.sh; do
    if [ -f "$test_file" ]; then
        # shellcheck source=/dev/null
        source "$test_file"
    fi
done

# Print final results
print_results
exit "$FAIL"

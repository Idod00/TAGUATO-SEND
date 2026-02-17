#!/bin/bash
# Legacy wrapper — delegates to the full test suite
exec "$(dirname "$0")/tests/run_all.sh" "$@"

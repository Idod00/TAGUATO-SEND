#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

SERVICE="${1:-}"

if [ -n "$SERVICE" ]; then
    echo "Showing logs for: $SERVICE"
    docker compose logs -f "$SERVICE"
else
    echo "Showing logs for all services (Ctrl+C to exit)"
    docker compose logs -f
fi

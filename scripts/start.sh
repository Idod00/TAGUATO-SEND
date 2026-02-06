#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "Starting TAGUATO-SEND services..."
docker compose up -d

echo ""
echo "Services started. Waiting for health checks..."
sleep 5
docker compose ps

echo ""
echo "API:     http://localhost:${API_PORT:-8080}"
echo "Manager: http://localhost:${MANAGER_PORT:-3000}"
echo "Docs:    http://localhost:${API_PORT:-8080}/docs"

#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Load env vars
if [ -f .env ]; then
    set -a
    source .env
    set +a
fi

BACKUP_DIR="./backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/taguato_backup_${TIMESTAMP}.sql.gz"

mkdir -p "$BACKUP_DIR"

echo "Backing up TAGUATO-SEND database..."
docker compose exec -T taguato-postgres pg_dump \
    -U "${POSTGRES_USER:-taguato}" \
    -d "${POSTGRES_DB:-evolution}" \
    | gzip > "$BACKUP_FILE"

echo "Backup saved to: $BACKUP_FILE"
echo "Size: $(du -h "$BACKUP_FILE" | cut -f1)"

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
DAY_OF_WEEK=$(date +%u)
BACKUP_FILE="${BACKUP_DIR}/taguato_backup_${TIMESTAMP}.sql.gz"

mkdir -p "$BACKUP_DIR"

echo "Backing up TAGUATO-SEND database..."
docker compose exec -T taguato-postgres pg_dump \
    -U "${POSTGRES_USER:-taguato}" \
    -d "${POSTGRES_DB:-evolution}" \
    | gzip > "$BACKUP_FILE"

echo "Backup saved to: $BACKUP_FILE"
echo "Size: $(du -h "$BACKUP_FILE" | cut -f1)"

# Create weekly backup on Sundays
if [ "$DAY_OF_WEEK" -eq 7 ]; then
    WEEKLY_FILE="${BACKUP_DIR}/taguato_weekly_${TIMESTAMP}.sql.gz"
    cp "$BACKUP_FILE" "$WEEKLY_FILE"
    echo "Weekly backup: $WEEKLY_FILE"
fi

# Retention: keep 7 daily backups
echo "Cleaning old daily backups (keeping last 7)..."
ls -t "${BACKUP_DIR}"/taguato_backup_*.sql.gz 2>/dev/null | tail -n +8 | xargs -r rm -f

# Retention: keep 4 weekly backups
echo "Cleaning old weekly backups (keeping last 4)..."
ls -t "${BACKUP_DIR}"/taguato_weekly_*.sql.gz 2>/dev/null | tail -n +5 | xargs -r rm -f

echo "Backup complete."

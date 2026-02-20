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
PG_USER="${POSTGRES_USER:-taguato}"
PG_DB="${POSTGRES_DB:-evolution}"

# --- Functions ---

list_backups() {
    local files
    files=$(ls -1t "$BACKUP_DIR"/*.sql.gz 2>/dev/null || true)
    if [ -z "$files" ]; then
        echo "No backups found in $BACKUP_DIR"
        exit 1
    fi
    echo "$files"
}

verify_backup() {
    local file="$1"
    echo "Verifying backup integrity: $(basename "$file")..."
    if gunzip -t "$file" 2>/dev/null; then
        echo "  OK - Backup is valid"
        return 0
    else
        echo "  FAILED - Backup appears corrupted"
        return 1
    fi
}

# --- Main ---

echo "============================================"
echo " TAGUATO-SEND Database Restore"
echo "============================================"
echo ""

# Check that containers are running
if ! docker compose ps --status running | grep -q taguato-postgres; then
    echo "ERROR: taguato-postgres container is not running."
    echo "Start it with: docker compose up -d taguato-postgres"
    exit 1
fi

# List available backups
echo "Available backups:"
echo ""

mapfile -t BACKUPS < <(list_backups)

for i in "${!BACKUPS[@]}"; do
    file="${BACKUPS[$i]}"
    size=$(du -h "$file" | cut -f1)
    date_str=$(basename "$file" | grep -oP '\d{8}_\d{6}' || echo "unknown")
    printf "  [%d] %s (%s) - %s\n" "$((i+1))" "$(basename "$file")" "$size" "$date_str"
done

echo ""

# Allow passing backup number as argument or select interactively
if [ $# -ge 1 ]; then
    CHOICE="$1"
else
    read -rp "Select backup number [1-${#BACKUPS[@]}]: " CHOICE
fi

# Validate selection
if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt "${#BACKUPS[@]}" ]; then
    echo "ERROR: Invalid selection"
    exit 1
fi

SELECTED="${BACKUPS[$((CHOICE-1))]}"
echo ""
echo "Selected: $(basename "$SELECTED")"

# Verify integrity
if ! verify_backup "$SELECTED"; then
    echo "ERROR: Cannot restore a corrupted backup."
    exit 1
fi

# Preview contents
echo ""
echo "Preview (first 20 SQL statements):"
gunzip -c "$SELECTED" | head -20
echo "..."
echo ""

# Confirm
echo "WARNING: This will DROP and recreate the taguato schema."
echo "Database: $PG_DB | User: $PG_USER"
read -rp "Are you sure? Type 'yes' to confirm: " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Restore cancelled."
    exit 0
fi

# Create a safety backup before restoring
echo ""
echo "Creating safety backup before restore..."
SAFETY_FILE="${BACKUP_DIR}/taguato_pre_restore_$(date +%Y%m%d_%H%M%S).sql.gz"
docker compose exec -T taguato-postgres pg_dump \
    -U "$PG_USER" \
    -d "$PG_DB" \
    | gzip > "$SAFETY_FILE"
echo "Safety backup saved: $SAFETY_FILE ($(du -h "$SAFETY_FILE" | cut -f1))"

# Restore
echo ""
echo "Restoring database from $(basename "$SELECTED")..."

gunzip -c "$SELECTED" | docker compose exec -T taguato-postgres psql \
    -U "$PG_USER" \
    -d "$PG_DB" \
    --single-transaction \
    -q

echo ""
echo "Restore complete."
echo ""
echo "Recommended next steps:"
echo "  1. Restart the gateway: docker compose restart taguato-gateway"
echo "  2. Verify the panel works at http://localhost"
echo "  3. If something went wrong, restore the safety backup:"
echo "     ./scripts/restore-db.sh  (select the pre_restore file)"

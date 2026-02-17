#!/bin/bash
# Seed admin user after schema init.
# Called from PostgreSQL entrypoint (docker-entrypoint-initdb.d).
# Environment variables ADMIN_USERNAME and ADMIN_PASSWORD must be set.

set -e

ADMIN_USER="${ADMIN_USERNAME:-admin}"
ADMIN_PASS="${ADMIN_PASSWORD:-admin}"

# Generate token via PostgreSQL (no openssl dependency)
TOKEN=$(psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
    -t -A -c "SELECT encode(gen_random_bytes(32), 'hex')")

# Insert admin user — plain SQL so psql interpolates :'var' correctly
# (psql variables do NOT work inside DO $$ blocks)
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
     -v admin_user="$ADMIN_USER" \
     -v admin_pass="$ADMIN_PASS" \
     -v admin_token="$TOKEN" <<'EOSQL'
INSERT INTO taguato.users (username, password_hash, role, api_token, max_instances, is_active)
VALUES (
    :'admin_user',
    crypt(:'admin_pass', gen_salt('bf')),
    'admin',
    :'admin_token',
    -1,
    true
)
ON CONFLICT (username) DO NOTHING;
EOSQL

echo "============================================"
echo "TAGUATO-SEND Admin User Created"
echo "Username: $ADMIN_USER"
echo "API Token: $TOKEN"
echo "Save this token! It is your admin API key."
echo "============================================"

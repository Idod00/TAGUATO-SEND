#!/bin/bash
# Seed admin user after schema init.
# Called from PostgreSQL entrypoint (docker-entrypoint-initdb.d).
# Environment variables ADMIN_USERNAME and ADMIN_PASSWORD must be set.

set -e

ADMIN_USER="${ADMIN_USERNAME:-admin}"
ADMIN_PASS="${ADMIN_PASSWORD:-admin}"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    DO \$\$
    DECLARE
        v_token TEXT := encode(gen_random_bytes(32), 'hex');
    BEGIN
        INSERT INTO taguato.users (username, password_hash, role, api_token, max_instances, is_active)
        VALUES (
            '${ADMIN_USER}',
            crypt('${ADMIN_PASS}', gen_salt('bf')),
            'admin',
            v_token,
            -1,
            true
        )
        ON CONFLICT (username) DO NOTHING;

        RAISE NOTICE '============================================';
        RAISE NOTICE 'TAGUATO-SEND Admin User Created';
        RAISE NOTICE 'Username: ${ADMIN_USER}';
        RAISE NOTICE 'API Token: %', v_token;
        RAISE NOTICE 'Save this token! It is your admin API key.';
        RAISE NOTICE '============================================';
    END \$\$;
EOSQL

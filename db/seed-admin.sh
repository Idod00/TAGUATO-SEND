#!/bin/bash
# Seed admin user after schema init.
# Called from PostgreSQL entrypoint (docker-entrypoint-initdb.d).
# Environment variables ADMIN_USERNAME and ADMIN_PASSWORD must be set.

set -e

ADMIN_USER="${ADMIN_USERNAME:-admin}"
ADMIN_PASS="${ADMIN_PASSWORD:-admin}"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
     -v admin_user="$ADMIN_USER" -v admin_pass="$ADMIN_PASS" <<'EOSQL'
    DO $$
    DECLARE
        v_user TEXT := :'admin_user';
        v_pass TEXT := :'admin_pass';
        v_token TEXT := encode(gen_random_bytes(32), 'hex');
    BEGIN
        INSERT INTO taguato.users (username, password_hash, role, api_token, max_instances, is_active)
        VALUES (
            v_user,
            crypt(v_pass, gen_salt('bf')),
            'admin',
            v_token,
            -1,
            true
        )
        ON CONFLICT (username) DO NOTHING;

        RAISE NOTICE '============================================';
        RAISE NOTICE 'TAGUATO-SEND Admin User Created';
        RAISE NOTICE 'Username: %', v_user;
        RAISE NOTICE 'API Token: %', v_token;
        RAISE NOTICE 'Save this token! It is your admin API key.';
        RAISE NOTICE '============================================';
    END $$;
EOSQL

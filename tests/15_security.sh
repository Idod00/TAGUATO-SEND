#!/bin/bash
# ============================================
# 15. Security (SQL injection, headers, CORS, rate limiting)
# ============================================

print_section "15. SECURITY"

# --- SQL Injection in login ---
print_section "15a. SQL INJECTION"

STATUS=$(get_status "$BASE/api/auth/login" "POST" "" \
    '{"username":"'"'"' OR '"'"'1'"'"'='"'"'1","password":"CiTestPass1"}')
assert_status "SQL injection in username -> 401" "401" "$STATUS"

STATUS=$(get_status "$BASE/api/auth/login" "POST" "" \
    '{"username":"'"'"'; DROP TABLE taguato.users; --","password":"CiTestPass1"}')
assert_status "DROP TABLE injection -> 401" "401" "$STATUS"

# SQL injection in apikey header
STATUS=$(get_status "$BASE/instance/fetchInstances" "GET" "' OR '1'='1")
assert_status "SQL injection in apikey -> 401" "401" "$STATUS"

STATUS=$(get_status "$BASE/instance/fetchInstances" "GET" "'; DROP TABLE taguato.users; --")
assert_status "DROP TABLE in apikey -> 401" "401" "$STATUS"

# Verify users table is still intact
BODY=$(do_get "$BASE/admin/users" "$ADMIN_TOKEN")
assert_contains "Users table intact after injection attempts" "ci_user1" "$BODY"
assert_contains "Admin still exists" "admin" "$BODY"

# --- Security Headers ---
print_section "15b. SECURITY HEADERS"

HEADERS=$(get_headers "$BASE/health")
assert_header "X-Content-Type-Options: nosniff" "X-Content-Type-Options" "nosniff" "$HEADERS"
assert_header "X-Frame-Options: DENY" "X-Frame-Options" "DENY" "$HEADERS"
assert_header "X-XSS-Protection present" "X-XSS-Protection" "1; mode=block" "$HEADERS"
assert_header "Referrer-Policy present" "Referrer-Policy" "strict-origin-when-cross-origin" "$HEADERS"
assert_header "HSTS present" "Strict-Transport-Security" "" "$HEADERS"

# Headers on authenticated endpoint
HEADERS=$(get_headers "$BASE/api/templates" "$USER1_TOKEN")
assert_header "Security headers on auth endpoint - nosniff" "X-Content-Type-Options" "nosniff" "$HEADERS"
assert_header "Security headers on auth endpoint - frame" "X-Frame-Options" "DENY" "$HEADERS"

# --- CORS ---
print_section "15c. CORS"

HEADERS=$(get_headers "$BASE/health")
assert_header "CORS Allow-Origin present" "Access-Control-Allow-Origin" "" "$HEADERS"
assert_header "CORS Allow-Methods present" "Access-Control-Allow-Methods" "" "$HEADERS"
assert_header "CORS Allow-Headers includes apikey" "Access-Control-Allow-Headers" "" "$HEADERS"

# OPTIONS preflight
STATUS=$(get_status "$BASE/api/auth/login" "OPTIONS")
assert_status "OPTIONS preflight -> 204" "204" "$STATUS"

# --- Rate Limiting ---
print_section "15d. RATE LIMITING"

# ci_user2 has rate_limit=100, which is per-second window
# We test by sending rapid requests — with rate_limit=100, it's hard to exceed in tests
# Instead verify the mechanism works by checking a user with low limit
# Create a user with very low rate limit
BODY=$(do_post "$BASE/admin/users" \
    '{"username":"ci_rate_user","password":"CiTestPass1","rate_limit":2}' "$ADMIN_TOKEN")
RATE_TOKEN=$(json_val "$BODY" '.user.api_token')
RATE_UID=$(json_val "$BODY" '.user.id')

# Send rapid requests to exceed limit
do_get "$BASE/instance/fetchInstances" "$RATE_TOKEN" > /dev/null
do_get "$BASE/instance/fetchInstances" "$RATE_TOKEN" > /dev/null
do_get "$BASE/instance/fetchInstances" "$RATE_TOKEN" > /dev/null
STATUS=$(get_status "$BASE/instance/fetchInstances" "GET" "$RATE_TOKEN")
assert_status "Rate limited user gets 429" "429" "$STATUS"

# Cleanup rate limit user
do_delete "$BASE/admin/users/$RATE_UID" "$ADMIN_TOKEN" > /dev/null 2>&1

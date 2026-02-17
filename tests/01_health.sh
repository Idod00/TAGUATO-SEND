#!/bin/bash
# ============================================
# 01. Health check + public status
# ============================================

print_section "01. HEALTH CHECK & STATUS"

# --- /health ---
STATUS=$(get_status "$BASE/health")
assert_status "GET /health -> 200" "200" "$STATUS"

BODY=$(do_get "$BASE/health")
assert_contains "Response contains 'gateway'" "gateway" "$BODY"
assert_json_field "DB connected" ".db" "connected" "$BODY"
assert_json_field "Status ok" ".status" "ok" "$BODY"

# --- /api/status ---
STATUS=$(get_status "$BASE/api/status")
assert_status "GET /api/status -> 200" "200" "$STATUS"

BODY=$(do_get "$BASE/api/status")
assert_contains "Has overall_status" "overall_status" "$BODY"
assert_json_count "Has 4 services" ".services" 4 "$BODY"
assert_contains "Has uptime field" "uptime" "$BODY"

# --- X-Cache header ---
HEADERS=$(get_headers "$BASE/api/status")
assert_header "X-Cache header present on /api/status" "X-Cache" "" "$HEADERS"

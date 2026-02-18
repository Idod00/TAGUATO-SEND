#!/bin/bash
# ============================================
# 09. Message logs + CSV export
# ============================================

print_section "09. MESSAGE LOGS & EXPORT"

# --- Create log entries ---
BODY=$(do_post "$BASE/api/messages/log" \
    '{"instance_name":"ci-test-u1a","phone_number":"59512345678","status":"sent"}' \
    "$USER1_TOKEN")
assert_contains "Create message log" "ci-test-u1a" "$BODY"
assert_json_field "Log status is sent" ".log.status" "sent" "$BODY"

do_post "$BASE/api/messages/log" \
    '{"instance_name":"ci-test-u1a","phone_number":"59587654321","status":"failed","error_message":"timeout"}' \
    "$USER1_TOKEN" > /dev/null

do_post "$BASE/api/messages/log" \
    '{"instance_name":"ci-test-u1b","phone_number":"59500001111","status":"sent","message_type":"image"}' \
    "$USER1_TOKEN" > /dev/null

# --- Validation: missing fields ---
STATUS=$(get_status "$BASE/api/messages/log" "POST" "$USER1_TOKEN" '{"instance_name":"ci-test-u1a"}')
assert_status "Log without phone_number -> 400" "400" "$STATUS"

# --- List with pagination ---
BODY=$(do_get "$BASE/api/messages/log?page=1&limit=10" "$USER1_TOKEN")
assert_contains "Logs include total" "total" "$BODY"
assert_contains "Logs include pages" "pages" "$BODY"
assert_json_count "Has at least 3 logs" ".logs" 3 "$BODY"

# --- Filter by status ---
BODY=$(do_get "$BASE/api/messages/log?status=failed" "$USER1_TOKEN")
assert_json_count "Filter status=failed has results" ".logs" 1 "$BODY"

# --- Filter by instance ---
BODY=$(do_get "$BASE/api/messages/log?instance_name=ci-test-u1b" "$USER1_TOKEN")
assert_json_count "Filter by instance_name" ".logs" 1 "$BODY"

# --- Isolation: User2 cannot see User1 logs ---
BODY=$(do_get "$BASE/api/messages/log" "$USER2_TOKEN")
assert_not_contains "User2 cannot see User1 logs" "ci-test-u1a" "$BODY"

# --- CSV Export ---
HEADERS=$(get_headers "$BASE/api/messages/export" "$USER1_TOKEN")
assert_header "Export Content-Type is CSV" "Content-Type" "" "$HEADERS"

BODY=$(do_get "$BASE/api/messages/export" "$USER1_TOKEN")
assert_contains "CSV has header row" "ID,Instance,Phone" "$BODY"
assert_contains "CSV contains test data" "ci-test-u1a" "$BODY"

# --- Export method check ---
STATUS=$(get_status "$BASE/api/messages/export" "POST" "$USER1_TOKEN")
assert_status "Export POST -> 405" "405" "$STATUS"

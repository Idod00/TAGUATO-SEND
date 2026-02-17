#!/bin/bash
# ============================================
# 08. Scheduled messages CRUD (user-scoped)
# ============================================

print_section "08. SCHEDULED MESSAGES"

FUTURE_DATE="2099-12-31T23:59:00"

# --- Create scheduled message ---
BODY=$(do_post "$BASE/api/scheduled" \
    '{"instance_name":"ci-test-u1a","recipients":["59512345678"],"message_content":"CI test msg","scheduled_at":"'"$FUTURE_DATE"'"}' \
    "$USER1_TOKEN")
SCHED1_ID=$(json_val "$BODY" '.message.id')
assert_json_field "Create scheduled message status" ".message.status" "pending" "$BODY"
assert_contains "Create scheduled with instance" "ci-test-u1a" "$BODY"

# --- Create second message ---
BODY=$(do_post "$BASE/api/scheduled" \
    '{"instance_name":"ci-test-u1a","recipients":["59587654321"],"message_content":"CI test msg 2","scheduled_at":"'"$FUTURE_DATE"'"}' \
    "$USER1_TOKEN")
SCHED2_ID=$(json_val "$BODY" '.message.id')

# --- List with pagination ---
BODY=$(do_get "$BASE/api/scheduled?page=1&limit=10" "$USER1_TOKEN")
assert_contains "List includes total field" "total" "$BODY"
assert_contains "List includes pages field" "pages" "$BODY"
assert_json_count "Has at least 2 messages" ".messages" 2 "$BODY"

# --- Get detail ---
BODY=$(do_get "$BASE/api/scheduled/$SCHED1_ID" "$USER1_TOKEN")
assert_json_field "Detail shows correct ID" ".message.id" "$SCHED1_ID" "$BODY"

# --- Update only pending ---
BODY=$(do_put "$BASE/api/scheduled/$SCHED1_ID" \
    '{"message_content":"Updated CI msg"}' "$USER1_TOKEN")
assert_json_field "Update message content" ".message.message_content" "Updated CI msg" "$BODY"

# --- Validations ---
STATUS=$(get_status "$BASE/api/scheduled" "POST" "$USER1_TOKEN" \
    '{"instance_name":"ci-test-u1a","recipients":"not-array","message_content":"test","scheduled_at":"'"$FUTURE_DATE"'"}')
assert_status "Recipients not array -> 400" "400" "$STATUS"

STATUS=$(get_status "$BASE/api/scheduled" "POST" "$USER1_TOKEN" \
    '{"instance_name":"ci-test-u1a","recipients":[],"message_content":"test","scheduled_at":"'"$FUTURE_DATE"'"}')
assert_status "Empty recipients -> 400" "400" "$STATUS"

LONG_CONTENT=$(printf 'x%.0s' $(seq 1 5001))
STATUS=$(get_status "$BASE/api/scheduled" "POST" "$USER1_TOKEN" \
    '{"instance_name":"ci-test-u1a","recipients":["59512345678"],"message_content":"'"$LONG_CONTENT"'","scheduled_at":"'"$FUTURE_DATE"'"}')
assert_status "Content > 5000 chars -> 400" "400" "$STATUS"

# --- Ownership: other's instance ---
STATUS=$(get_status "$BASE/api/scheduled" "POST" "$USER1_TOKEN" \
    '{"instance_name":"ci-test-u2a","recipients":["59512345678"],"message_content":"test","scheduled_at":"'"$FUTURE_DATE"'"}')
assert_status "Schedule for other's instance -> 403" "403" "$STATUS"

# --- Isolation: User2 cannot see User1 scheduled ---
BODY=$(do_get "$BASE/api/scheduled" "$USER2_TOKEN")
assert_not_contains "User2 cannot see User1 scheduled" "CI test msg" "$BODY"

STATUS=$(get_status "$BASE/api/scheduled/$SCHED1_ID" "GET" "$USER2_TOKEN")
assert_status "User2 cannot get User1 detail -> 404" "404" "$STATUS"

# --- Cancel (delete) ---
BODY=$(do_delete "$BASE/api/scheduled/$SCHED1_ID" "$USER1_TOKEN")
assert_json_field "Cancel sets status cancelled" ".message.status" "cancelled" "$BODY"

# Cannot cancel already cancelled
STATUS=$(get_status "$BASE/api/scheduled/$SCHED1_ID" "DELETE" "$USER1_TOKEN")
assert_status "Cannot cancel non-pending -> 400" "400" "$STATUS"

# Cleanup
do_delete "$BASE/api/scheduled/$SCHED2_ID" "$USER1_TOKEN" > /dev/null 2>&1

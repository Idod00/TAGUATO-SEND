#!/bin/bash
# ============================================
# 17. Multi-tenant isolation (end-to-end)
# ============================================

print_section "17. MULTI-TENANT ISOLATION"

# --- Setup: User1 creates data, User2 tries to access ---

# Templates isolation
BODY=$(do_post "$BASE/api/templates" \
    '{"name":"ci-tenant-tpl","content":"Private template"}' "$USER1_TOKEN")
TENANT_TPL_ID=$(json_val "$BODY" '.template.id')

BODY=$(do_get "$BASE/api/templates" "$USER2_TOKEN")
assert_not_contains "User2 cannot list User1 templates" "ci-tenant-tpl" "$BODY"

STATUS=$(get_status "$BASE/api/templates/$TENANT_TPL_ID" "PUT" "$USER2_TOKEN" '{"name":"hacked"}')
assert_status "User2 cannot update User1 template -> 404" "404" "$STATUS"

STATUS=$(get_status "$BASE/api/templates/$TENANT_TPL_ID" "DELETE" "$USER2_TOKEN")
assert_status "User2 cannot delete User1 template -> 404" "404" "$STATUS"

# Contacts isolation
BODY=$(do_post "$BASE/api/contacts" '{"name":"ci-tenant-list"}' "$USER1_TOKEN")
TENANT_LIST_ID=$(json_val "$BODY" '.list.id')

do_post "$BASE/api/contacts/$TENANT_LIST_ID/items" \
    '{"phone_number":"59512345678","label":"Private"}' "$USER1_TOKEN" > /dev/null

BODY=$(do_get "$BASE/api/contacts" "$USER2_TOKEN")
assert_not_contains "User2 cannot list User1 contacts" "ci-tenant-list" "$BODY"

STATUS=$(get_status "$BASE/api/contacts/$TENANT_LIST_ID" "GET" "$USER2_TOKEN")
assert_status "User2 cannot view User1 contact list -> 404" "404" "$STATUS"

STATUS=$(get_status "$BASE/api/contacts/$TENANT_LIST_ID/items" "POST" "$USER2_TOKEN" \
    '{"phone_number":"59500000000","label":"injected"}')
assert_status "User2 cannot add items to User1 list -> 404" "404" "$STATUS"

# Scheduled messages isolation
BODY=$(do_post "$BASE/api/scheduled" \
    '{"instance_name":"ci-test-u1a","recipients":["59512345678"],"message_content":"Tenant private","scheduled_at":"2099-12-31T23:59:00"}' \
    "$USER1_TOKEN")
TENANT_SCHED_ID=$(json_val "$BODY" '.message.id')

BODY=$(do_get "$BASE/api/scheduled" "$USER2_TOKEN")
assert_not_contains "User2 cannot list User1 scheduled" "Tenant private" "$BODY"

STATUS=$(get_status "$BASE/api/scheduled/$TENANT_SCHED_ID" "GET" "$USER2_TOKEN")
assert_status "User2 cannot view User1 scheduled -> 404" "404" "$STATUS"

STATUS=$(get_status "$BASE/api/scheduled/$TENANT_SCHED_ID" "DELETE" "$USER2_TOKEN")
assert_status "User2 cannot cancel User1 scheduled -> 404" "404" "$STATUS"

# Message logs isolation
do_post "$BASE/api/messages/log" \
    '{"instance_name":"ci-test-u1a","phone_number":"59512345678","status":"sent"}' \
    "$USER1_TOKEN" > /dev/null

BODY=$(do_get "$BASE/api/messages/log" "$USER2_TOKEN")
assert_not_contains "User2 cannot see User1 logs" "ci-test-u1a" "$BODY"

# Sessions isolation
BODY=$(do_post "$BASE/api/auth/login" '{"username":"ci_user1","password":"'"$CI_PASSWORD"'"}')
U1_LOGIN_TOKEN=$(json_val "$BODY" '.token')
BODY=$(do_get "$BASE/api/sessions" "$U1_LOGIN_TOKEN")
U1_SID=$(json_val "$BODY" '.sessions[0].id')

if [ -n "$U1_SID" ] && [ "$U1_SID" != "null" ]; then
    STATUS=$(get_status "$BASE/api/sessions/$U1_SID" "DELETE" "$USER2_TOKEN")
    assert_status "User2 cannot revoke User1 session -> 404" "404" "$STATUS"
fi

# --- Cleanup ---
do_delete "$BASE/api/templates/$TENANT_TPL_ID" "$USER1_TOKEN" > /dev/null 2>&1
do_delete "$BASE/api/contacts/$TENANT_LIST_ID" "$USER1_TOKEN" > /dev/null 2>&1
do_delete "$BASE/api/scheduled/$TENANT_SCHED_ID" "$USER1_TOKEN" > /dev/null 2>&1

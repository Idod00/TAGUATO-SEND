#!/bin/bash
# ============================================
# 04. Instances (create, filter, ownership, delete)
# ============================================

print_section "04. INSTANCES"

# --- Create instances ---
BODY=$(do_post "$BASE/instance/create" \
    '{"instanceName":"ci-test-u1a","integration":"WHATSAPP-BAILEYS","qrcode":true}' "$USER1_TOKEN")
assert_contains "User1 creates ci-test-u1a" "ci-test-u1a" "$BODY"

BODY=$(do_post "$BASE/instance/create" \
    '{"instanceName":"ci-test-u1b","integration":"WHATSAPP-BAILEYS","qrcode":true}' "$USER1_TOKEN")
assert_contains "User1 creates ci-test-u1b" "ci-test-u1b" "$BODY"

# --- Instance name validation ---
STATUS=$(get_status "$BASE/instance/create" "POST" "$USER1_TOKEN" \
    '{"instanceName":"-bad-name","integration":"WHATSAPP-BAILEYS","qrcode":true}')
assert_status "Name starting with hyphen -> 400" "400" "$STATUS"

STATUS=$(get_status "$BASE/instance/create" "POST" "$USER1_TOKEN" \
    '{"instanceName":"bad name","integration":"WHATSAPP-BAILEYS","qrcode":true}')
assert_status "Name with spaces -> 400" "400" "$STATUS"

# --- User2 creates instance ---
BODY=$(do_post "$BASE/instance/create" \
    '{"instanceName":"ci-test-u2a","integration":"WHATSAPP-BAILEYS","qrcode":true}' "$USER2_TOKEN")
assert_contains "User2 creates ci-test-u2a" "ci-test-u2a" "$BODY"

# --- Duplicate instance name ---
STATUS=$(get_status "$BASE/instance/create" "POST" "$USER2_TOKEN" \
    '{"instanceName":"ci-test-u1a","integration":"WHATSAPP-BAILEYS","qrcode":true}')
assert_status "Duplicate instance name -> 409" "409" "$STATUS"

# --- Instance limit (user1 has max=3, already has 2; third should work) ---
BODY=$(do_post "$BASE/instance/create" \
    '{"instanceName":"ci-test-u1c","integration":"WHATSAPP-BAILEYS","qrcode":true}' "$USER1_TOKEN")
assert_contains "User1 creates 3rd instance (within limit)" "ci-test-u1c" "$BODY"

# 4th should exceed limit
STATUS=$(get_status "$BASE/instance/create" "POST" "$USER1_TOKEN" \
    '{"instanceName":"ci-test-u1d","integration":"WHATSAPP-BAILEYS","qrcode":true}')
assert_status "User1 exceeds limit -> 403" "403" "$STATUS"

BODY=$(do_post "$BASE/instance/create" \
    '{"instanceName":"ci-test-u1d","integration":"WHATSAPP-BAILEYS","qrcode":true}' "$USER1_TOKEN")
assert_contains "Limit reached message" "Instance limit reached" "$BODY"

# --- fetchInstances filtering ---
print_section "04b. INSTANCE FILTERING (fetchInstances)"

BODY=$(do_get "$BASE/instance/fetchInstances" "$ADMIN_TOKEN")
assert_contains "Admin sees ci-test-u1a" "ci-test-u1a" "$BODY"
assert_contains "Admin sees ci-test-u2a" "ci-test-u2a" "$BODY"

BODY=$(do_get "$BASE/instance/fetchInstances" "$USER1_TOKEN")
assert_contains "User1 sees ci-test-u1a" "ci-test-u1a" "$BODY"
assert_contains "User1 sees ci-test-u1b" "ci-test-u1b" "$BODY"
assert_not_contains "User1 does NOT see ci-test-u2a" "ci-test-u2a" "$BODY"

BODY=$(do_get "$BASE/instance/fetchInstances" "$USER2_TOKEN")
assert_contains "User2 sees ci-test-u2a" "ci-test-u2a" "$BODY"
assert_not_contains "User2 does NOT see ci-test-u1" "ci-test-u1" "$BODY"

# --- Ownership operations ---
print_section "04c. INSTANCE OWNERSHIP"

STATUS=$(get_status "$BASE/instance/connectionState/ci-test-u1a" "GET" "$USER1_TOKEN")
assert_status "User1 accesses own instance -> 200" "200" "$STATUS"

STATUS=$(get_status "$BASE/instance/connectionState/ci-test-u2a" "GET" "$USER1_TOKEN")
assert_status "User1 cannot access User2 instance -> 403" "403" "$STATUS"

BODY=$(do_get "$BASE/instance/connectionState/ci-test-u2a" "$USER1_TOKEN")
assert_contains "Ownership error message" "don't own" "$BODY"

STATUS=$(get_status "$BASE/instance/connectionState/ci-test-u1a" "GET" "$USER2_TOKEN")
assert_status "User2 cannot access User1 instance -> 403" "403" "$STATUS"

STATUS=$(get_status "$BASE/instance/connectionState/ci-test-u1a" "GET" "$ADMIN_TOKEN")
assert_status "Admin accesses any instance -> 200" "200" "$STATUS"

STATUS=$(get_status "$BASE/instance/delete/ci-test-u2a" "DELETE" "$USER1_TOKEN")
assert_status "User1 cannot delete User2 instance -> 403" "403" "$STATUS"

# --- Delete instances ---
print_section "04d. INSTANCE DELETE + SLOT RECOVERY"

BODY=$(do_delete "$BASE/instance/delete/ci-test-u1c" "$USER1_TOKEN")
assert_contains "User1 deletes ci-test-u1c" "Instance deleted" "$BODY"

# Slot recovered — User1 can create again
BODY=$(do_post "$BASE/instance/create" \
    '{"instanceName":"ci-test-u1c","integration":"WHATSAPP-BAILEYS","qrcode":true}' "$USER1_TOKEN")
assert_contains "User1 creates after slot recovery" "ci-test-u1c" "$BODY"

# Cleanup: delete the extra instance to keep user1 at 2 for later tests
do_delete "$BASE/instance/delete/ci-test-u1c" "$USER1_TOKEN" > /dev/null

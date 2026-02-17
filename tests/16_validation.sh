#!/bin/bash
# ============================================
# 16. Boundary value validation (validate.lua)
# ============================================

print_section "16. VALIDATION BOUNDARY VALUES"

# --- Username boundaries ---
print_section "16a. USERNAME BOUNDARIES"

# 2 chars -> 400 (min is 3)
STATUS=$(get_status "$BASE/admin/users" "POST" "$ADMIN_TOKEN" \
    '{"username":"ab","password":"CiTestPass1"}')
assert_status "Username 2 chars -> 400" "400" "$STATUS"

# 3 chars -> OK (boundary)
BODY=$(do_post "$BASE/admin/users" '{"username":"abc","password":"CiTestPass1"}' "$ADMIN_TOKEN")
assert_contains "Username 3 chars -> OK" "abc" "$BODY"
ABC_ID=$(json_val "$BODY" '.user.id')

# 50 chars -> OK (boundary)
NAME50=$(printf 'a%.0s' $(seq 1 50))
BODY=$(do_post "$BASE/admin/users" '{"username":"'"$NAME50"'","password":"CiTestPass1"}' "$ADMIN_TOKEN")
assert_contains "Username 50 chars -> OK" "$NAME50" "$BODY"
NAME50_ID=$(json_val "$BODY" '.user.id')

# 51 chars -> 400
NAME51=$(printf 'a%.0s' $(seq 1 51))
STATUS=$(get_status "$BASE/admin/users" "POST" "$ADMIN_TOKEN" \
    '{"username":"'"$NAME51"'","password":"CiTestPass1"}')
assert_status "Username 51 chars -> 400" "400" "$STATUS"

# Special chars -> 400
STATUS=$(get_status "$BASE/admin/users" "POST" "$ADMIN_TOKEN" \
    '{"username":"bad@user#","password":"CiTestPass1"}')
assert_status "Username with @# -> 400" "400" "$STATUS"

# Spaces -> 400
STATUS=$(get_status "$BASE/admin/users" "POST" "$ADMIN_TOKEN" \
    '{"username":"bad user","password":"CiTestPass1"}')
assert_status "Username with spaces -> 400" "400" "$STATUS"

# Cleanup
do_delete "$BASE/admin/users/$ABC_ID" "$ADMIN_TOKEN" > /dev/null 2>&1
do_delete "$BASE/admin/users/$NAME50_ID" "$ADMIN_TOKEN" > /dev/null 2>&1

# --- Password boundaries ---
print_section "16b. PASSWORD BOUNDARIES"

# 7 chars -> 400
STATUS=$(get_status "$BASE/admin/users" "POST" "$ADMIN_TOKEN" \
    '{"username":"ci_pw7","password":"Short1A"}')
assert_status "Password 7 chars -> 400" "400" "$STATUS"

# 8 chars (valid) -> OK
BODY=$(do_post "$BASE/admin/users" '{"username":"ci_pw8","password":"Valid1Aa"}' "$ADMIN_TOKEN")
assert_contains "Password 8 chars -> OK" "ci_pw8" "$BODY"
PW8_ID=$(json_val "$BODY" '.user.id')

# Only lowercase + number -> 400
STATUS=$(get_status "$BASE/admin/users" "POST" "$ADMIN_TOKEN" \
    '{"username":"ci_pwlo","password":"alllower1"}')
assert_status "Password no uppercase -> 400" "400" "$STATUS"

# Only uppercase + number -> 400
STATUS=$(get_status "$BASE/admin/users" "POST" "$ADMIN_TOKEN" \
    '{"username":"ci_pwup","password":"ALLUPPER1"}')
assert_status "Password no lowercase -> 400" "400" "$STATUS"

# No number -> 400
STATUS=$(get_status "$BASE/admin/users" "POST" "$ADMIN_TOKEN" \
    '{"username":"ci_pwnn","password":"NoNumberHere"}')
assert_status "Password no number -> 400" "400" "$STATUS"

# Cleanup
do_delete "$BASE/admin/users/$PW8_ID" "$ADMIN_TOKEN" > /dev/null 2>&1

# --- Phone boundaries ---
print_section "16c. PHONE BOUNDARIES"

# Create a contact list for phone tests
BODY=$(do_post "$BASE/api/contacts" '{"name":"ci-test-phone-validation"}' "$USER1_TOKEN")
PHONE_LIST_ID=$(json_val "$BODY" '.list.id')

# 7 digits -> 400
STATUS=$(get_status "$BASE/api/contacts/$PHONE_LIST_ID/items" "POST" "$USER1_TOKEN" \
    '{"phone_number":"1234567","label":"short"}')
assert_status "Phone 7 digits -> 400" "400" "$STATUS"

# 8 digits -> OK
BODY=$(do_post "$BASE/api/contacts/$PHONE_LIST_ID/items" \
    '{"phone_number":"12345678","label":"eight"}' "$USER1_TOKEN")
assert_contains "Phone 8 digits -> OK" "12345678" "$BODY"

# 20 digits -> OK
BODY=$(do_post "$BASE/api/contacts/$PHONE_LIST_ID/items" \
    '{"phone_number":"12345678901234567890","label":"twenty"}' "$USER1_TOKEN")
assert_contains "Phone 20 digits -> OK" "12345678901234567890" "$BODY"

# 21 digits -> 400
STATUS=$(get_status "$BASE/api/contacts/$PHONE_LIST_ID/items" "POST" "$USER1_TOKEN" \
    '{"phone_number":"123456789012345678901","label":"twentyone"}')
assert_status "Phone 21 digits -> 400" "400" "$STATUS"

# Letters -> 400
STATUS=$(get_status "$BASE/api/contacts/$PHONE_LIST_ID/items" "POST" "$USER1_TOKEN" \
    '{"phone_number":"1234abcd90","label":"letters"}')
assert_status "Phone with letters -> 400" "400" "$STATUS"

# Cleanup
do_delete "$BASE/api/contacts/$PHONE_LIST_ID" "$USER1_TOKEN" > /dev/null 2>&1

# --- Instance name boundaries ---
print_section "16d. INSTANCE NAME BOUNDARIES"

# Starts with hyphen -> 400
STATUS=$(get_status "$BASE/instance/create" "POST" "$USER1_TOKEN" \
    '{"instanceName":"-invalid","integration":"WHATSAPP-BAILEYS","qrcode":true}')
assert_status "Instance name starts with hyphen -> 400" "400" "$STATUS"

# Contains spaces -> 400
STATUS=$(get_status "$BASE/instance/create" "POST" "$USER1_TOKEN" \
    '{"instanceName":"bad name","integration":"WHATSAPP-BAILEYS","qrcode":true}')
assert_status "Instance name with spaces -> 400" "400" "$STATUS"

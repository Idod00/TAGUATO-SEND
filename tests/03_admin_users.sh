#!/bin/bash
# ============================================
# 03. Admin user CRUD
# ============================================

print_section "03. ADMIN - USER CRUD"

# --- Create user validations ---
STATUS=$(get_status "$BASE/admin/users" "POST" "$ADMIN_TOKEN" '{"username":"ab","password":"CiTestPass1"}')
assert_status "Username < 3 chars -> 400" "400" "$STATUS"

BODY=$(do_post "$BASE/admin/users" '{"username":"ab","password":"CiTestPass1"}' "$ADMIN_TOKEN")
assert_contains "Username too short error" "between 3 and 50" "$BODY"

STATUS=$(get_status "$BASE/admin/users" "POST" "$ADMIN_TOKEN" '{"username":"bad@user!","password":"CiTestPass1"}')
assert_status "Username with special chars -> 400" "400" "$STATUS"

STATUS=$(get_status "$BASE/admin/users" "POST" "$ADMIN_TOKEN" '{"username":"ci_nopass"}')
assert_status "Missing password -> 400" "400" "$STATUS"

# --- Password validation (4 variants from validate.lua) ---
BODY=$(do_post "$BASE/admin/users" '{"username":"ci_pwtest","password":"Short1A"}' "$ADMIN_TOKEN")
assert_contains "Password < 8 chars rejected" "at least 8 characters" "$BODY"

BODY=$(do_post "$BASE/admin/users" '{"username":"ci_pwtest","password":"alllower1"}' "$ADMIN_TOKEN")
assert_contains "No uppercase rejected" "uppercase" "$BODY"

BODY=$(do_post "$BASE/admin/users" '{"username":"ci_pwtest","password":"ALLUPPER1"}' "$ADMIN_TOKEN")
assert_contains "No lowercase rejected" "lowercase" "$BODY"

BODY=$(do_post "$BASE/admin/users" '{"username":"ci_pwtest","password":"NoNumbersHere"}' "$ADMIN_TOKEN")
assert_contains "No number rejected" "number" "$BODY"

# --- Duplicate username ---
STATUS=$(get_status "$BASE/admin/users" "POST" "$ADMIN_TOKEN" \
    '{"username":"ci_user1","password":"CiTestPass1"}')
assert_status "Duplicate username -> 409" "409" "$STATUS"

# --- Invalid role ---
STATUS=$(get_status "$BASE/admin/users" "POST" "$ADMIN_TOKEN" \
    '{"username":"ci_badrole","password":"CiTestPass1","role":"superadmin"}')
assert_status "Invalid role -> 400" "400" "$STATUS"

# --- List users (paginated) ---
BODY=$(do_get "$BASE/admin/users" "$ADMIN_TOKEN")
assert_contains "List includes ci_user1" "ci_user1" "$BODY"
assert_contains "List includes ci_user2" "ci_user2" "$BODY"
assert_contains "List includes admin" '"role":"admin"' "$BODY"
assert_contains "Users list has total field" '"total"' "$BODY"
assert_json_field "Users list has page field" ".page" "1" "$BODY"

# --- Pagination: limit=1 ---
BODY=$(do_get "$BASE/admin/users?limit=1" "$ADMIN_TOKEN")
assert_json_field "Limit=1 returns 1 user" ".users | length" "1" "$BODY"
TOTAL_USERS=$(echo "$BODY" | jq -r '.total')
TOTAL_VAL=$((TOTAL + 1))
TOTAL=$TOTAL_VAL
if [ "$TOTAL_USERS" -gt "1" ]; then
    echo -e "  ${GREEN}PASS${NC} Pagination total > 1 with limit=1"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} Pagination total should be > 1 (got $TOTAL_USERS)"
    FAIL=$((FAIL + 1))
fi

# --- Search filter ---
BODY=$(do_get "$BASE/admin/users?search=ci_user1" "$ADMIN_TOKEN")
assert_contains "Search finds ci_user1" "ci_user1" "$BODY"
assert_not_contains "Search excludes ci_user2" "ci_user2" "$BODY"

# --- Get single user ---
BODY=$(do_get "$BASE/admin/users/$USER1_ID" "$ADMIN_TOKEN")
assert_json_field "GET user shows username" ".user.username" "ci_user1" "$BODY"
assert_contains "User includes instances field" "instances" "$BODY"

# --- Update user ---
BODY=$(do_put "$BASE/admin/users/$USER1_ID" '{"max_instances":5}' "$ADMIN_TOKEN")
assert_json_field "Update max_instances to 5" ".user.max_instances" "5" "$BODY"

# Restore
do_put "$BASE/admin/users/$USER1_ID" '{"max_instances":3}' "$ADMIN_TOKEN" > /dev/null

# --- Regenerate token invalidates sessions ---
OLD_TOKEN="$USER1_TOKEN"
BODY=$(do_put "$BASE/admin/users/$USER1_ID" '{"regenerate_token":true}' "$ADMIN_TOKEN")
assert_not_contains "Regenerate token does not expose api_token" "api_token" "$BODY"

# Old session token should be invalidated (wait for cache expiry)
sleep 11
STATUS=$(get_status "$BASE/api/auth/me" "GET" "$OLD_TOKEN")
assert_status "Old session invalid after regenerate_token -> 401" "401" "$STATUS"

# Re-login to get a new session token
BODY=$(do_post "$BASE/api/auth/login" '{"username":"ci_user1","password":"'"$CI_PASSWORD"'"}')
USER1_TOKEN=$(json_val "$BODY" '.token')
export USER1_TOKEN

# --- User normal cannot access /admin/ ---
STATUS=$(get_status "$BASE/admin/users" "GET" "$USER1_TOKEN")
assert_status "Normal user cannot access /admin/ -> 403" "403" "$STATUS"

# --- Deactivate user (invalidates sessions) ---
do_put "$BASE/admin/users/$USER1_ID" '{"is_active":false}' "$ADMIN_TOKEN" > /dev/null

# Wait for cache to expire so the invalidated session is recognized
sleep 11
STATUS=$(get_status "$BASE/api/auth/me" "GET" "$USER1_TOKEN")
assert_status "Deactivated user session invalid -> 401" "401" "$STATUS"

# Reactivate and re-login
do_put "$BASE/admin/users/$USER1_ID" '{"is_active":true}' "$ADMIN_TOKEN" > /dev/null
BODY=$(do_post "$BASE/api/auth/login" '{"username":"ci_user1","password":"'"$CI_PASSWORD"'"}')
USER1_TOKEN=$(json_val "$BODY" '.token')
export USER1_TOKEN

STATUS=$(get_status "$BASE/instance/fetchInstances" "GET" "$USER1_TOKEN")
assert_status "Reactivated user can access -> 200" "200" "$STATUS"

# --- Admin cannot self-delete ---
STATUS=$(get_status "$BASE/admin/users/1" "DELETE" "$ADMIN_TOKEN")
assert_status "Admin cannot self-delete -> 400" "400" "$STATUS"

# --- Delete user (ci_user3) ---
BODY=$(do_delete "$BASE/admin/users/$USER3_ID" "$ADMIN_TOKEN")
assert_contains "Delete user returns username" "ci_user3" "$BODY"

# Token of deleted user no longer works
STATUS=$(get_status "$BASE/instance/fetchInstances" "GET" "$USER3_TOKEN")
assert_status "Deleted user token -> 401" "401" "$STATUS"

# Recreate ci_user3 for later tests
BODY=$(do_post "$BASE/admin/users" \
    '{"username":"ci_user3","password":"'"$CI_PASSWORD"'","max_instances":1}' "$ADMIN_TOKEN")
USER3_ID=$(json_val "$BODY" '.user.id')
# Login to get session token
BODY=$(do_post "$BASE/api/auth/login" '{"username":"ci_user3","password":"'"$CI_PASSWORD"'"}')
USER3_TOKEN=$(json_val "$BODY" '.token')
export USER3_TOKEN USER3_ID

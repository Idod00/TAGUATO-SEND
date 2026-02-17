#!/bin/bash
# ============================================
# 02. Authentication (login, /me, change-password, brute force)
# ============================================

print_section "02. AUTHENTICATION"

# --- Login validations ---
STATUS=$(get_status "$BASE/api/auth/login" "POST" "" '{}')
assert_status "Login empty body -> 400" "400" "$STATUS"

STATUS=$(get_status "$BASE/api/auth/login" "POST" "" '{"username":"ci_user1"}')
assert_status "Login missing password -> 400" "400" "$STATUS"

STATUS=$(get_status "$BASE/api/auth/login" "POST" "" '{"username":"nobody","password":"WrongPass1"}')
assert_status "Login bad credentials -> 401" "401" "$STATUS"

BODY=$(do_post "$BASE/api/auth/login" '{"username":"nobody","password":"WrongPass1"}')
assert_contains "Login error message" "Invalid username or password" "$BODY"

# --- Successful login ---
BODY=$(do_post "$BASE/api/auth/login" '{"username":"ci_user1","password":"'"$CI_PASSWORD"'"}')
assert_contains "Login ok returns token" "token" "$BODY"
assert_json_field "Login user.username" ".user.username" "ci_user1" "$BODY"
assert_json_field "Login user.role" ".user.role" "user" "$BODY"

LOGIN_TOKEN=$(json_val "$BODY" '.token')

# --- /me without apikey ---
STATUS=$(get_status "$BASE/api/auth/me")
assert_status "GET /me no apikey -> 401" "401" "$STATUS"

# --- /me with bad apikey ---
STATUS=$(get_status "$BASE/api/auth/me" "GET" "fake_token_12345")
assert_status "GET /me bad apikey -> 401" "401" "$STATUS"

# --- /me with valid token ---
BODY=$(do_get "$BASE/api/auth/me" "$LOGIN_TOKEN")
STATUS=$(get_status "$BASE/api/auth/me" "GET" "$LOGIN_TOKEN")
assert_status "GET /me valid token -> 200" "200" "$STATUS"
assert_json_field "/me returns username" ".user.username" "ci_user1" "$BODY"
assert_contains "/me includes instances" "instances" "$BODY"

# --- Change password validations ---
STATUS=$(get_status "$BASE/api/auth/change-password" "POST" "$USER1_TOKEN" '{}')
assert_status "Change-password empty body -> 400" "400" "$STATUS"

BODY=$(do_post "$BASE/api/auth/change-password" \
    '{"current_password":"'"$CI_PASSWORD"'","new_password":"short"}' "$USER1_TOKEN")
assert_contains "Weak new password rejected" "at least 8 characters" "$BODY"

BODY=$(do_post "$BASE/api/auth/change-password" \
    '{"current_password":"'"$CI_PASSWORD"'","new_password":"alllowercase1"}' "$USER1_TOKEN")
assert_contains "No uppercase rejected" "uppercase" "$BODY"

STATUS=$(get_status "$BASE/api/auth/change-password" "POST" "$USER1_TOKEN" \
    '{"current_password":"WrongOldPass1","new_password":"NewValid1"}')
assert_status "Wrong current password -> 401" "401" "$STATUS"

# --- Successful password change ---
BODY=$(do_post "$BASE/api/auth/change-password" \
    '{"current_password":"'"$CI_PASSWORD"'","new_password":"CiNewPass1"}' "$USER1_TOKEN")
assert_contains "Password changed successfully" "Password changed" "$BODY"

# --- Login with new password ---
BODY=$(do_post "$BASE/api/auth/login" '{"username":"ci_user1","password":"CiNewPass1"}')
assert_contains "Login with new password works" "token" "$BODY"
USER1_TOKEN=$(json_val "$BODY" '.token')
export USER1_TOKEN

# --- Restore original password ---
do_put "$BASE/admin/users/$USER1_ID" '{"password":"'"$CI_PASSWORD"'"}' "$ADMIN_TOKEN" > /dev/null

# --- Brute force lockout ---
# Create a temp user for brute force test
BODY=$(do_post "$BASE/admin/users" \
    '{"username":"ci_brute_user","password":"'"$CI_PASSWORD"'"}' "$ADMIN_TOKEN")
for i in 1 2 3 4 5; do
    do_post "$BASE/api/auth/login" '{"username":"ci_brute_user","password":"WrongPass'$i'"}' > /dev/null
done
STATUS=$(get_status "$BASE/api/auth/login" "POST" "" \
    '{"username":"ci_brute_user","password":"WrongPass6"}')
assert_status "6th failed login -> 429 (locked)" "429" "$STATUS"

# --- Protected endpoint without apikey ---
STATUS=$(get_status "$BASE/instance/fetchInstances")
assert_status "Protected endpoint no apikey -> 401" "401" "$STATUS"

BODY=$(do_get "$BASE/instance/fetchInstances")
assert_contains "Missing apikey message" "Missing apikey" "$BODY"

#!/bin/bash
# ============================================
# 18. Password Recovery Flow
# ============================================

print_section "18. PASSWORD RECOVERY"

# --- forgot-password validations ---
STATUS=$(get_status "$BASE/api/auth/forgot-password" "POST" "" '{}')
assert_status "forgot-password empty body -> 400" "400" "$STATUS"

STATUS=$(get_status "$BASE/api/auth/forgot-password" "POST" "" '{"username":""}')
assert_status "forgot-password empty username -> 400" "400" "$STATUS"

# Valid username returns 200 (anti-enumeration: always 200)
STATUS=$(get_status "$BASE/api/auth/forgot-password" "POST" "" '{"username":"ci_user1"}')
assert_status "forgot-password valid user -> 200" "200" "$STATUS"

# Nonexistent username also returns 200 (anti-enumeration)
STATUS=$(get_status "$BASE/api/auth/forgot-password" "POST" "" '{"username":"nonexistent_user_xyz"}')
assert_status "forgot-password unknown user -> 200 (anti-enum)" "200" "$STATUS"

BODY=$(do_post "$BASE/api/auth/forgot-password" '{"username":"ci_user1"}')
assert_contains "forgot-password response message" "recovery code has been sent" "$BODY"

# --- verify-reset-code validations ---
STATUS=$(get_status "$BASE/api/auth/verify-reset-code" "POST" "" '{}')
assert_status "verify-reset-code empty body -> 400" "400" "$STATUS"

STATUS=$(get_status "$BASE/api/auth/verify-reset-code" "POST" "" '{"username":"ci_user1"}')
assert_status "verify-reset-code missing code -> 400" "400" "$STATUS"

STATUS=$(get_status "$BASE/api/auth/verify-reset-code" "POST" "" '{"username":"ci_user1","code":"000000"}')
assert_status "verify-reset-code invalid code -> 400" "400" "$STATUS"

STATUS=$(get_status "$BASE/api/auth/verify-reset-code" "POST" "" '{"username":"nonexistent_xyz","code":"123456"}')
assert_status "verify-reset-code unknown user -> 400" "400" "$STATUS"

# --- reset-password validations ---
STATUS=$(get_status "$BASE/api/auth/reset-password" "POST" "" '{}')
assert_status "reset-password empty body -> 400" "400" "$STATUS"

STATUS=$(get_status "$BASE/api/auth/reset-password" "POST" "" '{"reset_token":"fake_token"}')
assert_status "reset-password missing new_password -> 400" "400" "$STATUS"

STATUS=$(get_status "$BASE/api/auth/reset-password" "POST" "" '{"reset_token":"fake_token","new_password":"weak"}')
assert_status "reset-password weak password -> 400" "400" "$STATUS"

STATUS=$(get_status "$BASE/api/auth/reset-password" "POST" "" '{"reset_token":"invalid_token_xyz","new_password":"StrongPass1"}')
assert_status "reset-password invalid token -> 400" "400" "$STATUS"

# --- Admin reset password ---
# Normal user cannot reset another user's password
STATUS=$(get_status "$BASE/admin/users/$USER2_ID/reset-password" "POST" "$USER1_TOKEN")
assert_status "Normal user cannot admin-reset -> 403" "403" "$STATUS"

# Admin reset for nonexistent user
STATUS=$(get_status "$BASE/admin/users/99999/reset-password" "POST" "$ADMIN_TOKEN")
assert_status "Admin reset nonexistent user -> 404" "404" "$STATUS"

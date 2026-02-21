#!/bin/bash
# ============================================
# 19. Logout and Logout-All
# ============================================

print_section "19. LOGOUT"

# --- Logout without token ---
STATUS=$(get_status "$BASE/api/auth/logout" "POST")
assert_status "Logout without token -> 401" "401" "$STATUS"

# --- Logout with valid token ---
# Create a fresh session for this test
BODY=$(do_post "$BASE/api/auth/login" '{"username":"ci_user1","password":"'"$CI_PASSWORD"'"}')
LOGOUT_TOKEN=$(json_val "$BODY" '.token')

STATUS=$(get_status "$BASE/api/auth/logout" "POST" "$LOGOUT_TOKEN")
assert_status "Logout valid token -> 200" "200" "$STATUS"

# Token should no longer work
STATUS=$(get_status "$BASE/api/auth/me" "GET" "$LOGOUT_TOKEN")
assert_status "Token invalid after logout -> 401" "401" "$STATUS"

# --- Login again works after logout ---
BODY=$(do_post "$BASE/api/auth/login" '{"username":"ci_user1","password":"'"$CI_PASSWORD"'"}')
assert_contains "Login after logout works" "token" "$BODY"

# --- Logout-all ---
# Create multiple sessions
BODY=$(do_post "$BASE/api/auth/login" '{"username":"ci_user2","password":"'"$CI_PASSWORD"'"}')
LA_TOKEN1=$(json_val "$BODY" '.token')
BODY=$(do_post "$BASE/api/auth/login" '{"username":"ci_user2","password":"'"$CI_PASSWORD"'"}')
LA_TOKEN2=$(json_val "$BODY" '.token')

# Verify both work
STATUS=$(get_status "$BASE/api/auth/me" "GET" "$LA_TOKEN1")
assert_status "Session 1 works before logout-all" "200" "$STATUS"

# Logout all
STATUS=$(get_status "$BASE/api/auth/logout-all" "POST" "$LA_TOKEN1")
assert_status "Logout-all -> 200" "200" "$STATUS"

# Both tokens should be invalidated
STATUS=$(get_status "$BASE/api/auth/me" "GET" "$LA_TOKEN1")
assert_status "Token 1 invalid after logout-all -> 401" "401" "$STATUS"

STATUS=$(get_status "$BASE/api/auth/me" "GET" "$LA_TOKEN2")
assert_status "Token 2 invalid after logout-all -> 401" "401" "$STATUS"

# Login after logout-all works
BODY=$(do_post "$BASE/api/auth/login" '{"username":"ci_user2","password":"'"$CI_PASSWORD"'"}')
assert_contains "Login after logout-all works" "token" "$BODY"
USER2_TOKEN=$(json_val "$BODY" '.token')
export USER2_TOKEN

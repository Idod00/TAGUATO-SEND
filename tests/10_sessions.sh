#!/bin/bash
# ============================================
# 10. Sessions (user + admin)
# ============================================

print_section "10. SESSIONS"

# --- Login to create a session for User1 ---
BODY=$(do_post "$BASE/api/auth/login" '{"username":"ci_user1","password":"'"$CI_PASSWORD"'"}')
SESSION_TOKEN=$(json_val "$BODY" '.token')

# --- List user sessions ---
BODY=$(do_get "$BASE/api/sessions" "$SESSION_TOKEN")
assert_json_count "User1 has at least 1 session" ".sessions" 1 "$BODY"
SESSION_ID=$(json_val "$BODY" '.sessions[0].id')

# --- User normal cannot access admin sessions ---
STATUS=$(get_status "$BASE/admin/sessions" "GET" "$USER1_TOKEN")
assert_status "Normal user cannot access /admin/sessions -> 403" "403" "$STATUS"

# --- Admin list all sessions ---
BODY=$(do_get "$BASE/admin/sessions" "$ADMIN_TOKEN")
assert_contains "Admin sessions include username field" "username" "$BODY"
assert_json_count "Admin sees at least 1 session" ".sessions" 1 "$BODY"

# --- Admin revoke any session ---
if [ -n "$SESSION_ID" ] && [ "$SESSION_ID" != "null" ]; then
    BODY=$(do_delete "$BASE/admin/sessions/$SESSION_ID" "$ADMIN_TOKEN")
    assert_contains "Admin revokes session" "revoked" "$BODY"
fi

# --- User revoke own session ---
# Create a new session first
BODY=$(do_post "$BASE/api/auth/login" '{"username":"ci_user2","password":"'"$CI_PASSWORD"'"}')
U2_SESSION_TOKEN=$(json_val "$BODY" '.token')

BODY=$(do_get "$BASE/api/sessions" "$U2_SESSION_TOKEN")
U2_SESSION_ID=$(json_val "$BODY" '.sessions[0].id')

if [ -n "$U2_SESSION_ID" ] && [ "$U2_SESSION_ID" != "null" ]; then
    BODY=$(do_delete "$BASE/api/sessions/$U2_SESSION_ID" "$U2_SESSION_TOKEN")
    assert_contains "User2 revokes own session" "revoked" "$BODY"
fi

# --- Revoke nonexistent session ---
STATUS=$(get_status "$BASE/api/sessions/99999" "DELETE" "$USER1_TOKEN")
assert_status "Revoke nonexistent session -> 404" "404" "$STATUS"

# --- Isolation: User1 cannot revoke User2 sessions ---
# Create new session for User2
BODY=$(do_post "$BASE/api/auth/login" '{"username":"ci_user2","password":"'"$CI_PASSWORD"'"}')
U2_SESSION_TOKEN2=$(json_val "$BODY" '.token')
BODY=$(do_get "$BASE/api/sessions" "$U2_SESSION_TOKEN2")
U2_SID2=$(json_val "$BODY" '.sessions[0].id')

if [ -n "$U2_SID2" ] && [ "$U2_SID2" != "null" ]; then
    STATUS=$(get_status "$BASE/api/sessions/$U2_SID2" "DELETE" "$USER1_TOKEN")
    assert_status "User1 cannot revoke User2 session -> 404" "404" "$STATUS"
fi

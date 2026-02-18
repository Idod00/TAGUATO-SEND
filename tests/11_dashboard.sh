#!/bin/bash
# ============================================
# 11. Dashboard (user + admin)
# ============================================

print_section "11. DASHBOARD"

# --- User dashboard ---
BODY=$(do_get "$BASE/api/user/dashboard" "$USER1_TOKEN")
STATUS=$(get_status "$BASE/api/user/dashboard" "GET" "$USER1_TOKEN")
assert_status "User dashboard -> 200" "200" "$STATUS"
assert_contains "Has messages_today" "messages_today" "$BODY"
assert_contains "Has delivery_rate" "delivery_rate" "$BODY"
assert_contains "Has instances count" "instances" "$BODY"
assert_contains "Has daily array" "daily" "$BODY"
assert_contains "Has max_instances" "max_instances" "$BODY"

# --- User dashboard method check ---
STATUS=$(get_status "$BASE/api/user/dashboard" "POST" "$USER1_TOKEN")
assert_status "User dashboard POST -> 405" "405" "$STATUS"

# --- Admin dashboard ---
BODY=$(do_get "$BASE/admin/dashboard" "$ADMIN_TOKEN")
STATUS=$(get_status "$BASE/admin/dashboard" "GET" "$ADMIN_TOKEN")
assert_status "Admin dashboard -> 200" "200" "$STATUS"
assert_contains "Has users.total" "total" "$BODY"
assert_contains "Has instances section" "total_registered" "$BODY"

# --- Normal user cannot access admin dashboard ---
STATUS=$(get_status "$BASE/admin/dashboard" "GET" "$USER1_TOKEN")
assert_status "Normal user cannot access admin dashboard -> 403" "403" "$STATUS"

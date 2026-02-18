#!/bin/bash
# ============================================
# 14. Audit log (admin)
# ============================================

print_section "14. AUDIT LOG"

# --- Normal user cannot access ---
STATUS=$(get_status "$BASE/admin/audit" "GET" "$USER1_TOKEN")
assert_status "Normal user cannot access audit -> 403" "403" "$STATUS"

# --- List audit logs ---
BODY=$(do_get "$BASE/admin/audit" "$ADMIN_TOKEN")
assert_contains "Audit has logs array" "logs" "$BODY"
assert_contains "Audit has total" "total" "$BODY"
assert_contains "Audit has pagination" "pages" "$BODY"

# --- Filter by action ---
BODY=$(do_get "$BASE/admin/audit?action=user_created" "$ADMIN_TOKEN")
assert_json_count "Filter user_created has results" ".logs" 1 "$BODY"

# --- Filter by username ---
BODY=$(do_get "$BASE/admin/audit?username=admin" "$ADMIN_TOKEN")
assert_json_count "Filter by admin username has results" ".logs" 1 "$BODY"

# --- Filter by resource_type ---
BODY=$(do_get "$BASE/admin/audit?resource_type=user" "$ADMIN_TOKEN")
assert_json_count "Filter resource_type=user" ".logs" 1 "$BODY"

# --- Method check ---
STATUS=$(get_status "$BASE/admin/audit" "POST" "$ADMIN_TOKEN")
assert_status "Audit POST -> 405" "405" "$STATUS"

# --- Previous test actions appear in audit ---
BODY=$(do_get "$BASE/admin/audit?limit=100" "$ADMIN_TOKEN")
assert_contains "Audit contains user_created action" "user_created" "$BODY"

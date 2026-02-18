#!/bin/bash
# ============================================
# 13. Maintenance windows CRUD (admin)
# ============================================

print_section "13. MAINTENANCE"

# --- Normal user cannot access ---
STATUS=$(get_status "$BASE/admin/maintenance" "GET" "$USER1_TOKEN")
assert_status "Normal user cannot access maintenance -> 403" "403" "$STATUS"

# --- Create maintenance ---
BODY=$(do_post "$BASE/admin/maintenance" \
    '{"title":"CI Test Maintenance","scheduled_start":"2099-06-01T02:00:00","scheduled_end":"2099-06-01T06:00:00","description":"CI test window","service_ids":[1,2]}' \
    "$ADMIN_TOKEN")
MAINT_ID=$(json_val "$BODY" '.maintenance.id')
assert_json_field "Maintenance status" ".maintenance.status" "scheduled" "$BODY"
assert_contains "Maintenance title" "CI Test Maintenance" "$BODY"

# --- Validation: missing fields ---
STATUS=$(get_status "$BASE/admin/maintenance" "POST" "$ADMIN_TOKEN" '{"title":"no dates"}')
assert_status "Maintenance without dates -> 400" "400" "$STATUS"

# --- List maintenances ---
BODY=$(do_get "$BASE/admin/maintenance" "$ADMIN_TOKEN")
assert_contains "List includes CI maintenance" "CI Test Maintenance" "$BODY"
assert_contains "Includes affected_services" "affected_services" "$BODY"

# --- Update maintenance ---
BODY=$(do_put "$BASE/admin/maintenance/$MAINT_ID" \
    '{"status":"in_progress"}' "$ADMIN_TOKEN")
assert_json_field "Update status to in_progress" ".maintenance.status" "in_progress" "$BODY"

BODY=$(do_put "$BASE/admin/maintenance/$MAINT_ID" \
    '{"title":"CI Maintenance Updated","description":"Updated desc"}' "$ADMIN_TOKEN")
assert_json_field "Update title" ".maintenance.title" "CI Maintenance Updated" "$BODY"

# --- Maintenance visible in public status ---
BODY=$(do_get "$BASE/api/status")
assert_contains "Maintenance in public status" "scheduled_maintenances" "$BODY"

# --- Update services only ---
BODY=$(do_put "$BASE/admin/maintenance/$MAINT_ID" '{"service_ids":[1]}' "$ADMIN_TOKEN")
assert_contains "Update services" "Services updated" "$BODY"

# --- Delete maintenance (cascade) ---
BODY=$(do_delete "$BASE/admin/maintenance/$MAINT_ID" "$ADMIN_TOKEN")
assert_contains "Delete maintenance" "deleted" "$BODY"

STATUS=$(get_status "$BASE/admin/maintenance/99999" "DELETE" "$ADMIN_TOKEN")
assert_status "Delete nonexistent maintenance -> 404" "404" "$STATUS"

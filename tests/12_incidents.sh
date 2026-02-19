#!/bin/bash
# ============================================
# 12. Incidents CRUD (admin)
# ============================================

print_section "12. INCIDENTS"

# --- Normal user cannot access ---
STATUS=$(get_status "$BASE/admin/incidents" "GET" "$USER1_TOKEN")
assert_status "Normal user cannot access incidents -> 403" "403" "$STATUS"

# --- List services ---
BODY=$(do_get "$BASE/admin/incidents/services" "$ADMIN_TOKEN")
assert_json_count "At least 4 services" ".services" 4 "$BODY"

# --- Create incident ---
BODY=$(do_post "$BASE/admin/incidents" \
    '{"title":"CI Test Incident","severity":"minor","message":"Investigating CI issue","service_ids":[1]}' \
    "$ADMIN_TOKEN")
INC_ID=$(json_val "$BODY" '.incident.id')
assert_json_field "Incident severity" ".incident.severity" "minor" "$BODY"
assert_json_field "Incident status" ".incident.status" "investigating" "$BODY"

# --- Validation: missing fields ---
STATUS=$(get_status "$BASE/admin/incidents" "POST" "$ADMIN_TOKEN" '{"title":"no severity"}')
assert_status "Incident without severity -> 400" "400" "$STATUS"

STATUS=$(get_status "$BASE/admin/incidents" "POST" "$ADMIN_TOKEN" \
    '{"title":"no message","severity":"minor"}')
assert_status "Incident without message -> 400" "400" "$STATUS"

# --- List incidents (paginated) ---
BODY=$(do_get "$BASE/admin/incidents" "$ADMIN_TOKEN")
assert_contains "List includes CI test incident" "CI Test Incident" "$BODY"
assert_contains "Includes affected_services" "affected_services" "$BODY"
assert_contains "Includes updates timeline" "updates" "$BODY"
assert_json_field "Incidents has page field" ".page" "1" "$BODY"
assert_contains "Incidents has total field" '"total"' "$BODY"

# --- Add update to timeline ---
BODY=$(do_post "$BASE/admin/incidents/$INC_ID/updates" \
    '{"status":"monitoring","message":"CI monitoring update"}' "$ADMIN_TOKEN")
assert_json_field "Update status" ".update.status" "monitoring" "$BODY"

# --- Update incident ---
BODY=$(do_put "$BASE/admin/incidents/$INC_ID" \
    '{"title":"CI Test Incident Updated","severity":"major"}' "$ADMIN_TOKEN")
assert_json_field "Updated title" ".incident.title" "CI Test Incident Updated" "$BODY"
assert_json_field "Updated severity" ".incident.severity" "major" "$BODY"

# --- Resolve incident ---
BODY=$(do_post "$BASE/admin/incidents/$INC_ID/updates" \
    '{"status":"resolved","message":"CI issue resolved"}' "$ADMIN_TOKEN")
assert_json_field "Resolve status" ".update.status" "resolved" "$BODY"

# Verify resolved_at is set
BODY=$(do_get "$BASE/admin/incidents" "$ADMIN_TOKEN")
RESOLVED_AT=$(echo "$BODY" | jq -r '.incidents[] | select(.id=='"$INC_ID"') | .resolved_at')
TOTAL=$((TOTAL + 1))
if [ -n "$RESOLVED_AT" ] && [ "$RESOLVED_AT" != "null" ]; then
    echo -e "  ${GREEN}PASS${NC} Resolved incident has resolved_at"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} Resolved incident missing resolved_at"
    FAIL=$((FAIL + 1))
fi

# --- Incident visible in public status ---
# Create a new active incident for status check
BODY=$(do_post "$BASE/admin/incidents" \
    '{"title":"CI Active Incident","severity":"critical","message":"Testing status visibility","service_ids":[1]}' \
    "$ADMIN_TOKEN")
INC2_ID=$(json_val "$BODY" '.incident.id')

BODY=$(do_get "$BASE/api/status")
assert_contains "Active incident in public status" "CI Active Incident" "$BODY"

# --- Delete incident (cascade) ---
BODY=$(do_delete "$BASE/admin/incidents/$INC_ID" "$ADMIN_TOKEN")
assert_contains "Delete incident" "deleted" "$BODY"

STATUS=$(get_status "$BASE/admin/incidents/99999" "DELETE" "$ADMIN_TOKEN")
assert_status "Delete nonexistent incident -> 404" "404" "$STATUS"

# Cleanup second incident
do_delete "$BASE/admin/incidents/$INC2_ID" "$ADMIN_TOKEN" > /dev/null 2>&1

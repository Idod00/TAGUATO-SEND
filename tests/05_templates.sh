#!/bin/bash
# ============================================
# 05. Templates CRUD (user-scoped)
# ============================================

print_section "05. TEMPLATES"

# --- Empty list ---
BODY=$(do_get "$BASE/api/templates" "$USER1_TOKEN")
assert_json_field "User1 templates initially empty" ".templates | length" "0" "$BODY"

# --- Create template ---
BODY=$(do_post "$BASE/api/templates" \
    '{"name":"ci-test-tpl1","content":"Hello {{name}}!"}' "$USER1_TOKEN")
assert_status "Create template -> 201" "201" \
    "$(get_status "$BASE/api/templates" "POST" "$USER1_TOKEN" '{"name":"ci-test-tpl2","content":"Bye {{name}}"}')"
TPL1_ID=$(json_val "$BODY" '.template.id')
assert_json_field "Template name" ".template.name" "ci-test-tpl1" "$BODY"

# Capture second template ID
BODY=$(do_get "$BASE/api/templates" "$USER1_TOKEN")
TPL2_ID=$(echo "$BODY" | jq -r '.templates[] | select(.name=="ci-test-tpl2") | .id')

# --- Validation: missing fields ---
STATUS=$(get_status "$BASE/api/templates" "POST" "$USER1_TOKEN" '{"name":"only-name"}')
assert_status "Template without content -> 400" "400" "$STATUS"

STATUS=$(get_status "$BASE/api/templates" "POST" "$USER1_TOKEN" '{"content":"only-content"}')
assert_status "Template without name -> 400" "400" "$STATUS"

# --- Validation: name too long ---
LONG_NAME=$(printf 'x%.0s' $(seq 1 101))
STATUS=$(get_status "$BASE/api/templates" "POST" "$USER1_TOKEN" \
    '{"name":"'"$LONG_NAME"'","content":"test"}')
assert_status "Name > 100 chars -> 400" "400" "$STATUS"

# --- Update template ---
BODY=$(do_put "$BASE/api/templates/$TPL1_ID" \
    '{"content":"Updated content for {{name}}"}' "$USER1_TOKEN")
assert_json_field "Update template content" ".template.content" "Updated content for {{name}}" "$BODY"

# --- Isolation: User2 cannot see User1 templates ---
BODY=$(do_get "$BASE/api/templates" "$USER2_TOKEN")
assert_not_contains "User2 cannot see User1 templates" "ci-test-tpl1" "$BODY"

# --- Isolation: User2 cannot update User1 template ---
STATUS=$(get_status "$BASE/api/templates/$TPL1_ID" "PUT" "$USER2_TOKEN" '{"name":"hacked"}')
assert_status "User2 cannot update User1 template -> 404" "404" "$STATUS"

# --- Isolation: User2 cannot delete User1 template ---
STATUS=$(get_status "$BASE/api/templates/$TPL1_ID" "DELETE" "$USER2_TOKEN")
assert_status "User2 cannot delete User1 template -> 404" "404" "$STATUS"

# --- Delete template ---
BODY=$(do_delete "$BASE/api/templates/$TPL1_ID" "$USER1_TOKEN")
assert_contains "Delete template" "deleted" "$BODY"

# Cleanup second template
do_delete "$BASE/api/templates/$TPL2_ID" "$USER1_TOKEN" > /dev/null 2>&1

#!/bin/bash
# ============================================
# 06. Contact lists + items CRUD (user-scoped)
# ============================================

print_section "06. CONTACTS"

# --- Empty list ---
BODY=$(do_get "$BASE/api/contacts" "$USER1_TOKEN")
assert_json_field "User1 contacts initially empty" ".lists | length" "0" "$BODY"

# --- Create list ---
BODY=$(do_post "$BASE/api/contacts" '{"name":"ci-test-list1"}' "$USER1_TOKEN")
assert_contains "Create contact list" "ci-test-list1" "$BODY"
LIST1_ID=$(json_val "$BODY" '.list.id')

# --- Create second list ---
BODY=$(do_post "$BASE/api/contacts" '{"name":"ci-test-list2"}' "$USER1_TOKEN")
LIST2_ID=$(json_val "$BODY" '.list.id')

# --- List all ---
BODY=$(do_get "$BASE/api/contacts" "$USER1_TOKEN")
assert_json_count "User1 has 2 lists" ".lists" 2 "$BODY"

# --- Get detail ---
BODY=$(do_get "$BASE/api/contacts/$LIST1_ID" "$USER1_TOKEN")
assert_json_field "List detail name" ".list.name" "ci-test-list1" "$BODY"
assert_contains "Detail includes items field" "items" "$BODY"

# --- Update list name ---
BODY=$(do_put "$BASE/api/contacts/$LIST1_ID" '{"name":"ci-test-list1-updated"}' "$USER1_TOKEN")
assert_json_field "Update list name" ".list.name" "ci-test-list1-updated" "$BODY"

# --- Validation: create without name ---
STATUS=$(get_status "$BASE/api/contacts" "POST" "$USER1_TOKEN" '{}')
assert_status "Create list without name -> 400" "400" "$STATUS"

# --- Add single item ---
BODY=$(do_post "$BASE/api/contacts/$LIST1_ID/items" \
    '{"phone_number":"59512345678","label":"Contact1"}' "$USER1_TOKEN")
assert_contains "Add single item" "59512345678" "$BODY"
ITEM1_ID=$(json_val "$BODY" '.items[0].id')

# --- Add multiple items ---
BODY=$(do_post "$BASE/api/contacts/$LIST1_ID/items" \
    '{"items":[{"phone_number":"59587654321","label":"Contact2"},{"phone_number":"59500001111","label":"Contact3"}]}' \
    "$USER1_TOKEN")
assert_json_count "Add multiple items (2)" ".items" 2 "$BODY"

# --- Phone validation: too short ---
STATUS=$(get_status "$BASE/api/contacts/$LIST1_ID/items" "POST" "$USER1_TOKEN" \
    '{"phone_number":"1234567","label":"short"}')
assert_status "Phone < 8 digits -> 400" "400" "$STATUS"

# --- Phone validation: too long ---
LONG_PHONE="123456789012345678901"
STATUS=$(get_status "$BASE/api/contacts/$LIST1_ID/items" "POST" "$USER1_TOKEN" \
    '{"phone_number":"'"$LONG_PHONE"'","label":"long"}')
assert_status "Phone > 20 digits -> 400" "400" "$STATUS"

# --- Phone validation: letters ---
STATUS=$(get_status "$BASE/api/contacts/$LIST1_ID/items" "POST" "$USER1_TOKEN" \
    '{"phone_number":"5951234abcd","label":"letters"}')
assert_status "Phone with letters -> 400" "400" "$STATUS"

# --- Delete item ---
BODY=$(do_delete "$BASE/api/contacts/$LIST1_ID/items/$ITEM1_ID" "$USER1_TOKEN")
assert_contains "Delete item" "deleted" "$BODY"

# --- Isolation: User2 cannot see User1 lists ---
BODY=$(do_get "$BASE/api/contacts" "$USER2_TOKEN")
assert_not_contains "User2 cannot see User1 lists" "ci-test-list" "$BODY"

# --- Isolation: User2 cannot access User1 list detail ---
STATUS=$(get_status "$BASE/api/contacts/$LIST1_ID" "GET" "$USER2_TOKEN")
assert_status "User2 cannot access User1 list -> 404" "404" "$STATUS"

# --- Isolation: User2 cannot add items to User1 list ---
STATUS=$(get_status "$BASE/api/contacts/$LIST1_ID/items" "POST" "$USER2_TOKEN" \
    '{"phone_number":"59500000000","label":"hacked"}')
assert_status "User2 cannot add to User1 list -> 404" "404" "$STATUS"

# --- Cascade delete ---
BODY=$(do_delete "$BASE/api/contacts/$LIST1_ID" "$USER1_TOKEN")
assert_contains "Delete list cascades" "deleted" "$BODY"

# Cleanup
do_delete "$BASE/api/contacts/$LIST2_ID" "$USER1_TOKEN" > /dev/null 2>&1

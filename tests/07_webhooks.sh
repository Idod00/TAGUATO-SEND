#!/bin/bash
# ============================================
# 07. Webhooks CRUD (user-scoped)
# ============================================

print_section "07. WEBHOOKS"

# --- Empty list ---
BODY=$(do_get "$BASE/api/webhooks" "$USER1_TOKEN")
assert_json_field "User1 webhooks initially empty" ".webhooks | length" "0" "$BODY"

# --- Validation: missing fields ---
STATUS=$(get_status "$BASE/api/webhooks" "POST" "$USER1_TOKEN" '{}')
assert_status "Webhook without instance_name -> 400" "400" "$STATUS"

STATUS=$(get_status "$BASE/api/webhooks" "POST" "$USER1_TOKEN" \
    '{"instance_name":"ci-test-u1a"}')
assert_status "Webhook without webhook_url -> 400" "400" "$STATUS"

STATUS=$(get_status "$BASE/api/webhooks" "POST" "$USER1_TOKEN" \
    '{"instance_name":"ci-test-u1a","webhook_url":"not-a-url"}')
assert_status "Webhook URL without http -> 400" "400" "$STATUS"

# --- Ownership: cannot create for other's instance ---
STATUS=$(get_status "$BASE/api/webhooks" "POST" "$USER1_TOKEN" \
    '{"instance_name":"ci-test-u2a","webhook_url":"https://example.com/hook"}')
assert_status "Webhook for other's instance -> 403" "403" "$STATUS"

# --- Create webhook ---
BODY=$(do_post "$BASE/api/webhooks" \
    '{"instance_name":"ci-test-u1a","webhook_url":"https://example.com/hook1","events":["MESSAGE"]}' \
    "$USER1_TOKEN")
WH1_ID=$(json_val "$BODY" '.webhook.id')
assert_contains "Create webhook" "ci-test-u1a" "$BODY"

# --- Duplicate webhook ---
STATUS=$(get_status "$BASE/api/webhooks" "POST" "$USER1_TOKEN" \
    '{"instance_name":"ci-test-u1a","webhook_url":"https://example.com/hook2"}')
assert_status "Duplicate webhook for same instance -> 409" "409" "$STATUS"

# --- List webhooks ---
BODY=$(do_get "$BASE/api/webhooks" "$USER1_TOKEN")
assert_json_count "User1 has 1 webhook" ".webhooks" 1 "$BODY"

# --- Admin can create for any instance ---
BODY=$(do_post "$BASE/api/webhooks" \
    '{"instance_name":"ci-test-u2a","webhook_url":"https://example.com/admin-hook"}' \
    "$ADMIN_TOKEN")
ADMIN_WH_ID=$(json_val "$BODY" '.webhook.id')
assert_contains "Admin creates webhook for User2 instance" "ci-test-u2a" "$BODY"

# --- PUT: Update webhook URL ---
BODY=$(do_put "$BASE/api/webhooks/$WH1_ID" \
    '{"webhook_url":"https://example.com/hook-updated"}' "$USER1_TOKEN")
assert_json_field "Update webhook URL" ".webhook.webhook_url" "https://example.com/hook-updated" "$BODY"

# --- PUT: Update webhook events ---
BODY=$(do_put "$BASE/api/webhooks/$WH1_ID" \
    '{"events":["MESSAGES_UPSERT","CONNECTION_UPDATE"]}' "$USER1_TOKEN")
assert_contains "Update webhook events" "MESSAGES_UPSERT" "$BODY"

# --- PUT: Invalid URL ---
STATUS=$(get_status "$BASE/api/webhooks/$WH1_ID" "PUT" "$USER1_TOKEN" \
    '{"webhook_url":"not-a-url"}')
assert_status "PUT invalid webhook URL -> 400" "400" "$STATUS"

# --- PUT: Invalid events ---
STATUS=$(get_status "$BASE/api/webhooks/$WH1_ID" "PUT" "$USER1_TOKEN" \
    '{"events":["INVALID_EVENT"]}')
assert_status "PUT invalid event -> 400" "400" "$STATUS"

# --- PUT: Reactivate webhook (resets retry_count) ---
BODY=$(do_put "$BASE/api/webhooks/$WH1_ID" '{"is_active":true}' "$USER1_TOKEN")
assert_json_field "Reactivate webhook" ".webhook.is_active" "true" "$BODY"
assert_json_field "Reactivate resets retry_count" ".webhook.retry_count" "0" "$BODY"

# --- PUT: Other user's webhook -> 404 ---
STATUS=$(get_status "$BASE/api/webhooks/$WH1_ID" "PUT" "$USER2_TOKEN" \
    '{"webhook_url":"https://example.com/hacked"}')
assert_status "PUT other user webhook -> 404" "404" "$STATUS"

# --- Delete webhook ---
BODY=$(do_delete "$BASE/api/webhooks/$WH1_ID" "$USER1_TOKEN")
assert_contains "Delete webhook" "deleted" "$BODY"

# Cleanup admin webhook
if [ -n "$ADMIN_WH_ID" ] && [ "$ADMIN_WH_ID" != "null" ]; then
    # Admin webhooks have user_id of admin, so admin deletes
    do_delete "$BASE/api/webhooks/$ADMIN_WH_ID" "$ADMIN_TOKEN" > /dev/null 2>&1
fi

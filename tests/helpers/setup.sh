#!/bin/bash
# ============================================
# TAGUATO-SEND — Test data setup
# ============================================
# Creates test users and exports tokens/IDs.
# Requires: ADMIN_TOKEN, BASE, common.sh sourced.

print_section "SETUP: Creating test users"

CI_PASSWORD="CiTestPass1"

# Create ci_user1 (max_instances=3)
BODY=$(do_post "$BASE/admin/users" \
    '{"username":"ci_user1","password":"'"$CI_PASSWORD"'","max_instances":3}' \
    "$ADMIN_TOKEN")
USER1_TOKEN=$(json_val "$BODY" '.user.api_token')
USER1_ID=$(json_val "$BODY" '.user.id')
if [ -z "$USER1_TOKEN" ] || [ "$USER1_TOKEN" = "null" ]; then
    echo -e "  ${RED}ERROR${NC} Failed to create ci_user1: $BODY"
    exit 1
fi
echo -e "  ${GREEN}OK${NC} ci_user1 ID=$USER1_ID"

# Create ci_user2 (max_instances=2, rate_limit=100)
BODY=$(do_post "$BASE/admin/users" \
    '{"username":"ci_user2","password":"'"$CI_PASSWORD"'","max_instances":2,"rate_limit":100}' \
    "$ADMIN_TOKEN")
USER2_TOKEN=$(json_val "$BODY" '.user.api_token')
USER2_ID=$(json_val "$BODY" '.user.id')
if [ -z "$USER2_TOKEN" ] || [ "$USER2_TOKEN" = "null" ]; then
    echo -e "  ${RED}ERROR${NC} Failed to create ci_user2: $BODY"
    exit 1
fi
echo -e "  ${GREEN}OK${NC} ci_user2 ID=$USER2_ID"

# Create ci_user3 (max_instances=1)
BODY=$(do_post "$BASE/admin/users" \
    '{"username":"ci_user3","password":"'"$CI_PASSWORD"'","max_instances":1}' \
    "$ADMIN_TOKEN")
USER3_TOKEN=$(json_val "$BODY" '.user.api_token')
USER3_ID=$(json_val "$BODY" '.user.id')
if [ -z "$USER3_TOKEN" ] || [ "$USER3_TOKEN" = "null" ]; then
    echo -e "  ${RED}ERROR${NC} Failed to create ci_user3: $BODY"
    exit 1
fi
echo -e "  ${GREEN}OK${NC} ci_user3 ID=$USER3_ID"

export USER1_TOKEN USER1_ID USER2_TOKEN USER2_ID USER3_TOKEN USER3_ID CI_PASSWORD

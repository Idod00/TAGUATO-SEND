#!/bin/bash
# ============================================
# TAGUATO-SEND — Test data teardown
# ============================================
# Cleans all ci-test-* data in reverse order (FK safe).
# Called via trap EXIT in run_all.sh.

echo ""
echo -e "${YELLOW}TEARDOWN: Cleaning test data${NC}"

# 1. Delete instances with ci-test- prefix (via admin)
for inst in $(do_get "$BASE/instance/fetchInstances" "$ADMIN_TOKEN" | jq -r '.[]?.instance?.instanceName // empty' 2>/dev/null | grep '^ci-test-'); do
    curl -s -X DELETE -H "apikey: $ADMIN_TOKEN" "$BASE/instance/delete/$inst" > /dev/null 2>&1
done
echo -e "  ${GREEN}OK${NC} Instances cleaned"

# 2. Delete test users (ci_user1, ci_user2, ci_user3)
for uid in $USER1_ID $USER2_ID $USER3_ID; do
    if [ -n "$uid" ] && [ "$uid" != "null" ]; then
        curl -s -X DELETE "$BASE/admin/users/$uid" -H "apikey: $ADMIN_TOKEN" > /dev/null 2>&1
    fi
done
echo -e "  ${GREEN}OK${NC} Users cleaned"

# 3. Brute-force lockout user (ci_brute_user)
BRUTE_ID=$(do_get "$BASE/admin/users" "$ADMIN_TOKEN" | jq -r '.users[] | select(.username=="ci_brute_user") | .id' 2>/dev/null)
if [ -n "$BRUTE_ID" ] && [ "$BRUTE_ID" != "null" ]; then
    curl -s -X DELETE "$BASE/admin/users/$BRUTE_ID" -H "apikey: $ADMIN_TOKEN" > /dev/null 2>&1
fi
echo -e "  ${GREEN}OK${NC} Brute-force user cleaned"

echo -e "  ${GREEN}OK${NC} Teardown complete"

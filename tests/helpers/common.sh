#!/bin/bash
# ============================================
# TAGUATO-SEND — Shared test helpers
# ============================================

BASE="${BASE:-http://localhost}"
PASS=0
FAIL=0
TOTAL=0
SKIP=0

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m'

# ---- Assertion helpers ----

assert_status() {
    local desc="$1"
    local expected="$2"
    local actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$actual" = "$expected" ]; then
        echo -e "  ${GREEN}PASS${NC} [$actual] $desc"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} [$actual != $expected] $desc"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local desc="$1"
    local expected="$2"
    local body="$3"
    TOTAL=$((TOTAL + 1))
    if echo "$body" | grep -q "$expected"; then
        echo -e "  ${GREEN}PASS${NC} $desc"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} $desc (expected '$expected')"
        echo -e "       ${DIM}Response: ${body:0:200}${NC}"
        FAIL=$((FAIL + 1))
    fi
}

assert_not_contains() {
    local desc="$1"
    local unexpected="$2"
    local body="$3"
    TOTAL=$((TOTAL + 1))
    if echo "$body" | grep -q "$unexpected"; then
        echo -e "  ${RED}FAIL${NC} $desc (found '$unexpected')"
        echo -e "       ${DIM}Response: ${body:0:200}${NC}"
        FAIL=$((FAIL + 1))
    else
        echo -e "  ${GREEN}PASS${NC} $desc"
        PASS=$((PASS + 1))
    fi
}

assert_json_field() {
    local desc="$1"
    local jq_path="$2"
    local expected="$3"
    local body="$4"
    TOTAL=$((TOTAL + 1))
    local actual
    actual=$(echo "$body" | jq -r "$jq_path" 2>/dev/null)
    if [ "$actual" = "$expected" ]; then
        echo -e "  ${GREEN}PASS${NC} $desc"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} $desc ($jq_path = '$actual', expected '$expected')"
        FAIL=$((FAIL + 1))
    fi
}

assert_json_count() {
    local desc="$1"
    local jq_array="$2"
    local min_count="$3"
    local body="$4"
    TOTAL=$((TOTAL + 1))
    local count
    count=$(echo "$body" | jq "$jq_array | length" 2>/dev/null)
    if [ -z "$count" ] || [ "$count" = "null" ]; then count=0; fi
    if [ "$count" -ge "$min_count" ]; then
        echo -e "  ${GREEN}PASS${NC} $desc (count=$count >= $min_count)"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} $desc (count=$count < $min_count)"
        FAIL=$((FAIL + 1))
    fi
}

assert_header() {
    local desc="$1"
    local header_name="$2"
    local expected_value="$3"
    local headers="$4"
    TOTAL=$((TOTAL + 1))
    local actual
    actual=$(echo "$headers" | grep -i "^${header_name}:" | sed "s/^[^:]*: //" | tr -d '\r')
    if [ -z "$expected_value" ]; then
        # Just check header exists
        if [ -n "$actual" ]; then
            echo -e "  ${GREEN}PASS${NC} $desc (present)"
            PASS=$((PASS + 1))
        else
            echo -e "  ${RED}FAIL${NC} $desc (header '$header_name' missing)"
            FAIL=$((FAIL + 1))
        fi
    else
        if [ "$actual" = "$expected_value" ]; then
            echo -e "  ${GREEN}PASS${NC} $desc"
            PASS=$((PASS + 1))
        else
            echo -e "  ${RED}FAIL${NC} $desc ('$actual' != '$expected_value')"
            FAIL=$((FAIL + 1))
        fi
    fi
}

skip_test() {
    local desc="$1"
    local reason="${2:-}"
    TOTAL=$((TOTAL + 1))
    SKIP=$((SKIP + 1))
    echo -e "  ${YELLOW}SKIP${NC} $desc ($reason)"
}

# ---- HTTP helpers ----

do_get() {
    local url="$1"
    local apikey="${2:-}"
    if [ -n "$apikey" ]; then
        curl -s -H "apikey: $apikey" "$url"
    else
        curl -s "$url"
    fi
}

do_post() {
    local url="$1"
    local json_body="$2"
    local apikey="${3:-}"
    if [ -n "$apikey" ]; then
        curl -s -X POST "$url" -H "apikey: $apikey" -H "Content-Type: application/json" -d "$json_body"
    else
        curl -s -X POST "$url" -H "Content-Type: application/json" -d "$json_body"
    fi
}

do_put() {
    local url="$1"
    local json_body="$2"
    local apikey="${3:-}"
    if [ -n "$apikey" ]; then
        curl -s -X PUT "$url" -H "apikey: $apikey" -H "Content-Type: application/json" -d "$json_body"
    else
        curl -s -X PUT "$url" -H "Content-Type: application/json" -d "$json_body"
    fi
}

do_delete() {
    local url="$1"
    local apikey="${2:-}"
    if [ -n "$apikey" ]; then
        curl -s -X DELETE "$url" -H "apikey: $apikey"
    else
        curl -s -X DELETE "$url"
    fi
}

get_status() {
    local url="$1"
    local method="${2:-GET}"
    local apikey="${3:-}"
    local body="${4:-}"
    local args=(-s -o /dev/null -w '%{http_code}')
    if [ "$method" != "GET" ]; then args+=(-X "$method"); fi
    if [ -n "$apikey" ]; then args+=(-H "apikey: $apikey"); fi
    if [ -n "$body" ]; then args+=(-H "Content-Type: application/json" -d "$body"); fi
    curl "${args[@]}" "$url"
}

get_headers() {
    local url="$1"
    local apikey="${2:-}"
    if [ -n "$apikey" ]; then
        curl -s -I -H "apikey: $apikey" "$url"
    else
        curl -s -I "$url"
    fi
}

json_val() {
    local body="$1"
    local jq_path="$2"
    echo "$body" | jq -r "$jq_path" 2>/dev/null
}

# ---- Display helpers ----

print_section() {
    echo ""
    echo -e "${YELLOW}$1${NC}"
}

print_results() {
    echo ""
    echo -e "${CYAN}============================================${NC}"
    echo -e "${CYAN} RESULTS${NC}"
    echo -e "${CYAN}============================================${NC}"
    echo ""
    echo -e "  Total:   $TOTAL"
    echo -e "  ${GREEN}Pass:    $PASS${NC}"
    if [ "$FAIL" -gt 0 ]; then
        echo -e "  ${RED}Fail:    $FAIL${NC}"
    else
        echo -e "  Fail:    0"
    fi
    if [ "$SKIP" -gt 0 ]; then
        echo -e "  ${YELLOW}Skip:    $SKIP${NC}"
    fi
    echo ""
    if [ "$FAIL" -eq 0 ]; then
        echo -e "  ${GREEN}ALL TESTS PASSED${NC}"
    else
        echo -e "  ${RED}THERE ARE FAILING TESTS${NC}"
    fi
    echo ""
    return "$FAIL"
}

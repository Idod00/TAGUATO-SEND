#!/bin/bash
# ============================================
# TAGUATO-SEND - Test Completo del Sistema
# ============================================
set -uo pipefail

BASE="http://localhost"
ADMIN_TOKEN="${ADMIN_TOKEN:-$(grep '^ADMIN_TOKEN=' .env 2>/dev/null | cut -d= -f2)}"
if [ -z "$ADMIN_TOKEN" ]; then
    echo "ERROR: ADMIN_TOKEN not set. Export it or add ADMIN_TOKEN=<token> to .env"
    exit 1
fi
PASS=0
FAIL=0
TOTAL=0
SKIP=0

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

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
        echo -e "  ${RED}FAIL${NC} $desc (esperaba '$expected' en respuesta)"
        echo "       Respuesta: $body"
        FAIL=$((FAIL + 1))
    fi
}

skip_test() {
    local desc="$1"
    TOTAL=$((TOTAL + 1))
    SKIP=$((SKIP + 1))
    echo -e "  ${YELLOW}SKIP${NC} $desc"
}

# Curl wrapper with timeout for proxied requests
api_curl() {
    curl -s --max-time 10 "$@"
}

echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN} TAGUATO-SEND - Test Completo del Sistema${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""

# ============================================
echo -e "${YELLOW}1. HEALTH CHECK${NC}"
# ============================================
STATUS=$(api_curl -o /dev/null -w '%{http_code}' "$BASE/health")
assert_status "GET /health responde 200" "200" "$STATUS"

BODY=$(api_curl "$BASE/health")
assert_contains "Respuesta contiene 'gateway'" "gateway" "$BODY"

# ============================================
echo ""
echo -e "${YELLOW}2. AUTENTICACION${NC}"
# ============================================
STATUS=$(api_curl -o /dev/null -w '%{http_code}' "$BASE/instance/fetchInstances")
assert_status "Sin apikey retorna 401" "401" "$STATUS"

BODY=$(api_curl "$BASE/instance/fetchInstances")
assert_contains "Mensaje: Missing apikey header" "Missing apikey" "$BODY"

STATUS=$(api_curl -o /dev/null -w '%{http_code}' -H "apikey: token_falso_12345" "$BASE/instance/fetchInstances")
assert_status "Token invalido retorna 401" "401" "$STATUS"

BODY=$(api_curl -H "apikey: token_falso_12345" "$BASE/instance/fetchInstances")
assert_contains "Mensaje: Invalid API token" "Invalid API token" "$BODY"

STATUS=$(api_curl -o /dev/null -w '%{http_code}' -H "apikey: $ADMIN_TOKEN" "$BASE/instance/fetchInstances")
assert_status "Token admin valido retorna 200" "200" "$STATUS"

# Check if Evolution API proxy is working (needed for instance tests)
PROXY_OK=false
if [ "$STATUS" = "200" ]; then
    PROXY_OK=true
fi

# ============================================
echo ""
echo -e "${YELLOW}3. ADMIN - CRUD DE USUARIOS${NC}"
# ============================================

# Cleanup: remove test users from previous runs (idempotent)
for uname in test_user1 test_user2; do
    EXISTING=$(api_curl "$BASE/admin/users" -H "apikey: $ADMIN_TOKEN" | \
        python3 -c "import sys,json; users=json.load(sys.stdin).get('users',[]); [print(u['id']) for u in users if u['username']=='$uname']" 2>/dev/null)
    if [ -n "$EXISTING" ]; then
        api_curl -X DELETE "$BASE/admin/users/$EXISTING" -H "apikey: $ADMIN_TOKEN" > /dev/null 2>&1
    fi
done

# 3a. Crear usuario normal
BODY=$(api_curl -X POST "$BASE/admin/users" \
  -H "apikey: $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"username":"test_user1","password":"TestPass123","max_instances":2}')
assert_contains "POST /admin/users crea usuario" "test_user1" "$BODY"
assert_contains "Respuesta incluye api_token" "api_token" "$BODY"
assert_contains "Role por defecto es 'user'" '"role":"user"' "$BODY"

USER1_TOKEN=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin)['user']['api_token'])" 2>/dev/null)
USER1_ID=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin)['user']['id'])" 2>/dev/null)
echo -e "       User1 ID=$USER1_ID Token=${USER1_TOKEN:0:16}..."

# 3b. Crear segundo usuario
BODY=$(api_curl -X POST "$BASE/admin/users" \
  -H "apikey: $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"username":"test_user2","password":"TestPass456","max_instances":2}')
assert_contains "Crear segundo usuario" "test_user2" "$BODY"

USER2_TOKEN=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin)['user']['api_token'])" 2>/dev/null)
USER2_ID=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin)['user']['id'])" 2>/dev/null)
echo -e "       User2 ID=$USER2_ID Token=${USER2_TOKEN:0:16}..."

# 3c. Crear usuario duplicado
STATUS=$(api_curl -o /dev/null -w '%{http_code}' -X POST "$BASE/admin/users" \
  -H "apikey: $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"username":"test_user1","password":"OtroPass789","max_instances":1}')
assert_status "Usuario duplicado retorna 409" "409" "$STATUS"

# 3d. Crear usuario sin campos requeridos
STATUS=$(api_curl -o /dev/null -w '%{http_code}' -X POST "$BASE/admin/users" \
  -H "apikey: $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"username":"incompleto"}')
assert_status "Usuario sin password retorna 400" "400" "$STATUS"

# 3e. Listar usuarios
BODY=$(api_curl "$BASE/admin/users" -H "apikey: $ADMIN_TOKEN")
assert_contains "GET /admin/users lista usuarios" "test_user1" "$BODY"
assert_contains "Lista incluye segundo usuario" "test_user2" "$BODY"
assert_contains "Lista incluye admin" '"role":"admin"' "$BODY"

# 3f. Ver usuario individual con instancias
BODY=$(api_curl "$BASE/admin/users/$USER1_ID" -H "apikey: $ADMIN_TOKEN")
assert_contains "GET /admin/users/{id} muestra usuario" "test_user1" "$BODY"
assert_contains "Incluye campo instances" "instances" "$BODY"

# 3g. Actualizar usuario
BODY=$(api_curl -X PUT "$BASE/admin/users/$USER1_ID" \
  -H "apikey: $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"max_instances":5}')
assert_contains "PUT /admin/users/{id} actualiza max_instances" '"max_instances":5' "$BODY"

# Restaurar max_instances a 2
api_curl -X PUT "$BASE/admin/users/$USER1_ID" \
  -H "apikey: $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"max_instances":2}' > /dev/null

# 3h. Usuario normal no puede acceder a admin
if [ -n "$USER1_TOKEN" ]; then
    STATUS=$(api_curl -o /dev/null -w '%{http_code}' "$BASE/admin/users" -H "apikey: $USER1_TOKEN")
    assert_status "Usuario normal no accede a /admin/ (403)" "403" "$STATUS"
else
    skip_test "Usuario normal no accede a /admin/ (403) - no token"
fi

# ============================================
# Instance tests require Evolution API proxy
# ============================================
if [ "$PROXY_OK" = "true" ] && [ -n "$USER1_TOKEN" ] && [ -n "$USER2_TOKEN" ]; then

echo ""
echo -e "${YELLOW}4. INSTANCIAS - CREAR${NC}"
# ============================================

# 4a. User1 crea instancia
BODY=$(api_curl -X POST "$BASE/instance/create" \
  -H "apikey: $USER1_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"instanceName":"test-inst-u1a","integration":"WHATSAPP-BAILEYS","qrcode":true}')
assert_contains "User1 crea instancia test-inst-u1a" "test-inst-u1a" "$BODY"

# 4b. User1 crea segunda instancia
BODY=$(api_curl -X POST "$BASE/instance/create" \
  -H "apikey: $USER1_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"instanceName":"test-inst-u1b","integration":"WHATSAPP-BAILEYS","qrcode":true}')
assert_contains "User1 crea segunda instancia test-inst-u1b" "test-inst-u1b" "$BODY"

# 4c. User1 intenta tercera instancia (limite=2)
STATUS=$(api_curl -o /dev/null -w '%{http_code}' -X POST "$BASE/instance/create" \
  -H "apikey: $USER1_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"instanceName":"test-inst-u1c","integration":"WHATSAPP-BAILEYS","qrcode":true}')
assert_status "User1 excede limite (403)" "403" "$STATUS"

BODY=$(api_curl -X POST "$BASE/instance/create" \
  -H "apikey: $USER1_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"instanceName":"test-inst-u1c","integration":"WHATSAPP-BAILEYS","qrcode":true}')
assert_contains "Mensaje: Instance limit reached" "Instance limit reached" "$BODY"

# 4d. User2 crea instancia
BODY=$(api_curl -X POST "$BASE/instance/create" \
  -H "apikey: $USER2_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"instanceName":"test-inst-u2a","integration":"WHATSAPP-BAILEYS","qrcode":true}')
assert_contains "User2 crea instancia test-inst-u2a" "test-inst-u2a" "$BODY"

# 4e. User2 intenta nombre ya tomado por User1
STATUS=$(api_curl -o /dev/null -w '%{http_code}' -X POST "$BASE/instance/create" \
  -H "apikey: $USER2_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"instanceName":"test-inst-u1a","integration":"WHATSAPP-BAILEYS","qrcode":true}')
assert_status "Nombre de instancia duplicado retorna 409" "409" "$STATUS"

# ============================================
echo ""
echo -e "${YELLOW}5. INSTANCIAS - FILTRADO (fetchInstances)${NC}"
# ============================================

# 5a. Admin ve todas las instancias
BODY=$(api_curl -H "apikey: $ADMIN_TOKEN" "$BASE/instance/fetchInstances")
assert_contains "Admin ve test-inst-u1a" "test-inst-u1a" "$BODY"
assert_contains "Admin ve test-inst-u1b" "test-inst-u1b" "$BODY"
assert_contains "Admin ve test-inst-u2a" "test-inst-u2a" "$BODY"

# 5b. User1 solo ve sus instancias
BODY=$(api_curl -H "apikey: $USER1_TOKEN" "$BASE/instance/fetchInstances")
assert_contains "User1 ve test-inst-u1a" "test-inst-u1a" "$BODY"
assert_contains "User1 ve test-inst-u1b" "test-inst-u1b" "$BODY"
TOTAL=$((TOTAL + 1))
if echo "$BODY" | grep -q "test-inst-u2a"; then
    echo -e "  ${RED}FAIL${NC} User1 NO debe ver test-inst-u2a"
    FAIL=$((FAIL + 1))
else
    echo -e "  ${GREEN}PASS${NC} User1 NO ve instancias de User2"
    PASS=$((PASS + 1))
fi

# 5c. User2 solo ve sus instancias
BODY=$(api_curl -H "apikey: $USER2_TOKEN" "$BASE/instance/fetchInstances")
assert_contains "User2 ve test-inst-u2a" "test-inst-u2a" "$BODY"
TOTAL=$((TOTAL + 1))
if echo "$BODY" | grep -q "test-inst-u1"; then
    echo -e "  ${RED}FAIL${NC} User2 NO debe ver instancias de User1"
    FAIL=$((FAIL + 1))
else
    echo -e "  ${GREEN}PASS${NC} User2 NO ve instancias de User1"
    PASS=$((PASS + 1))
fi

# ============================================
echo ""
echo -e "${YELLOW}6. INSTANCIAS - OWNERSHIP (operaciones)${NC}"
# ============================================

# 6a. User1 puede ver estado de su instancia
STATUS=$(api_curl -o /dev/null -w '%{http_code}' -H "apikey: $USER1_TOKEN" "$BASE/instance/connectionState/test-inst-u1a")
assert_status "User1 accede a su instancia (200)" "200" "$STATUS"

# 6b. User1 NO puede ver instancia de User2
STATUS=$(api_curl -o /dev/null -w '%{http_code}' -H "apikey: $USER1_TOKEN" "$BASE/instance/connectionState/test-inst-u2a")
assert_status "User1 no accede a instancia de User2 (403)" "403" "$STATUS"

BODY=$(api_curl -H "apikey: $USER1_TOKEN" "$BASE/instance/connectionState/test-inst-u2a")
assert_contains "Mensaje: You don't own this instance" "don't own" "$BODY"

# 6c. User2 NO puede ver instancia de User1
STATUS=$(api_curl -o /dev/null -w '%{http_code}' -H "apikey: $USER2_TOKEN" "$BASE/instance/connectionState/test-inst-u1a")
assert_status "User2 no accede a instancia de User1 (403)" "403" "$STATUS"

# 6d. Admin puede ver cualquier instancia
STATUS=$(api_curl -o /dev/null -w '%{http_code}' -H "apikey: $ADMIN_TOKEN" "$BASE/instance/connectionState/test-inst-u1a")
assert_status "Admin accede a instancia de User1 (200)" "200" "$STATUS"

STATUS=$(api_curl -o /dev/null -w '%{http_code}' -H "apikey: $ADMIN_TOKEN" "$BASE/instance/connectionState/test-inst-u2a")
assert_status "Admin accede a instancia de User2 (200)" "200" "$STATUS"

# 6e. User1 no puede borrar instancia de User2
STATUS=$(api_curl -o /dev/null -w '%{http_code}' -X DELETE -H "apikey: $USER1_TOKEN" "$BASE/instance/delete/test-inst-u2a")
assert_status "User1 no puede borrar instancia de User2 (403)" "403" "$STATUS"

# ============================================
echo ""
echo -e "${YELLOW}7. INSTANCIAS - ELIMINAR${NC}"
# ============================================

# 7a. User1 borra su instancia
BODY=$(api_curl -X DELETE -H "apikey: $USER1_TOKEN" "$BASE/instance/delete/test-inst-u1b")
assert_contains "User1 elimina test-inst-u1b" "Instance deleted" "$BODY"

# 7b. Verificar que User1 ahora puede crear otra (ya no excede limite)
BODY=$(api_curl -X POST "$BASE/instance/create" \
  -H "apikey: $USER1_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"instanceName":"test-inst-u1c","integration":"WHATSAPP-BAILEYS","qrcode":true}')
assert_contains "User1 crea nueva instancia tras borrar (slot liberado)" "test-inst-u1c" "$BODY"

# 7c. User2 borra su instancia
BODY=$(api_curl -X DELETE -H "apikey: $USER2_TOKEN" "$BASE/instance/delete/test-inst-u2a")
assert_contains "User2 elimina test-inst-u2a" "Instance deleted" "$BODY"

# ============================================
echo ""
echo -e "${YELLOW}8. ADMIN - DESACTIVAR USUARIO${NC}"
# ============================================

# 8a. Desactivar User1
api_curl -X PUT "$BASE/admin/users/$USER1_ID" \
  -H "apikey: $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"is_active":false}' > /dev/null

STATUS=$(api_curl -o /dev/null -w '%{http_code}' -H "apikey: $USER1_TOKEN" "$BASE/instance/fetchInstances")
assert_status "Usuario desactivado retorna 403" "403" "$STATUS"

BODY=$(api_curl -H "apikey: $USER1_TOKEN" "$BASE/instance/fetchInstances")
assert_contains "Mensaje: Account is disabled" "disabled" "$BODY"

# Reactivar
api_curl -X PUT "$BASE/admin/users/$USER1_ID" \
  -H "apikey: $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"is_active":true}' > /dev/null

STATUS=$(api_curl -o /dev/null -w '%{http_code}' -H "apikey: $USER1_TOKEN" "$BASE/instance/fetchInstances")
assert_status "Usuario reactivado puede acceder (200)" "200" "$STATUS"

else
    # Proxy not available or user tokens missing - skip instance tests
    echo ""
    echo -e "${YELLOW}4-8. INSTANCIAS (SKIPPED - Evolution API proxy no disponible)${NC}"
    for desc in \
        "User1 crea instancia test-inst-u1a" \
        "User1 crea segunda instancia test-inst-u1b" \
        "User1 excede limite (403)" \
        "Mensaje: Instance limit reached" \
        "User2 crea instancia test-inst-u2a" \
        "Nombre de instancia duplicado retorna 409" \
        "Admin ve test-inst-u1a" "Admin ve test-inst-u1b" "Admin ve test-inst-u2a" \
        "User1 ve test-inst-u1a" "User1 ve test-inst-u1b" "User1 NO ve instancias de User2" \
        "User2 ve test-inst-u2a" "User2 NO ve instancias de User1" \
        "User1 accede a su instancia (200)" \
        "User1 no accede a instancia de User2 (403)" \
        "Mensaje: You don't own this instance" \
        "User2 no accede a instancia de User1 (403)" \
        "Admin accede a instancia de User1 (200)" \
        "Admin accede a instancia de User2 (200)" \
        "User1 no puede borrar instancia de User2 (403)" \
        "User1 elimina test-inst-u1b" \
        "User1 crea nueva instancia tras borrar (slot liberado)" \
        "User2 elimina test-inst-u2a" \
        "Usuario desactivado retorna 403" \
        "Mensaje: Account is disabled" \
        "Usuario reactivado puede acceder (200)"; do
        skip_test "$desc"
    done
fi

# ============================================
echo ""
echo -e "${YELLOW}9. ADMIN - ELIMINAR USUARIO${NC}"
# ============================================

# 9a. Admin no puede eliminarse a si mismo
ADMIN_ID=$(api_curl "$BASE/admin/users" -H "apikey: $ADMIN_TOKEN" | \
    python3 -c "import sys,json; users=json.load(sys.stdin).get('users',[]); [print(u['id']) for u in users if u['role']=='admin']" 2>/dev/null | head -1)
STATUS=$(api_curl -o /dev/null -w '%{http_code}' -X DELETE "$BASE/admin/users/$ADMIN_ID" -H "apikey: $ADMIN_TOKEN")
assert_status "Admin no puede auto-eliminarse (400)" "400" "$STATUS"

# 9b. Eliminar User2
if [ -n "$USER2_ID" ]; then
    BODY=$(api_curl -X DELETE "$BASE/admin/users/$USER2_ID" -H "apikey: $ADMIN_TOKEN")
    assert_contains "DELETE /admin/users elimina User2" "test_user2" "$BODY"

    # 9c. Token de User2 ya no funciona
    if [ -n "$USER2_TOKEN" ]; then
        STATUS=$(api_curl -o /dev/null -w '%{http_code}' -H "apikey: $USER2_TOKEN" "$BASE/instance/fetchInstances")
        assert_status "Token de usuario eliminado retorna 401" "401" "$STATUS"
    else
        skip_test "Token de usuario eliminado retorna 401 - no token"
    fi
else
    skip_test "DELETE /admin/users elimina User2 - no user ID"
    skip_test "Token de usuario eliminado retorna 401 - no user ID"
fi

# ============================================
echo ""
echo -e "${YELLOW}10. ADMIN - VER INSTANCIAS DE USUARIO${NC}"
# ============================================

if [ -n "$USER1_ID" ]; then
    BODY=$(api_curl "$BASE/admin/users/$USER1_ID" -H "apikey: $ADMIN_TOKEN")
    if [ "$PROXY_OK" = "true" ]; then
        assert_contains "Admin ve instancias de User1" "test-inst-u1a" "$BODY"
        assert_contains "Admin ve segunda instancia de User1" "test-inst-u1c" "$BODY"
    else
        assert_contains "Admin ve datos de User1" "test_user1" "$BODY"
        skip_test "Admin ve instancias de User1 (proxy no disponible)"
    fi
else
    skip_test "Admin ve instancias de User1 - no user ID"
    skip_test "Admin ve segunda instancia de User1 - no user ID"
fi

# ============================================
echo ""
echo -e "${YELLOW}11. LIMPIEZA${NC}"
# ============================================

# Borrar instancias de prueba (usar admin para limpiar todo)
api_curl -X DELETE -H "apikey: $ADMIN_TOKEN" "$BASE/instance/delete/test-inst-u1a" > /dev/null 2>&1
api_curl -X DELETE -H "apikey: $ADMIN_TOKEN" "$BASE/instance/delete/test-inst-u1b" > /dev/null 2>&1
api_curl -X DELETE -H "apikey: $ADMIN_TOKEN" "$BASE/instance/delete/test-inst-u1c" > /dev/null 2>&1
api_curl -X DELETE -H "apikey: $ADMIN_TOKEN" "$BASE/instance/delete/test-inst-u2a" > /dev/null 2>&1

# Borrar usuarios de prueba
if [ -n "$USER1_ID" ]; then
    api_curl -X DELETE "$BASE/admin/users/$USER1_ID" -H "apikey: $ADMIN_TOKEN" > /dev/null 2>&1
fi

echo -e "  ${GREEN}OK${NC} Instancias y usuarios de prueba eliminados"

# ============================================
echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN} RESULTADOS${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""
echo -e "  Total:  $TOTAL"
echo -e "  ${GREEN}Pass:   $PASS${NC}"
if [ "$FAIL" -gt 0 ]; then
    echo -e "  ${RED}Fail:   $FAIL${NC}"
else
    echo -e "  Fail:   0"
fi
if [ "$SKIP" -gt 0 ]; then
    echo -e "  ${YELLOW}Skip:   $SKIP${NC}"
fi
echo ""
if [ "$FAIL" -eq 0 ]; then
    echo -e "  ${GREEN}TODOS LOS TESTS PASARON${NC}"
else
    echo -e "  ${RED}HAY TESTS FALLIDOS${NC}"
fi
echo ""
exit "$FAIL"

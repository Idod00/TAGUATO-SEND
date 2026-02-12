#!/usr/bin/env bash
set -euo pipefail

# ============================================
# TAGUATO-SEND - Universal Deployment Script
# Linux / macOS / WSL / Git Bash
# ============================================

REPO_URL="https://github.com/Idod00/TAGUATO-SEND.git"
REPO_DIR="TAGUATO-SEND"
HEALTH_TIMEOUT=180
UNATTENDED=false

# --- Parse flags ---
for arg in "$@"; do
    case "$arg" in
        --unattended|-y) UNATTENDED=true ;;
    esac
done

# ============================================
# Colors & helpers
# ============================================
if [ -t 1 ] && command -v tput &>/dev/null && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    RED=$(tput setaf 1) GREEN=$(tput setaf 2) YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4) MAGENTA=$(tput setaf 5) CYAN=$(tput setaf 6)
    BOLD=$(tput bold) RESET=$(tput sgr0)
else
    RED="" GREEN="" YELLOW="" BLUE="" MAGENTA="" CYAN="" BOLD="" RESET=""
fi

info()    { echo "${BLUE}[INFO]${RESET} $*"; }
success() { echo "${GREEN}[OK]${RESET}   $*"; }
warn()    { echo "${YELLOW}[WARN]${RESET} $*"; }
error()   { echo "${RED}[ERR]${RESET}  $*" >&2; }
step()    { echo ""; echo "${MAGENTA}${BOLD}>> $*${RESET}"; }

spinner() {
    local pid=$1
    local msg="${2:-Working...}"
    local chars='|/-\'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${CYAN}%s${RESET} %s " "${chars:i++%${#chars}:1}" "$msg"
        sleep 0.2
    done
    printf "\r%*s\r" $((${#msg} + 6)) ""
}

generate_key() {
    local length="${1:-32}"
    if command -v openssl &>/dev/null; then
        openssl rand -hex "$length"
    elif command -v xxd &>/dev/null; then
        head -c "$length" /dev/urandom | xxd -p | tr -d '\n'
    else
        # Last resort fallback
        head -c "$length" /dev/urandom | od -An -tx1 | tr -d ' \n' | head -c $(( length * 2 ))
    fi
}

ask_or_default() {
    local prompt="$1"
    local default="$2"
    if [ "$UNATTENDED" = true ]; then
        echo "$default"
        return
    fi
    read -rp "${prompt} [${default}]: " answer
    echo "${answer:-$default}"
}

# ============================================
# Banner
# ============================================
echo ""
echo "${MAGENTA}${BOLD}"
cat << 'BANNER'
  ___________  ________  __  ___________  ______
 /_  __/ __  |/ ____/ / / / / __  /_  __// __  |
  / / / /_/ // / __/ / / / / /_/ / / /  / / / /
 / / / __  // / / / / / / / __  / / /  / / / /
/ / / / / // /_/ / /_/ / / / / / / /  / /_/ /
\/ /_/ /_/ \____/\____/ /_/ /_/ /_/   \____/
                                       -SEND
BANNER
echo "${RESET}"
echo "  ${CYAN}Plataforma multi-tenant de mensajeria WhatsApp${RESET}"
echo "  ${CYAN}Despliegue automatizado${RESET}"
echo ""

# ============================================
# Step 1: Detect OS
# ============================================
step "Detectando sistema operativo..."

OS_TYPE="unknown"
case "$(uname -s)" in
    Linux*)
        if grep -qi microsoft /proc/version 2>/dev/null; then
            OS_TYPE="wsl"
            info "Detectado: Windows Subsystem for Linux (WSL)"
        else
            OS_TYPE="linux"
            info "Detectado: Linux"
        fi
        ;;
    Darwin*)
        OS_TYPE="macos"
        info "Detectado: macOS"
        ;;
    MINGW*|MSYS*|CYGWIN*)
        OS_TYPE="gitbash"
        info "Detectado: Git Bash / MSYS2"
        ;;
    *)
        warn "Sistema operativo no reconocido: $(uname -s)"
        info "Continuando de todas formas..."
        ;;
esac

# ============================================
# Step 2: Check dependencies
# ============================================
step "Verificando dependencias..."

missing=()

# Git
if command -v git &>/dev/null; then
    success "git $(git --version | awk '{print $3}')"
else
    missing+=("git")
    error "git no encontrado"
fi

# Docker
if command -v docker &>/dev/null; then
    success "docker $(docker --version | awk '{print $3}' | tr -d ',')"
else
    missing+=("docker")
    error "docker no encontrado"
fi

# Docker Compose
COMPOSE_CMD=""
if docker compose version &>/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
    success "docker compose $(docker compose version --short 2>/dev/null || echo '(v2)')"
elif command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
    success "docker-compose (legacy)"
else
    missing+=("docker-compose")
    error "docker compose no encontrado"
fi

# openssl (optional - has fallbacks)
if command -v openssl &>/dev/null; then
    success "openssl $(openssl version 2>/dev/null | awk '{print $2}')"
else
    warn "openssl no encontrado - usando metodo alternativo para generar claves"
fi

if [ ${#missing[@]} -gt 0 ]; then
    echo ""
    warn "Faltan dependencias: ${missing[*]}"

    case "$OS_TYPE" in
        linux|wsl)
            echo ""
            if [ "$UNATTENDED" = true ]; then
                INSTALL_AUTO=true
            else
                read -rp "  ${YELLOW}Instalar Docker automaticamente? (S/n):${RESET} " install_answer
                if [[ "$install_answer" =~ ^[nN]$ ]]; then
                    INSTALL_AUTO=false
                else
                    INSTALL_AUTO=true
                fi
            fi

            if [ "$INSTALL_AUTO" = true ]; then
                step "Instalando Docker desde el repositorio oficial..."

                sudo apt-get update -qq
                sudo apt-get install -y ca-certificates curl

                sudo install -m 0755 -d /etc/apt/keyrings
                sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
                sudo chmod a+r /etc/apt/keyrings/docker.asc

                echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

                sudo apt-get update -qq
                sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

                sudo systemctl enable docker && sudo systemctl start docker

                # Add current user to docker group
                if ! groups "$USER" | grep -q '\bdocker\b'; then
                    sudo usermod -aG docker "$USER"
                    warn "Se agrego '$USER' al grupo docker."
                    info "Si docker falla mas adelante, cierra sesion y vuelve a entrar."
                    # Use newgrp to apply group in current session
                    info "Aplicando grupo docker en la sesion actual..."
                fi

                # Re-check docker compose
                if docker compose version &>/dev/null 2>&1; then
                    COMPOSE_CMD="docker compose"
                    success "docker compose $(docker compose version --short 2>/dev/null || echo '(v2)')"
                fi

                success "Docker instalado correctamente"
            else
                echo ""
                info "Instrucciones de instalacion manual:"
                echo "  # Repo oficial de Docker:"
                echo "  sudo apt-get update && sudo apt-get install -y ca-certificates curl"
                echo "  sudo install -m 0755 -d /etc/apt/keyrings"
                echo "  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc"
                echo "  sudo chmod a+r /etc/apt/keyrings/docker.asc"
                echo "  echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \$(. /etc/os-release && echo \"\$VERSION_CODENAME\") stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null"
                echo "  sudo apt-get update && sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin"
                echo "  sudo systemctl enable docker && sudo systemctl start docker"
                echo "  sudo usermod -aG docker \$USER  # (cerrar sesion y volver a entrar)"
                exit 1
            fi
            ;;
        macos)
            echo ""
            info "Instrucciones de instalacion:"
            echo "  brew install git"
            echo "  Instalar Docker Desktop: https://docs.docker.com/desktop/install/mac-install/"
            exit 1
            ;;
        gitbash)
            echo ""
            info "Instrucciones de instalacion:"
            echo "  Instalar Git: https://git-scm.com/download/win"
            echo "  Instalar Docker Desktop: https://docs.docker.com/desktop/install/windows-install/"
            exit 1
            ;;
        *)
            echo ""
            info "Instrucciones de instalacion:"
            echo "  Instalar git: https://git-scm.com/"
            echo "  Instalar Docker: https://docs.docker.com/get-docker/"
            exit 1
            ;;
    esac
fi

# ============================================
# Step 3: Verify Docker is running + fix permissions
# ============================================
step "Verificando que Docker esta corriendo..."

if ! docker info &>/dev/null 2>&1; then
    # Check if it's a permission issue (Docker is running but user can't access)
    if sudo docker info &>/dev/null 2>&1; then
        warn "Docker esta corriendo pero tu usuario no tiene permisos."
        info "Agregando '$USER' al grupo docker..."
        sudo usermod -aG docker "$USER"
        # Apply group in current session via sg
        info "Aplicando permisos... (las siguientes operaciones usaran sudo si es necesario)"
        # Re-define compose command with sudo fallback
        if sg docker -c "docker compose version" &>/dev/null 2>&1; then
            COMPOSE_CMD="sg docker -c 'docker compose'"
            # Actually, sg in subshells is tricky. Use sudo instead.
            COMPOSE_CMD="sudo docker compose"
        elif sudo docker compose version &>/dev/null 2>&1; then
            COMPOSE_CMD="sudo docker compose"
        fi
        success "Docker esta corriendo (usando permisos elevados para esta sesion)"
        info "En futuras sesiones no necesitaras sudo (cierra sesion y vuelve a entrar)"
    else
        # Docker genuinely not running
        case "$OS_TYPE" in
            linux|wsl)
                info "Intentando iniciar Docker..."
                sudo systemctl start docker && sudo systemctl enable docker
                if sudo docker info &>/dev/null 2>&1; then
                    success "Docker iniciado correctamente"
                    # Also fix permissions
                    if ! groups "$USER" | grep -q '\bdocker\b'; then
                        sudo usermod -aG docker "$USER"
                    fi
                    COMPOSE_CMD="sudo docker compose"
                else
                    error "No se pudo iniciar Docker."
                    info "Revisa: sudo journalctl -u docker"
                    exit 1
                fi
                ;;
            macos|gitbash)
                error "Docker no esta corriendo."
                info "Abre Docker Desktop y espera a que este listo."
                exit 1
                ;;
            *)
                error "Docker no esta corriendo."
                exit 1
                ;;
        esac
    fi
else
    success "Docker esta corriendo"
fi


# ============================================
# Step 4: Clone or detect repo
# ============================================
step "Preparando repositorio..."

IN_REPO=false
if [ -f "docker-compose.yml" ] && [ -d "gateway" ] && [ -f ".env.example" ]; then
    IN_REPO=true
    success "Ya estamos dentro del repositorio TAGUATO-SEND"
elif [ -d "$REPO_DIR" ] && [ -f "$REPO_DIR/docker-compose.yml" ]; then
    info "Directorio $REPO_DIR ya existe, entrando..."
    cd "$REPO_DIR"
    IN_REPO=true
fi

if [ "$IN_REPO" = false ]; then
    info "Clonando repositorio..."
    git clone "$REPO_URL" "$REPO_DIR"
    cd "$REPO_DIR"
    success "Repositorio clonado en $(pwd)"
fi

# ============================================
# Step 5: Generate .env
# ============================================
step "Configurando variables de entorno..."

if [ -f ".env" ]; then
    if [ "$UNATTENDED" = true ]; then
        warn ".env ya existe - modo desatendido, se conserva el existente"
        SKIP_ENV=true
    else
        read -rp "  ${YELLOW}El archivo .env ya existe. Sobreescribir? (s/N):${RESET} " overwrite
        if [[ "$overwrite" =~ ^[sS]$ ]]; then
            SKIP_ENV=false
        else
            info "Conservando .env existente"
            SKIP_ENV=true
        fi
    fi
else
    SKIP_ENV=false
fi

if [ "${SKIP_ENV:-false}" = false ]; then
    if [ ! -f ".env.example" ]; then
        error "No se encontro .env.example en $(pwd)"
        info "Asegurate de estar dentro del directorio TAGUATO-SEND"
        exit 1
    fi
    cp .env.example .env
    info "Copiado .env.example -> .env"

    # Generate secure values
    API_KEY=$(generate_key 32)
    PG_PASS=$(generate_key 16)

    # Admin password
    if [ "$UNATTENDED" = true ]; then
        ADMIN_PASS=$(generate_key 16)
    else
        echo ""
        info "Configurar contrasena del administrador."
        info "Presiona Enter para generar una automaticamente."
        read -rsp "  Contrasena admin: " ADMIN_PASS
        echo ""
        if [ -z "$ADMIN_PASS" ]; then
            ADMIN_PASS=$(generate_key 16)
            info "Contrasena admin generada automaticamente"
        fi
    fi

    # Gateway port
    GW_PORT=$(ask_or_default "  Puerto del gateway" "80")

    # Replace placeholders in .env
    if [[ "$OSTYPE" == "darwin"* ]]; then
        SED_I="sed -i ''"
    else
        SED_I="sed -i"
    fi

    # AUTHENTICATION_API_KEY
    $SED_I "s|CHANGE_ME_GENERATE_A_SECURE_KEY|${API_KEY}|g" .env

    # ADMIN_PASSWORD
    $SED_I "s|CHANGE_ME_USE_STRONG_PASSWORD_FOR_ADMIN|${ADMIN_PASS}|g" .env

    # POSTGRES_PASSWORD (in POSTGRES_PASSWORD= line)
    $SED_I "s|POSTGRES_PASSWORD=CHANGE_ME_USE_STRONG_PASSWORD|POSTGRES_PASSWORD=${PG_PASS}|g" .env

    # DATABASE_CONNECTION_URI (contains the password too)
    $SED_I "s|taguato:CHANGE_ME_USE_STRONG_PASSWORD@|taguato:${PG_PASS}@|g" .env

    # GATEWAY_PORT
    $SED_I "s|GATEWAY_PORT=80|GATEWAY_PORT=${GW_PORT}|g" .env

    # Clean up macOS sed backup files
    rm -f .env''

    # Verify .env was created
    if [ ! -f ".env" ]; then
        error "Fallo al crear el archivo .env"
        exit 1
    fi

    success "Archivo .env configurado con valores seguros"
    echo ""
    echo "  ${CYAN}GATEWAY_PORT${RESET}          = ${GW_PORT}"
    echo "  ${CYAN}ADMIN_USERNAME${RESET}        = admin"
    echo "  ${CYAN}ADMIN_PASSWORD${RESET}        = ${ADMIN_PASS}"
    echo "  ${CYAN}AUTHENTICATION_API_KEY${RESET} = ${API_KEY:0:8}...${API_KEY: -8}"
    echo "  ${CYAN}POSTGRES_PASSWORD${RESET}     = ${PG_PASS:0:4}...${PG_PASS: -4}"
fi

# ============================================
# Step 5b: Configure firewall (Linux only)
# ============================================
if [ "$OS_TYPE" = "linux" ] || [ "$OS_TYPE" = "wsl" ]; then
    if command -v ufw &>/dev/null; then
        step "Configurando firewall (ufw)..."

        FW_PORT="${GW_PORT:-80}"
        if [ -z "$FW_PORT" ] || [ "$FW_PORT" = "" ]; then
            FW_PORT=$(grep '^GATEWAY_PORT=' .env 2>/dev/null | cut -d= -f2 || echo "80")
        fi

        # Always allow SSH first (safety net)
        sudo ufw allow 22/tcp comment "SSH" >/dev/null 2>&1

        # Allow TAGUATO ports
        sudo ufw allow "$FW_PORT"/tcp comment "TAGUATO Gateway" >/dev/null 2>&1
        sudo ufw allow 443/tcp comment "TAGUATO HTTPS" >/dev/null 2>&1

        # Enable ufw if not active
        UFW_STATUS=$(sudo ufw status 2>/dev/null | head -1 || echo "")
        if ! echo "$UFW_STATUS" | grep -qi "active"; then
            info "Activando firewall..."
            sudo ufw --force enable >/dev/null 2>&1
        fi

        success "Firewall configurado (SSH:22, Gateway:$FW_PORT, HTTPS:443)"
    fi
fi

# ============================================
# Step 6: Build and deploy
# ============================================
step "Construyendo e iniciando servicios..."

# Final check: .env must exist for docker compose
if [ ! -f ".env" ]; then
    error "Archivo .env no encontrado en $(pwd)"
    info "Ejecuta el script de nuevo desde el directorio del proyecto."
    exit 1
fi

info "Esto puede tomar unos minutos la primera vez..."

eval $COMPOSE_CMD up -d --build &
BUILD_PID=$!
spinner $BUILD_PID "Construyendo contenedores..."
wait $BUILD_PID
BUILD_EXIT=$?

if [ $BUILD_EXIT -ne 0 ]; then
    error "Error al construir/iniciar los servicios (exit code: $BUILD_EXIT)"
    info "Revisa los logs con: $COMPOSE_CMD logs"
    exit 1
fi
success "Servicios iniciados"

# ============================================
# Step 7: Wait for healthy
# ============================================
step "Esperando a que los servicios esten listos..."

ELAPSED=0
INTERVAL=5
ALL_HEALTHY=false

while [ $ELAPSED -lt $HEALTH_TIMEOUT ]; do
    # Check if all containers are running
    RUNNING=$(eval $COMPOSE_CMD ps --format '{{.Status}}' 2>/dev/null | grep -ci 'up' || true)
    TOTAL=$(eval $COMPOSE_CMD ps --format '{{.Status}}' 2>/dev/null | wc -l | tr -d ' ' || true)

    if [ "$TOTAL" -gt 0 ] && [ "$RUNNING" -eq "$TOTAL" ]; then
        ALL_HEALTHY=true
        break
    fi

    printf "\r  ${CYAN}|${RESET} Esperando... (%ds/%ds) - %s/%s servicios corriendo " \
        "$ELAPSED" "$HEALTH_TIMEOUT" "$RUNNING" "$TOTAL"
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done

echo ""

if [ "$ALL_HEALTHY" = true ]; then
    success "Todos los servicios estan corriendo ($ELAPSED segundos)"
else
    warn "Timeout esperando servicios (${HEALTH_TIMEOUT}s). Algunos pueden no estar listos."
    info "Verifica con: $COMPOSE_CMD ps"
fi

# Give postgres a moment to run init scripts
sleep 5

# ============================================
# Step 8: Get admin token
# ============================================
step "Obteniendo token del administrador..."

ADMIN_TOKEN=""
ADMIN_TOKEN=$(eval $COMPOSE_CMD logs taguato-postgres 2>/dev/null | grep "API Token:" | tail -1 | sed 's/.*API Token: //' | tr -d '[:space:]' || true)

if [ -z "$ADMIN_TOKEN" ]; then
    # Try waiting a bit more and retry
    sleep 5
    ADMIN_TOKEN=$(eval $COMPOSE_CMD logs taguato-postgres 2>/dev/null | grep "API Token:" | tail -1 | sed 's/.*API Token: //' | tr -d '[:space:]' || true)
fi

# ============================================
# Step 9: Summary
# ============================================
PORT="${GW_PORT:-80}"
# If we didn't generate .env, try to read port from existing .env
if [ "${SKIP_ENV:-false}" = true ]; then
    PORT=$(grep '^GATEWAY_PORT=' .env 2>/dev/null | cut -d= -f2 || echo "80")
fi

if [ "$PORT" = "80" ]; then
    BASE_URL="http://localhost"
else
    BASE_URL="http://localhost:${PORT}"
fi

echo ""
echo "${GREEN}${BOLD}"
echo "  ============================================"
echo "     TAGUATO-SEND desplegado exitosamente!"
echo "  ============================================"
echo "${RESET}"
echo "  ${CYAN}${BOLD}URLs:${RESET}"
echo "  Panel web:        ${GREEN}${BASE_URL}/panel/${RESET}"
echo "  API:              ${GREEN}${BASE_URL}/${RESET}"
echo "  Pagina de estado: ${GREEN}${BASE_URL}/status/${RESET}"
echo "  Swagger (admin):  ${GREEN}${BASE_URL}/docs${RESET}"
echo ""
echo "  ${CYAN}${BOLD}Credenciales admin:${RESET}"
echo "  Usuario:          ${BOLD}admin${RESET}"

if [ "${SKIP_ENV:-false}" = false ]; then
    echo "  Contrasena:       ${BOLD}${ADMIN_PASS}${RESET}"
fi

if [ -n "$ADMIN_TOKEN" ]; then
    echo "  API Token:        ${BOLD}${ADMIN_TOKEN}${RESET}"
else
    warn "No se pudo extraer el token automaticamente."
    info "Ejecuta: $COMPOSE_CMD logs taguato-postgres | grep 'API Token'"
fi

echo ""
echo "  ${CYAN}${BOLD}Comandos utiles:${RESET}"
echo "  Ver logs:         ${BOLD}$COMPOSE_CMD logs -f${RESET}"
echo "  Detener:          ${BOLD}$COMPOSE_CMD down${RESET}"
echo "  Reiniciar:        ${BOLD}$COMPOSE_CMD restart${RESET}"
echo "  Estado:           ${BOLD}$COMPOSE_CMD ps${RESET}"
echo ""
echo "  ${YELLOW}Guarda el token del admin en un lugar seguro!${RESET}"
echo ""

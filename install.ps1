# ============================================
# TAGUATO-SEND - Universal Deployment Script
# Windows PowerShell
# ============================================

param(
    [Alias("y")]
    [switch]$Unattended
)

$ErrorActionPreference = "Stop"

$REPO_URL = "https://github.com/Idod00/TAGUATO-SEND.git"
$REPO_DIR = "TAGUATO-SEND"
$HEALTH_TIMEOUT = 180

# ============================================
# Helpers
# ============================================
function Write-Info    { param($msg) Write-Host "[INFO] " -ForegroundColor Cyan -NoNewline; Write-Host $msg }
function Write-Ok      { param($msg) Write-Host "[OK]   " -ForegroundColor Green -NoNewline; Write-Host $msg }
function Write-Warn    { param($msg) Write-Host "[WARN] " -ForegroundColor Yellow -NoNewline; Write-Host $msg }
function Write-Err     { param($msg) Write-Host "[ERR]  " -ForegroundColor Red -NoNewline; Write-Host $msg }
function Write-Step    { param($msg) Write-Host ""; Write-Host ">> $msg" -ForegroundColor Magenta }

function New-SecureKey {
    param([int]$Bytes = 32)
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $buf = New-Object byte[] $Bytes
    $rng.GetBytes($buf)
    return [BitConverter]::ToString($buf).Replace("-", "").ToLower()
}

function Show-Spinner {
    param([scriptblock]$Action, [string]$Message = "Working...")
    $job = Start-Job -ScriptBlock $Action
    $chars = @("|", "/", "-", "\")
    $i = 0
    while ($job.State -eq "Running") {
        Write-Host "`r  $($chars[$i % $chars.Length]) $Message " -ForegroundColor Cyan -NoNewline
        Start-Sleep -Milliseconds 200
        $i++
    }
    Write-Host "`r$(' ' * ($Message.Length + 6))`r" -NoNewline
    $result = Receive-Job -Job $job
    Remove-Job -Job $job
    return $result
}

# ============================================
# Banner
# ============================================
Write-Host ""
Write-Host @"
  ___________  ________  __  ___________  ______
 /_  __/ __  |/ ____/ / / / / __  /_  __// __  |
  / / / /_/ // / __/ / / / / /_/ / / /  / / / /
 / / / __  // / / / / / / / __  / / /  / / / /
/ / / / / // /_/ / /_/ / / / / / / /  / /_/ /
\/ /_/ /_/ \____/\____/ /_/ /_/ /_/   \____/
                                       -SEND
"@ -ForegroundColor Magenta

Write-Host ""
Write-Host "  Plataforma multi-tenant de mensajeria WhatsApp" -ForegroundColor Cyan
Write-Host "  Despliegue automatizado" -ForegroundColor Cyan
Write-Host ""

# ============================================
# Step 1: Detect OS
# ============================================
Write-Step "Detectando sistema operativo..."
Write-Info "Detectado: Windows (PowerShell $($PSVersionTable.PSVersion))"

# ============================================
# Step 2: Check dependencies
# ============================================
Write-Step "Verificando dependencias..."

$missing = @()

# Git
if (Get-Command git -ErrorAction SilentlyContinue) {
    $gitVersion = (git --version) -replace "git version ", ""
    Write-Ok "git $gitVersion"
} else {
    $missing += "git"
    Write-Err "git no encontrado"
}

# Docker
if (Get-Command docker -ErrorAction SilentlyContinue) {
    $dockerVersion = ((docker --version) -split " ")[2].TrimEnd(",")
    Write-Ok "docker $dockerVersion"
} else {
    $missing += "docker"
    Write-Err "docker no encontrado"
}

# Docker Compose
$COMPOSE_CMD = $null
try {
    docker compose version 2>$null | Out-Null
    $COMPOSE_CMD = "docker compose"
    Write-Ok "docker compose (v2)"
} catch {
    if (Get-Command docker-compose -ErrorAction SilentlyContinue) {
        $COMPOSE_CMD = "docker-compose"
        Write-Ok "docker-compose (legacy)"
    } else {
        $missing += "docker-compose"
        Write-Err "docker compose no encontrado"
    }
}

if ($missing.Count -gt 0) {
    Write-Host ""
    Write-Err "Faltan dependencias: $($missing -join ', ')"
    Write-Host ""
    Write-Info "Instrucciones de instalacion:"
    Write-Host "  Instalar Git:    https://git-scm.com/download/win"
    Write-Host "  Instalar Docker: https://docs.docker.com/desktop/install/windows-install/"
    exit 1
}

# ============================================
# Step 3: Verify Docker is running
# ============================================
Write-Step "Verificando que Docker esta corriendo..."

try {
    docker info 2>$null | Out-Null
    Write-Ok "Docker esta corriendo"
} catch {
    Write-Err "Docker no esta corriendo."
    Write-Info "Abre Docker Desktop y espera a que este listo."
    exit 1
}

# ============================================
# Step 4: Clone or detect repo
# ============================================
Write-Step "Preparando repositorio..."

$InRepo = $false
if ((Test-Path "docker-compose.yml") -and (Test-Path "gateway") -and (Test-Path ".env.example")) {
    $InRepo = $true
    Write-Ok "Ya estamos dentro del repositorio TAGUATO-SEND"
} elseif ((Test-Path $REPO_DIR) -and (Test-Path "$REPO_DIR/docker-compose.yml")) {
    Write-Info "Directorio $REPO_DIR ya existe, entrando..."
    Set-Location $REPO_DIR
    $InRepo = $true
}

if (-not $InRepo) {
    Write-Info "Clonando repositorio..."
    git clone $REPO_URL $REPO_DIR
    Set-Location $REPO_DIR
    Write-Ok "Repositorio clonado en $(Get-Location)"
}

# ============================================
# Step 5: Generate .env
# ============================================
Write-Step "Configurando variables de entorno..."

$SkipEnv = $false

if (Test-Path ".env") {
    if ($Unattended) {
        Write-Warn ".env ya existe - modo desatendido, se conserva el existente"
        $SkipEnv = $true
    } else {
        $overwrite = Read-Host "  El archivo .env ya existe. Sobreescribir? (s/N)"
        if ($overwrite -match "^[sS]$") {
            $SkipEnv = $false
        } else {
            Write-Info "Conservando .env existente"
            $SkipEnv = $true
        }
    }
}

$AdminPass = ""
$GwPort = "80"
$ApiKey = ""
$PgPass = ""

if (-not $SkipEnv) {
    Copy-Item ".env.example" ".env"
    Write-Info "Copiado .env.example -> .env"

    # Generate secure values
    $ApiKey = New-SecureKey -Bytes 32
    $PgPass = New-SecureKey -Bytes 16

    # Admin password
    if ($Unattended) {
        $AdminPass = New-SecureKey -Bytes 16
    } else {
        Write-Host ""
        Write-Info "Configurar contrasena del administrador."
        Write-Info "Presiona Enter para generar una automaticamente."
        $securePass = Read-Host "  Contrasena admin" -AsSecureString
        $AdminPass = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePass)
        )
        if ([string]::IsNullOrEmpty($AdminPass)) {
            $AdminPass = New-SecureKey -Bytes 16
            Write-Info "Contrasena admin generada automaticamente"
        }
    }

    # Gateway port
    if ($Unattended) {
        $GwPort = "80"
    } else {
        $portInput = Read-Host "  Puerto del gateway [80]"
        if (-not [string]::IsNullOrEmpty($portInput)) { $GwPort = $portInput }
    }

    # Replace placeholders in .env
    $envContent = Get-Content ".env" -Raw
    $envContent = $envContent -replace "CHANGE_ME_GENERATE_A_SECURE_KEY", $ApiKey
    $envContent = $envContent -replace "CHANGE_ME_USE_STRONG_PASSWORD_FOR_ADMIN", $AdminPass
    $envContent = $envContent -replace "POSTGRES_PASSWORD=CHANGE_ME_USE_STRONG_PASSWORD", "POSTGRES_PASSWORD=$PgPass"
    $envContent = $envContent -replace "taguato:CHANGE_ME_USE_STRONG_PASSWORD@", "taguato:${PgPass}@"
    $envContent = $envContent -replace "GATEWAY_PORT=80", "GATEWAY_PORT=$GwPort"
    Set-Content ".env" $envContent -NoNewline

    Write-Ok "Archivo .env configurado con valores seguros"
    Write-Host ""
    Write-Host "  GATEWAY_PORT          = $GwPort" -ForegroundColor Cyan
    Write-Host "  ADMIN_USERNAME        = admin" -ForegroundColor Cyan
    Write-Host "  ADMIN_PASSWORD        = $AdminPass" -ForegroundColor Cyan
    Write-Host "  AUTHENTICATION_API_KEY = $($ApiKey.Substring(0,8))...$($ApiKey.Substring($ApiKey.Length-8))" -ForegroundColor Cyan
    Write-Host "  POSTGRES_PASSWORD     = $($PgPass.Substring(0,4))...$($PgPass.Substring($PgPass.Length-4))" -ForegroundColor Cyan
}

# ============================================
# Step 6: Build and deploy
# ============================================
Write-Step "Construyendo e iniciando servicios..."
Write-Info "Esto puede tomar unos minutos la primera vez..."

$composeArgs = "up -d --build"
if ($COMPOSE_CMD -eq "docker compose") {
    $buildProcess = Start-Process -FilePath "docker" -ArgumentList "compose up -d --build" -NoNewWindow -PassThru -Wait
} else {
    $buildProcess = Start-Process -FilePath "docker-compose" -ArgumentList "up -d --build" -NoNewWindow -PassThru -Wait
}

if ($buildProcess.ExitCode -ne 0) {
    Write-Err "Error al construir/iniciar los servicios (exit code: $($buildProcess.ExitCode))"
    Write-Info "Revisa los logs con: $COMPOSE_CMD logs"
    exit 1
}
Write-Ok "Servicios iniciados"

# ============================================
# Step 7: Wait for healthy
# ============================================
Write-Step "Esperando a que los servicios esten listos..."

$elapsed = 0
$interval = 5
$allHealthy = $false

while ($elapsed -lt $HEALTH_TIMEOUT) {
    if ($COMPOSE_CMD -eq "docker compose") {
        $statuses = docker compose ps --format '{{.Status}}' 2>$null
    } else {
        $statuses = docker-compose ps --format '{{.Status}}' 2>$null
    }

    $total = ($statuses | Measure-Object).Count
    $running = ($statuses | Where-Object { $_ -match "Up" } | Measure-Object).Count

    if ($total -gt 0 -and $running -eq $total) {
        $allHealthy = $true
        break
    }

    Write-Host "`r  | Esperando... (${elapsed}s/${HEALTH_TIMEOUT}s) - ${running}/${total} servicios corriendo " -ForegroundColor Cyan -NoNewline
    Start-Sleep -Seconds $interval
    $elapsed += $interval
}

Write-Host ""

if ($allHealthy) {
    Write-Ok "Todos los servicios estan corriendo (${elapsed} segundos)"
} else {
    Write-Warn "Timeout esperando servicios (${HEALTH_TIMEOUT}s). Algunos pueden no estar listos."
    Write-Info "Verifica con: $COMPOSE_CMD ps"
}

# Give postgres a moment to run init scripts
Start-Sleep -Seconds 5

# ============================================
# Step 8: Get admin token
# ============================================
Write-Step "Obteniendo token del administrador..."

$AdminToken = ""
if ($COMPOSE_CMD -eq "docker compose") {
    $logs = docker compose logs taguato-postgres 2>$null
} else {
    $logs = docker-compose logs taguato-postgres 2>$null
}

$tokenLine = $logs | Select-String "API Token:" | Select-Object -Last 1
if ($tokenLine) {
    $AdminToken = ($tokenLine -replace ".*API Token:\s*", "").Trim()
}

if ([string]::IsNullOrEmpty($AdminToken)) {
    Start-Sleep -Seconds 5
    if ($COMPOSE_CMD -eq "docker compose") {
        $logs = docker compose logs taguato-postgres 2>$null
    } else {
        $logs = docker-compose logs taguato-postgres 2>$null
    }
    $tokenLine = $logs | Select-String "API Token:" | Select-Object -Last 1
    if ($tokenLine) {
        $AdminToken = ($tokenLine -replace ".*API Token:\s*", "").Trim()
    }
}

# ============================================
# Step 9: Summary
# ============================================
$Port = $GwPort
if ($SkipEnv) {
    $envLine = Get-Content ".env" | Where-Object { $_ -match "^GATEWAY_PORT=" }
    if ($envLine) { $Port = ($envLine -split "=")[1] }
}

if ($Port -eq "80") {
    $BaseUrl = "http://localhost"
} else {
    $BaseUrl = "http://localhost:$Port"
}

Write-Host ""
Write-Host "  ============================================" -ForegroundColor Green
Write-Host "     TAGUATO-SEND desplegado exitosamente!" -ForegroundColor Green
Write-Host "  ============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  URLs:" -ForegroundColor Cyan
Write-Host "  Panel web:        " -NoNewline; Write-Host "$BaseUrl/panel/" -ForegroundColor Green
Write-Host "  API:              " -NoNewline; Write-Host "$BaseUrl/" -ForegroundColor Green
Write-Host "  Pagina de estado: " -NoNewline; Write-Host "$BaseUrl/status/" -ForegroundColor Green
Write-Host "  Swagger (admin):  " -NoNewline; Write-Host "$BaseUrl/docs" -ForegroundColor Green
Write-Host ""
Write-Host "  Credenciales admin:" -ForegroundColor Cyan
Write-Host "  Usuario:          admin"

if (-not $SkipEnv) {
    Write-Host "  Contrasena:       $AdminPass"
}

if (-not [string]::IsNullOrEmpty($AdminToken)) {
    Write-Host "  API Token:        $AdminToken"
} else {
    Write-Warn "No se pudo extraer el token automaticamente."
    Write-Info "Ejecuta: $COMPOSE_CMD logs taguato-postgres | Select-String 'API Token'"
}

Write-Host ""
Write-Host "  Comandos utiles:" -ForegroundColor Cyan
Write-Host "  Ver logs:         $COMPOSE_CMD logs -f"
Write-Host "  Detener:          $COMPOSE_CMD down"
Write-Host "  Reiniciar:        $COMPOSE_CMD restart"
Write-Host "  Estado:           $COMPOSE_CMD ps"
Write-Host ""
Write-Host "  Guarda el token del admin en un lugar seguro!" -ForegroundColor Yellow
Write-Host ""

# ============================================================
# INVENTÁRIO, RESET CONSERVADOR E LIMPEZA DE CREDENCIAIS
# ============================================================
#
# O script:
#   - Solicita obrigatoriamente o número do computador ao operador.
#   - Identifica o usuário de forma não destrutiva.
#   - Inventaria Python, Pip, Chocolatey, Postman e VS Code.
#   - Encerra processos de forma inteligente com timeout e validação.
#   - Reseta APENAS os dados de perfil do usuário (preserva instaladores).
#   - Remove credenciais salvas no Windows (GitHub, VS Code, etc).
#   - Rastreia granularmente o sucesso/falha de cada etapa.
#   - Gera uma linha de log estruturada, copia para o clipboard
#     e envia automaticamente para o Rentry.co (9y2fgm4z).
# ============================================================

$ErrorActionPreference = "Continue"

Clear-Host

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "     INVENTARIO DO COMPUTADOR (V2)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ------------------------------------------------------------
# CONFIGURAÇÃO RENTRY.CO (DESTINO DOS RESULTADOS)
# ------------------------------------------------------------
$rentryEntryUrl = "9y2fgm4z"
$rentryEditCode = "jGeEjvpV"

# ------------------------------------------------------------
# 1. IDENTIFICACAO
# ------------------------------------------------------------
# Pergunta e valida o número do computador (aceita estritamente apenas números)
do {
    $numeroComputador = Read-Host "Digite o numero do computador"
    if ($numeroComputador -notmatch '^\d+$') {
        Write-Host "Entrada invalida! Digite apenas numeros." -ForegroundColor Red
    }
} while ($numeroComputador -notmatch '^\d+$')

$computerName = $numeroComputador
$userName = $env:USERNAME
$dateTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

Write-Host ""
Write-Host "Computador (Nº) : $computerName" -ForegroundColor Green
Write-Host "Usuario         : $userName"
Write-Host "Data            : $dateTime"
Write-Host ""

# ------------------------------------------------------------
# FUNCOES AUXILIARES
# ------------------------------------------------------------
function Get-CommandVersion {
    param (
        [string]$CommandName,
        [string]$Arguments = "--version"
    )

    $command = Get-Command $CommandName -ErrorAction SilentlyContinue

    if (-not $command) {
        return "NAO_INSTALADO"
    }

    try {
        $output = & $command.Source $Arguments 2>&1 | Out-String
        $output = $output.Trim()

        if ([string]::IsNullOrWhiteSpace($output)) {
            return "INSTALADO"
        }

        $firstLine = ($output -split "`r?`n")[0].Trim()

        return $firstLine
    }
    catch {
        return "ERRO"
    }
}

function Test-PathStatus {
    param ([string]$Path)
    return Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue
}

function Stop-Application {
    param (
        [string[]]$ProcessNames,
        [int]$TimeoutSeconds = 10
    )

    foreach ($processName in $ProcessNames) {
        Get-Process -Name $processName -ErrorAction SilentlyContinue |
            Stop-Process -Force -ErrorAction SilentlyContinue
    }

    $elapsed = 0
    while ($elapsed -lt $TimeoutSeconds) {
        $running = $false
        foreach ($processName in $ProcessNames) {
            if (Get-Process -Name $processName -ErrorAction SilentlyContinue) {
                $running = $true
                break
            }
        }
        if (-not $running) { return $true }
        Start-Sleep -Milliseconds 500
        $elapsed += 0.5
    }
    return $false
}

function Remove-Folder {
    param ([string]$Path)

    if (-not (Test-PathStatus $Path)) { return "NAO_EXISTE" }

    try {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        if (-not (Test-PathStatus $Path)) { return "OK" } else { return "FALHOU" }
    }
    catch {
        return "ERRO"
    }
}

function Remove-WindowsCredentials {
    param (
        [string[]]$Targets
    )

    $removed = @()

    # Garante o uso do executavel do System32
    $cmdkeyPath = "$env:SystemRoot\System32\cmdkey.exe"
    if (-not (Test-Path $cmdkeyPath)) {
        $cmdkeyPath = "cmdkey.exe"
    }

    # Executa o cmdkey e converte a saida para um array de linhas limpas
    $cmdkeyOutput = & $cmdkeyPath /list 2>&1 | Out-String
    $lines = $cmdkeyOutput -split "`r?`n"

    foreach ($line in $lines) {
        # Extrai qualquer linha que contenha um indicador de alvo/target
        if ($line -match "(?:Target|Alvo):\s*(.+)" -or $line -match "Target=\s*(.+)") {
            $credentialName = $Matches[1].Trim()

            # Verifica se o nome da credencial bate com algum dos nossos alvos
            foreach ($target in $Targets) {
                if ($credentialName -like "*$target*") {
                    
                    # Evita tentar apagar a mesma credencial duas vezes no mesmo loop
                    if ($removed -notcontains $credentialName) {
                        try {
                            & $cmdkeyPath /delete:$credentialName | Out-Null
                            Write-Host "  [OK] Credencial removida: $credentialName" -ForegroundColor Green
                            $removed += $credentialName
                        } catch {}
                    }
                }
            }
        }
    }

    if ($removed.Count -eq 0) {
        return "NAO_ENCONTRADA"
    }

    return "OK"
}

# ------------------------------------------------------------
# 2. INVENTARIO - TECNOLOGIAS
# ------------------------------------------------------------
Write-Host "[TECNOLOGIAS]" -ForegroundColor Yellow
$pythonVersion = Get-CommandVersion "python"
$pipVersion    = Get-CommandVersion "pip"
$chocoVersion  = Get-CommandVersion "choco"

Write-Host "Python        : $pythonVersion"
Write-Host "Pip           : $pipVersion"
Write-Host "Chocolatey    : $chocoVersion"
Write-Host ""

# ------------------------------------------------------------
# 3. INVENTARIO - POSTMAN
# ------------------------------------------------------------
Write-Host "[SOFTWARE]" -ForegroundColor Yellow

$postmanPaths = @(
    "$env:LOCALAPPDATA\Postman\Postman.exe",
    "$env:LOCALAPPDATA\Postman\app-*\Postman.exe",
    "$env:ProgramFiles\Postman\Postman.exe",
    "${env:ProgramFiles(x86)}\Postman\Postman.exe"
)

$postmanExe = $null
foreach ($path in $postmanPaths) {
    $found = Get-ChildItem -Path $path -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { $postmanExe = $found.FullName; break }
}

if ($postmanExe) {
    $postmanInstalled = "SIM"
    try { $postmanVersion = (Get-Item $postmanExe).VersionInfo.ProductVersion }
    catch { $postmanVersion = "DESCONHECIDA" }
} else {
    $postmanInstalled = "NAO"
    $postmanVersion = "-"
}
Write-Host "Postman       : $postmanInstalled ($postmanVersion)"

# ------------------------------------------------------------
# 4. INVENTARIO - VS CODE
# ------------------------------------------------------------
$vscodeCommands = @("code", "code-insiders")
$vscodeCommand = $null

foreach ($commandName in $vscodeCommands) {
    $command = Get-Command $commandName -ErrorAction SilentlyContinue
    if ($command) { $vscodeCommand = $command; break }
}

if ($vscodeCommand) {
    $vscodeInstalled = "SIM"
    try {
        $vscodeVersionOutput = & $vscodeCommand.Source "--version" 2>&1
        $vscodeVersion = ($vscodeVersionOutput -split "`r?`n").Trim()[0]
    } catch { $vscodeVersion = "DESCONHECIDA" }
} else {
    $vscodePaths = @(
        "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe",
        "$env:ProgramFiles\Microsoft VS Code\Code.exe"
    )
    $vscodeExe = $null
    foreach ($path in $vscodePaths) {
        if (Test-PathStatus $path) { $vscodeExe = $path; break }
    }
    if ($vscodeExe) {
        $vscodeInstalled = "SIM"
        try { $vscodeVersion = (Get-Item $vscodeExe).VersionInfo.ProductVersion }
        catch { $vscodeVersion = "DESCONHECIDA" }
    } else {
        $vscodeInstalled = "NAO"
        $vscodeVersion = "-"
    }
}
Write-Host "VS Code       : $vscodeInstalled ($vscodeVersion)"
Write-Host ""

# ------------------------------------------------------------
# 5. CONFIRMACAO DO RESET
# ------------------------------------------------------------
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "          RESET DOS PROGRAMAS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$credentialTargets = @(
    "git:",
    "github",
    "vscode",
    "MicrosoftAccount"
)

Write-Host "O reset ira remover apenas os dados de usuario e credenciais:" -ForegroundColor Yellow
Write-Host "  -> VS Code Perfil     : $env:APPDATA\Code"
Write-Host "  -> VS Code Extensoes  : $env:USERPROFILE\.vscode\extensions"
Write-Host "  -> Postman Dados      : $env:APPDATA\Postman"
Write-Host "  -> Credenciais Win    : GitHub, VS Code (cmdkey)"
Write-Host ""

$confirmation = Read-Host "Deseja realizar o reset? (S/N)"

if ($confirmation -match "^[Ss]$") {

    # --------------------------------------------------------
    # 6. ENCERRAMENTO INTELIGENTE DOS PROCESSOS
    # --------------------------------------------------------
    Write-Host ""
    Write-Host "Encerrando aplicacoes de forma segura..." -ForegroundColor Yellow
    
    $processesToStop = @("Code", "code-insiders", "Postman")
    $stopResult = Stop-Application -ProcessNames $processesToStop -TimeoutSeconds 10

    if (-not $stopResult) {
        Write-Host "Aviso: Alguns processos demoraram para encerrar. Tentando prosseguir..." -ForegroundColor DarkYellow
    }

    # --------------------------------------------------------
    # 7. EXECUCAO DO RESET (CONSERVADOR)
    # --------------------------------------------------------
    Write-Host ""
    Write-Host "[EXECUTANDO LIMPEZA]" -ForegroundColor Yellow

    $postmanDataResult      = Remove-Folder "$env:APPDATA\Postman"
    $vscodeCodeResult       = Remove-Folder "$env:APPDATA\Code"
    $vscodeExtensionsResult = Remove-Folder "$env:USERPROFILE\.vscode\extensions"

    Write-Host "Postman Dados      : $postmanDataResult"
    Write-Host "VS Code Perfil     : $vscodeCodeResult"
    Write-Host "VS Code Extensoes  : $vscodeExtensionsResult"

    Write-Host ""
    Write-Host "[LIMPANDO CREDENCIAIS DO WINDOWS]" -ForegroundColor Yellow

    $windowsCredentialsResult = Remove-WindowsCredentials -Targets $credentialTargets

    Write-Host "Credenciais Windows : $windowsCredentialsResult"
}
else {
    Write-Host ""
    Write-Host "Reset cancelado pelo operador." -ForegroundColor Yellow
    $postmanDataResult        = "NAO_REALIZADO"
    $vscodeCodeResult         = "NAO_REALIZADO"
    $vscodeExtensionsResult   = "NAO_REALIZADO"
    $windowsCredentialsResult = "NAO_REALIZADO"
}

# ------------------------------------------------------------
# 8. MONTAR RESULTADO E SALVAR NO RENTRY.CO
# ------------------------------------------------------------
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "              RESULTADO" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

$result = "COMP_$computerName | usuario=$userName | python=$pythonVersion | pip=$pipVersion | choco=$chocoVersion | postman=$postmanInstalled | postman_version=$postmanVersion | postman_data=$postmanDataResult | vscode=$vscodeInstalled | vscode_version=$vscodeVersion | vscode_code=$vscodeCodeResult | vscode_extensions=$vscodeExtensionsResult | windows_credentials=$windowsCredentialsResult"

Write-Host $result -ForegroundColor White

# Copia para a area de transferencia
try {
    Set-Clipboard -Value $result -ErrorAction SilentlyContinue
    Write-Host ""
    Write-Host "[✓] Resultado copiado para a area de transferencia!" -ForegroundColor Green
} catch {}



try {
    # Garante o uso de TLS 1.2 para conexao HTTPS segura
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # Cabeçalhos HTTP para evitar bloqueios de Referer / User-Agent pelo Rentry
    $headers = @{
        "Referer"    = "https://rentry.co/"
        "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
    }

    # 1. Obtem o conteudo atual do Rentry para nao sobrescrever
    $rawUrl = "https://rentry.co/api/raw/$rentryEntryUrl"
    $conteudoAtual = ""
    try {
        $responseRaw = Invoke-RestMethod -Uri $rawUrl -Method Get -Headers $headers -ErrorAction Stop
        if ($responseRaw -and $responseRaw.status -eq "200") {
            $conteudoAtual = $responseRaw.content
        }
    } catch {
        $conteudoAtual = ""
    }

    # 2. Concatena o novo resultado ao final
    if ([string]::IsNullOrWhiteSpace($conteudoAtual)) {
        $novoConteudo = $result
    } else {
        $novoConteudo = "$conteudoAtual`n$result"
    }

    # 3. Envia o texto atualizado via API do Rentry
    $body = @{
        entry_url = $rentryEntryUrl
        edit_code = $rentryEditCode
        text      = $novoConteudo
    }

    $editUrl = "https://rentry.co/api/edit"
    $editResponse = Invoke-RestMethod -Uri $editUrl -Method Post -Headers $headers -Body $body -ErrorAction Stop

    if ($editResponse.status -eq "200") {
        Write-Host "[✓] Resultado salvo com sucesso em https://rentry.co/$rentryEntryUrl" -ForegroundColor Green
    } else {
        Write-Host "[X] Rentry retornou erro ao salvar os dados." -ForegroundColor Red
    }
} catch {
    Write-Host "[X] Falha ao conectar ao Rentry.co: $_" -ForegroundColor Red
}

# ------------------------------------------------------------
# 9. FINALIZACAO
# ------------------------------------------------------------
Write-Host ""
Write-Host "Pressione ENTER para finalizar..."
Read-Host
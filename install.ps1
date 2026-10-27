# UniCIVE - Instalador do Hermes Agent + Pauta (Windows)
# Uso:  iex (irm https://raw.githubusercontent.com/lfcanhete/unicive-hermes/main/install.ps1)
# Este script nunca usa "exit", para nao fechar a janela do PowerShell.

$ErrorActionPreference = "Stop"
$Repo   = "https://raw.githubusercontent.com/lfcanhete/unicive-hermes/main"
$Modelo = "claude-sonnet-4-6"
# categoria\nome de cada skill extra
$Skills = @("productivity\resumo-reuniao", "productivity\oficio-institucional")
$Local  = if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot "SOUL.md"))) { $PSScriptRoot } else { $null }

function Passo($n, $msg) { Write-Host "`n[$n/5] $msg" -ForegroundColor Cyan }
function Pegar($rel, $destino) {
    New-Item -ItemType Directory -Force -Path (Split-Path $destino) | Out-Null
    if ($Local) { Copy-Item (Join-Path $Local $rel) $destino -Force }
    else { Invoke-WebRequest "$Repo/$rel" -OutFile $destino -UseBasicParsing }
}

try {
    $HermesHome = if ($env:HERMES_HOME) { $env:HERMES_HOME } else { Join-Path $env:LOCALAPPDATA "hermes" }
    $HermesExe  = Join-Path $HermesHome "bin\hermes.exe"

    # O instalador oficial pode deixar so o hermes.cmd dentro da pasta do projeto.
    $HermesCmd = Join-Path $HermesHome "hermes-agent\.hermes\bin\hermes.cmd"

    function AcharHermes {
        if (Test-Path $HermesExe) { return $HermesExe }
        $cmd = Get-Command hermes -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
        if (Test-Path $HermesCmd) { return $HermesCmd }
        return $null
    }

    Passo 1 "Instalando o Hermes (pode levar alguns minutos)"
    if (-not (AcharHermes)) {
        # O instalador oficial fecha a janela ao terminar; roda em um processo separado.
        powershell -NoProfile -ExecutionPolicy Bypass -Command "iex (irm https://hermes-agent.nousresearch.com/install.ps1)"
        $env:Path = [Environment]::GetEnvironmentVariable("Path","User") + ";" + [Environment]::GetEnvironmentVariable("Path","Machine")
    } else {
        Write-Host "Hermes ja instalado."
    }
    $achado = AcharHermes
    if (-not $achado) { throw "O Hermes nao foi encontrado depois da instalacao. Feche esta janela, abra o PowerShell de novo e rode o comando outra vez." }
    $HermesExe = $achado

    # Em alguns PCs o instalador para na etapa de dependencias; o proprio Hermes sabe se reparar.
    Write-Host "Verificando a instalacao..."
    $versao = (& $HermesExe --version 2>&1 | Out-String)
    if ($versao -notmatch "Hermes Agent v") {
        Write-Host "Completando a instalacao (reparo automatico)..." -ForegroundColor Yellow
        & $HermesExe pm repair
    }
    # Deixa o comando "hermes" disponivel em novas janelas do PowerShell.
    $pasta = Split-Path $HermesExe
    $userPath = [Environment]::GetEnvironmentVariable("Path","User")
    if (-not (($userPath -split ';') -contains $pasta)) {
        [Environment]::SetEnvironmentVariable("Path", ($userPath.TrimEnd(';') + ";" + $pasta), "User")
        $env:Path += ";$pasta"
    }

    Passo 2 "Configurando o Claude como modelo"
    & $HermesExe config set model.provider anthropic
    & $HermesExe config set model.default $Modelo

    Passo 3 "Instalando a Pauta e as skills da UniCIVE"
    $soul = Join-Path $HermesHome "SOUL.md"
    if ((Test-Path $soul) -and -not (Test-Path "$soul.original")) { Copy-Item $soul "$soul.original" }
    Pegar "SOUL.md" $soul
    foreach ($s in $Skills) {
        $nome = Split-Path $s -Leaf
        Pegar "skills\$nome\SKILL.md" (Join-Path $HermesHome "skills\$s\SKILL.md")
    }

    Passo 4 "Chave de acesso ao Claude"
    $key = $env:UNICIVE_KEY
    if (-not $key) {
        try {
            $sec = Read-Host "Cole a chave que a UniCIVE te entregou (Enter para pular)" -AsSecureString
            $key = [System.Net.NetworkCredential]::new("", $sec).Password
        } catch { $key = "" }
    }
    if ($key) {
        $envFile = Join-Path $HermesHome ".env"
        $linhas = if (Test-Path $envFile) { @(Get-Content $envFile | Where-Object { $_ -notmatch '^ANTHROPIC_API_KEY=' }) } else { @() }
        $linhas += "ANTHROPIC_API_KEY=$key"
        Set-Content -Path $envFile -Value $linhas -Encoding UTF8
        Write-Host "Chave salva."
    } else {
        Write-Host "Chave nao informada. Rode de novo o instalador quando tiver a chave." -ForegroundColor Yellow
    }

    Passo 5 "Pronto"
    Write-Host "Abrindo a Pauta..." -ForegroundColor Green
    Write-Host "Na primeira conversa, diga: 'Pauta, configure meu Google Workspace'." -ForegroundColor Yellow
    & $HermesExe
}
catch {
    Write-Host "`nERRO: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Tire uma foto desta tela e envie para o suporte."
}

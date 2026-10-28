# UniCIVE - Instalador do Hermes Agent + Pauta (Windows)
# Uso:  iex (irm https://raw.githubusercontent.com/lfcanhete/unicive-hermes/main/install.ps1)
# Este script nunca usa "exit", para nao fechar a janela do PowerShell.

# Continue: no PowerShell 5.1 o stderr de programas externos (ex.: aviso do hermes) viraria erro fatal com "Stop".
$ErrorActionPreference = "Continue"
$Repo   = "https://raw.githubusercontent.com/lfcanhete/unicive-hermes/main"
$Modelo = "claude-sonnet-5-5"
# categoria\nome de cada skill extra
$Skills = @("productivity\resumo-reuniao", "productivity\oficio-institucional")
$Local  = if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot "SOUL.md"))) { $PSScriptRoot } else { $null }

function Passo($n, $msg) { Write-Host "`n[$n/5] $msg" -ForegroundColor Cyan }
function Pegar($rel, $destino) {
    New-Item -ItemType Directory -Force -Path (Split-Path $destino) -ErrorAction Stop | Out-Null
    if ($Local) { Copy-Item (Join-Path $Local $rel) $destino -Force -ErrorAction Stop }
    else { Invoke-WebRequest "$Repo/$rel" -OutFile $destino -UseBasicParsing -ErrorAction Stop }
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

    # Aplicativo (Hermes Desktop): se o instalador oficial parou antes dele, refaz so essa parte.
    $instLocal = Join-Path $HermesHome "hermes-agent\scripts\install.ps1"
    $atalho = Join-Path ([Environment]::GetFolderPath("Desktop")) "Hermes.lnk"
    $appExe = Join-Path $HermesHome "hermes-agent\apps\desktop\release\win-unpacked\Hermes.exe"
    if ((Test-Path $instLocal) -and -not (Test-Path $atalho)) {
        Write-Host "Instalando o aplicativo Hermes Desktop (pode levar alguns minutos)..."
        # Pode terminar com erro na etapa do launcher mesmo com o app pronto; o que vale e o Hermes.exe.
        if (Test-Path (Join-Path $HermesHome ".hermes-update-in-progress")) { Remove-Item (Join-Path $HermesHome ".hermes-update-in-progress") -Force -ErrorAction SilentlyContinue }
        powershell -NoProfile -ExecutionPolicy Bypass -File $instLocal -Stage products -IncludeDesktop
    }
    if ((Test-Path $appExe) -and -not (Test-Path $atalho)) {
        $ws = New-Object -ComObject WScript.Shell
        foreach ($dir in @([Environment]::GetFolderPath("Desktop"), [Environment]::GetFolderPath("Programs"))) {
            $sc = $ws.CreateShortcut((Join-Path $dir "Hermes.lnk")); $sc.TargetPath = $appExe; $sc.WorkingDirectory = Split-Path $appExe; $sc.Save()
        }
        Write-Host "Atalho do Hermes criado na area de trabalho." -ForegroundColor Green
    }

    Passo 2 "Configurando o Claude como modelo"
    & $HermesExe config set model.provider anthropic
    & $HermesExe config set model.default $Modelo
    # Respostas mais rapidas e menos uso da cota do plano: raciocinio baixo e sem chamada extra para titulo.
    & $HermesExe config set --force agent.reasoning_effort low
    & $HermesExe config set auxiliary.title_generation.enabled false

    Passo 3 "Instalando a Pauta e as skills da UniCIVE"
    $soul = Join-Path $HermesHome "SOUL.md"
    if ((Test-Path $soul) -and -not (Test-Path "$soul.original")) { Copy-Item $soul "$soul.original" }
    Pegar "SOUL.md" $soul
    foreach ($s in $Skills) {
        $nome = Split-Path $s -Leaf
        Pegar "skills\$nome\SKILL.md" (Join-Path $HermesHome "skills\$s\SKILL.md")
    }

    Passo 4 "Credenciais (Claude e Google)"
    $semBom = New-Object System.Text.UTF8Encoding($false)
    # Chave do Claude (opcional): se a UniCIVE enviar UNICIVE_KEY no comando, usa a chave;
    # senao abre o login do Claude no navegador.
    $key = $env:UNICIVE_KEY
    if (-not $key) {
        Write-Host "Vai abrir o navegador: entre com a sua conta do Claude e autorize." -ForegroundColor Yellow
        & $HermesExe auth add anthropic --type oauth
    }
    if ($key) {
        $envFile = Join-Path $HermesHome ".env"
        $linhas = if (Test-Path $envFile) { @(Get-Content $envFile | Where-Object { $_ -notmatch '^ANTHROPIC_API_KEY=' }) } else { @() }
        $linhas += "ANTHROPIC_API_KEY=$key"
        [System.IO.File]::WriteAllLines($envFile, [string[]]$linhas, $semBom)
        Write-Host "Chave do Claude salva."
    }
    # Cliente OAuth do Google da UniCIVE (UNICIVE_GOOGLE = arquivo client_secret.json em base64).
    if ($env:UNICIVE_GOOGLE) {
        $json = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($env:UNICIVE_GOOGLE))
        if ($json -notmatch '"installed"') { throw "UNICIVE_GOOGLE nao parece um client_secret.json do Google." }
        [System.IO.File]::WriteAllText((Join-Path $HermesHome "google_client_secret.json"), $json, $semBom)
        Write-Host "Cliente do Google instalado."
    }

    Passo 5 "Pronto"
    $primeira = Join-Path $HermesHome "primeira-mensagem.txt"
    Pegar "primeira-mensagem.txt" $primeira
    Write-Host "Abrindo a Pauta..." -ForegroundColor Green
    & $HermesExe chat --query-file $primeira
}
catch {
    Write-Host "`nERRO: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Tire uma foto desta tela e envie para o suporte."
}

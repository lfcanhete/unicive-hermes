# UniCIVE · Instalador do Hermes Agent (Windows)
# Uso:  iex (irm https://raw.githubusercontent.com/canhetejr/unicive-hermes/main/install.ps1)

$ErrorActionPreference = "Stop"
$Repo = "https://raw.githubusercontent.com/canhetejr/unicive-hermes/main"
$Skills = @("pauta", "resumo-reuniao", "oficio-institucional")

function Passo($n, $msg) { Write-Host "`n[$n] $msg" -ForegroundColor Cyan }

Passo 1 "Instalando o Hermes Agent (instalador oficial)"
if (-not (Get-Command hermes -ErrorAction SilentlyContinue)) {
    iex (irm https://hermes-agent.nousresearch.com/install.ps1)
    # recarrega o PATH da sessao atual
    $env:Path = [Environment]::GetEnvironmentVariable("Path","User") + ";" + [Environment]::GetEnvironmentVariable("Path","Machine")
} else {
    Write-Host "Hermes ja instalado, pulando."
}

Passo 2 "Aplicando configuracoes padrao da UniCIVE"
hermes config set model claude-sonnet-4-5
# Ajuste as chaves abaixo conforme `hermes config` mostrar na sua versao:
# hermes config set language pt-BR

Passo 3 "Instalando skills da UniCIVE"
$tmp = Join-Path $env:TEMP "unicive-skills"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
foreach ($s in $Skills) {
    $dir = Join-Path $tmp $s
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Invoke-WebRequest "$Repo/skills/$s/SKILL.md" -OutFile (Join-Path $dir "SKILL.md")
    hermes skills install $dir
}

Passo 4 "Login no Claude (abre o navegador)"
Write-Host "Escolha 'Anthropic' e depois 'OAuth login' (ou cole a chave da API da UniCIVE)."
hermes model

Passo 5 "Verificando a instalacao"
hermes doctor

Write-Host "`nPronto! Abra o Hermes Desktop ou digite 'hermes' no terminal." -ForegroundColor Green
Write-Host "Proximo passo: diga ao Hermes 'Use a skill pauta e configure meu Google Workspace'." -ForegroundColor Yellow

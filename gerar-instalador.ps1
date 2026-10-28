# Uso (somente por quem administra a oficina):
#   .\gerar-instalador.ps1 -ClientSecret "C:\caminho\client_secret.json" [-Saida "C:\caminho\Instalar-Assessor.cmd"]
# Gera o Instalar-Assessor.cmd que os diretores baixam e abrem com dois cliques. Ele abre o instalador visual
# (instalador.ps1, baixado do GitHub). Com -ClientSecret, o Google ja vem configurado dentro do arquivo:
# nesse caso o .cmd e de uso interno e NAO pode ir para este repositorio nem para um site publico.
param(
    [string] $ClientSecret,
    [string] $Saida = (Join-Path (Get-Location) "Instalar-Assessor.cmd")
)
$url = "https://raw.githubusercontent.com/lfcanhete/unicive-hermes/main/instalador.ps1"
$linhas = @(
    "@echo off",
    "title Instalador do Assessor - UNICIVE",
    "echo Abrindo o instalador do Assessor. Aguarde..."
)
if ($ClientSecret) {
    $b64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes((Resolve-Path $ClientSecret)))
    $linhas += "set ""UNICIVE_GOOGLE=$b64"""
}
# Se o download falhar ou a janela nao abrir, a janela preta fica aberta explicando o motivo.
$ps = "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; " +
      "`$f = Join-Path `$env:TEMP 'instalador-assessor.ps1'; " +
      "try { Invoke-WebRequest '$url' -OutFile `$f -UseBasicParsing -ErrorAction Stop } " +
      "catch { Write-Host ''; Write-Host 'Nao consegui baixar o instalador do GitHub.' -ForegroundColor Red; Write-Host `$_.Exception.Message; " +
      "Write-Host 'A rede pode estar bloqueando o github.com. Tente em outra rede (por exemplo, o roteador do celular).'; exit 1 }; " +
      "& `$f; " +
      "if (-not `$global:UniciveJanelaAbriu) { Write-Host ''; Write-Host 'A janela do instalador nao abriu.' -ForegroundColor Red; " +
      "`$Error | Select-Object -First 5 | ForEach-Object { Write-Host `$_ }; exit 1 }"
$linhas += @(
    "set ""UNICIVE_LAUNCHER=1""",
    "powershell -NoProfile -ExecutionPolicy Bypass -STA -Command ""$ps""",
    "if errorlevel 1 pause"
)
[System.IO.File]::WriteAllLines($Saida, [string[]]$linhas, [System.Text.Encoding]::ASCII)
Write-Host "Instalador gerado: $Saida"
if ($ClientSecret) { Write-Host "Contem a configuracao do Google: uso interno, nao publique em repositorio ou site aberto." }

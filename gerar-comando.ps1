# Uso (somente por quem administra a oficina, NUNCA publicar o resultado):
#   .\gerar-comando.ps1 -ClientSecret "C:\caminho\client_secret.json" [-Chave "sk-ant-..."]
# Gera a linha unica que os diretores colam no PowerShell e a copia para a area de transferencia.
param(
    [string] $Chave,
    [string] $ClientSecret
)
if (-not $Chave -and -not $ClientSecret) { Write-Host "Informe -ClientSecret e/ou -Chave."; return }
$url = "https://raw.githubusercontent.com/lfcanhete/unicive-hermes/main/install.ps1"
$linha = ""
if ($Chave) { $linha += "`$env:UNICIVE_KEY='$Chave'; " }
if ($ClientSecret) {
    $b64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes((Resolve-Path $ClientSecret)))
    $linha += "`$env:UNICIVE_GOOGLE='$b64'; "
}
$linha += "iex (irm $url)"
Set-Clipboard $linha
Write-Host "Comando copiado para a area de transferencia ($($linha.Length) caracteres)."
Write-Host "Envie por um canal privado (e-mail institucional ou mensagem direta). Nao coloque em repositorio, slide ou grupo aberto."

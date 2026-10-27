# Uso (somente por quem administra a oficina, NUNCA publicar o resultado):
#   .\gerar-comando.ps1 -Chave "sk-ant-..." -ClientSecret "C:\caminho\client_secret.json"
# Gera a linha unica que os diretores colam no PowerShell e a copia para a area de transferencia.
param(
    [Parameter(Mandatory)] [string] $Chave,
    [string] $ClientSecret
)
$url = "https://raw.githubusercontent.com/lfcanhete/unicive-hermes/main/install.ps1"
$linha = "`$env:UNICIVE_KEY='$Chave'; "
if ($ClientSecret) {
    $b64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes((Resolve-Path $ClientSecret)))
    $linha += "`$env:UNICIVE_GOOGLE='$b64'; "
}
$linha += "iex (irm $url)"
Set-Clipboard $linha
Write-Host "Comando copiado para a area de transferencia ($($linha.Length) caracteres)."
Write-Host "Envie por um canal privado (e-mail institucional ou mensagem direta). Nao coloque em repositorio, slide ou grupo aberto."

@echo off
rem UNICIVE - Instalador do Assessor. Usa o curl do Windows, o Hermes-Setup.exe oficial (assinado pela
rem Nous Research; se falhar, o instalador oficial pelo PowerShell) e o assistente em Python do proprio Hermes.
title Instalador do Assessor - UNICIVE
setlocal
set "HH=%LOCALAPPDATA%\hermes"
set "AS=%TEMP%\assistente-assessor-%RANDOM%%RANDOM%.py"
echo.
echo   Instalador do Assessor - UNICIVE
echo.
if exist "%HH%\bin\hermes.exe" goto assistente

echo   [1/2] Instalando o Hermes oficial (Nous Research).
echo         Uma janela de instalacao vai abrir: siga ate o fim. Depois esta janela continua sozinha.
curl -fsSL -o "%TEMP%\Hermes-Setup.exe" "https://hermes-assets.nousresearch.com/Hermes-Setup.exe" || goto erro_rede
start "" /wait "%TEMP%\Hermes-Setup.exe"
echo         Aguardando o Hermes terminar de instalar...
set /a N=0
:esperar
if exist "%HH%\bin\hermes.exe" goto assistente
set /a N+=1
if %N% gtr 6 goto plano_b
ping -n 6 127.0.0.1 >nul
goto esperar

:plano_b
rem O instalador com janela grava um script que o antivirus pode bloquear ("Install didn't finish").
rem O instalador oficial pelo PowerShell roda direto da internet, sem gravar esse script no disco.
echo.
echo         O instalador com janela nao terminou. Tentando o instalador oficial pelo PowerShell...
echo         (pode levar alguns minutos; nao feche esta janela)
taskkill /f /im Hermes-Setup.exe >nul 2>&1
if exist "%HH%\bootstrap-cache" ren "%HH%\bootstrap-cache" "bootstrap-cache.velho-%RANDOM%" >nul 2>&1
set "HERMES_NONINTERACTIVE=1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol='Tls12'; iex (irm https://hermes-agent.nousresearch.com/install.ps1)"
set "HERMES_NONINTERACTIVE="
if exist "%HH%\bin\hermes.exe" goto assistente
goto erro_hermes

:assistente
set "PY="
for /d %%D in ("%HH%\tools\python-*") do if exist "%%D\pythonw.exe" set "PY=%%D\pythonw.exe"
if not defined PY for /r "%HH%\installs" %%F in (pythonw.exe) do if exist "%%F" set "PY=%%F"
if not defined PY goto erro_python
echo   [2/2] Abrindo o assistente do Assessor...
curl -fsSL -o "%AS%" "https://raw.githubusercontent.com/lfcanhete/unicive-hermes/main/assistente.py" || goto erro_rede
if not exist "%AS%" goto erro_antivirus
start "" "%PY%" -I "%AS%"
exit /b 0

:erro_rede
echo.
echo   Nao consegui baixar da internet. Confira a conexao e tente de novo.
pause
exit /b 1
:erro_hermes
echo.
echo   O instalador oficial do Hermes nao terminou (por exemplo: "Install didn't finish").
echo   1. Feche o Hermes, inclusive o icone perto do relogio.
echo   2. Baixe e rode o Remover-Hermes.cmd: https://lfcanhete.github.io/unicive-hermes/Remover-Hermes.cmd
echo   3. Abra este instalador de novo.
pause
exit /b 1
:erro_python
echo.
echo   Nao encontrei o Python do Hermes. Feche esta janela e abra o instalador de novo.
pause
exit /b 1
:erro_antivirus
echo.
echo   O Windows nao deixou salvar o assistente (normalmente e o antivirus). Tente de novo.
pause
exit /b 1

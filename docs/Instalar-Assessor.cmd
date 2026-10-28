@echo off
rem UNICIVE - Instalador do Assessor. Sem PowerShell: usa o curl do Windows, o Hermes-Setup.exe oficial
rem (assinado pela Nous Research) e o assistente em Python que roda no Python do proprio Hermes.
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
if %N% gtr 180 goto erro_hermes
ping -n 6 127.0.0.1 >nul
goto esperar

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
echo   O Hermes nao terminou de instalar. Feche esta janela e abra o instalador de novo.
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

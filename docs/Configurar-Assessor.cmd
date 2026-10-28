@echo off
rem UNICIVE - Configurador do Assessor. Nao instala nem remove o Hermes: ele e instalado do jeito original,
rem pelo site oficial da Nous Research. Aqui so abre o assistente que configura o Assessor no Hermes.
title Configurar o Assessor - UNICIVE
setlocal
set "HH=%LOCALAPPDATA%\hermes"
set "AS=%TEMP%\assistente-assessor-%RANDOM%%RANDOM%.py"
echo.
echo   Configurar o Assessor - UNICIVE
echo.
set "OK="
if exist "%HH%\bin\hermes.exe" (
    "%HH%\bin\hermes.exe" --version 2>nul | findstr /c:"Hermes Agent v" >nul && set "OK=1"
)
if not defined OK goto sem_hermes

set "PY="
for /d %%D in ("%HH%\tools\python-*") do if exist "%%D\pythonw.exe" set "PY=%%D\pythonw.exe"
if not defined PY for /r "%HH%\installs" %%F in (pythonw.exe) do if exist "%%F" set "PY=%%F"
if not defined PY goto sem_hermes
echo   Abrindo o assistente do Assessor...
curl -fsSL -o "%AS%" "https://raw.githubusercontent.com/lfcanhete/unicive-hermes/main/assistente.py" || goto erro_rede
if not exist "%AS%" goto erro_antivirus
start "" "%PY%" -I "%AS%"
exit /b 0

:sem_hermes
echo   O Hermes ainda nao esta instalado (ou nao esta funcionando) neste computador.
echo.
echo   1. Instale o Hermes pelo site oficial da Nous Research (a pagina vai abrir agora).
echo   2. Abra o Hermes uma vez e espere ele terminar de preparar tudo.
echo   3. Abra este arquivo de novo para configurar o Assessor.
echo.
start "" "https://hermes-agent.nousresearch.com/desktop"
pause
exit /b 1

:erro_rede
echo.
echo   Nao consegui baixar o assistente da internet. Confira a conexao e tente de novo.
pause
exit /b 1
:erro_antivirus
echo.
echo   O Windows nao deixou salvar o assistente (normalmente e o antivirus). Tente de novo.
pause
exit /b 1

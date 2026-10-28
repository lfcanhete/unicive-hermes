@echo off
rem UNICIVE - Remove uma instalacao antiga ou quebrada do Hermes, para instalar de novo do zero.
rem Sem PowerShell. A pasta do Hermes vai para um backup (fica so o mais recente); o Claude Code fica.
title Remover o Hermes - UNICIVE
setlocal EnableExtensions
set "HH=%LOCALAPPDATA%\hermes"
if defined HERMES_HOME set "HH=%HERMES_HOME%"
echo.
echo   Remover o Hermes - UNICIVE
echo.
echo   Isto fecha o Hermes e guarda a instalacao atual num backup:
echo   %HH%
echo   Depois rode o Instalar-Assessor de novo. Os logins (Claude, Google e Telegram)
echo   e as preferencias do Assessor terao de ser feitos outra vez.
echo.
choice /c SN /m "  Continuar"
if errorlevel 2 goto fim

echo.
echo   [1/4] Fechando o Hermes...
if exist "%HH%\bin\hermes.exe" "%HH%\bin\hermes.exe" gateway stop >nul 2>&1
if not defined UNICIVE_TESTE taskkill /f /im Hermes.exe >nul 2>&1
ping -n 4 127.0.0.1 >nul

echo   [2/4] Tirando o Hermes da inicializacao do Windows e os atalhos...
if not defined UNICIVE_TESTE (
    del /q "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Hermes_Gateway*" >nul 2>&1
    del /q "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Atualizar-Claude-Code.vbs" >nul 2>&1
    del /q "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Assessor-Telegram.cmd" >nul 2>&1
    del /q "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Hermes.lnk" >nul 2>&1
    del /q "%USERPROFILE%\Desktop\Hermes.lnk" >nul 2>&1
    if defined OneDrive del /q "%OneDrive%\Desktop\Hermes.lnk" >nul 2>&1
)

echo   [3/4] Limpando Python incompleto...
rem Python do uv registrado como instalado mas sem o python.exe: o instalador do Hermes falharia.
rem rmdir sem /s apaga so o atalho (junction); se for pasta de verdade, apaga com o conteudo.
for /d %%D in ("%APPDATA%\uv\python\cpython-*") do (
    if not exist "%%D\python.exe" (
        rmdir "%%D" >nul 2>&1 || rmdir /s /q "%%D" >nul 2>&1
    )
)

echo   [4/4] Guardando a instalacao atual num backup...
if not exist "%HH%" goto pronto
for %%P in ("%HH%") do (set "PAI=%%~dpP" & set "NOME=%%~nxP")
for /d %%B in ("%PAI%%NOME%.backup-*") do (
    echo         Apagando o backup antigo %%~nxB...
    rmdir /s /q "%%B" >nul 2>&1
)
set "CARIMBO=%date%-%time%"
set "CARIMBO=%CARIMBO:/=%"
set "CARIMBO=%CARIMBO::=%"
set "CARIMBO=%CARIMBO:.=%"
set "CARIMBO=%CARIMBO:,=%"
set "CARIMBO=%CARIMBO: =0%"
set /a T=0
:renomear
ren "%HH%" "%NOME%.backup-%CARIMBO%" >nul 2>&1
if not exist "%HH%" goto guardado
set /a T+=1
if %T% geq 6 goto erro_preso
if not defined UNICIVE_TESTE taskkill /f /im Hermes.exe >nul 2>&1
ping -n 4 127.0.0.1 >nul
goto renomear

:guardado
echo         Backup: %PAI%%NOME%.backup-%CARIMBO%
:pronto
echo.
echo   Pronto. Agora abra o Instalar-Assessor de novo.
echo.
pause
exit /b 0

:erro_preso
echo.
echo   Algum programa ainda esta usando a pasta do Hermes.
echo   Feche o Hermes (inclusive o icone perto do relogio), ou reinicie o computador, e rode este arquivo de novo.
echo.
pause
exit /b 1

:fim
echo   Nada foi alterado.
pause
exit /b 0

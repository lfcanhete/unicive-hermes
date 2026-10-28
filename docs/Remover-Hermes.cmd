@echo off
rem UNICIVE - Limpeza completa do Hermes, para instalar de novo do zero sem restos que travem a instalacao.
rem Apaga o Hermes, os dados do aplicativo, o Python que ele usa, os restos do instalador oficial, a
rem inicializacao automatica e os atalhos. Nao mexe no Claude Code.
title Remover o Hermes - UNICIVE
setlocal EnableExtensions
set "HH=%LOCALAPPDATA%\hermes"
if defined HERMES_HOME set "HH=%HERMES_HOME%"
set "INI=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
echo.
echo   Remover o Hermes - limpeza completa - UNICIVE
echo.
echo   Isto APAGA o Hermes deste computador, sem backup:
echo     - a instalacao, as conversas, a memoria e os logins do Assessor
echo     - o aplicativo Hermes, o Python que ele usa e os restos de instalacoes anteriores
echo     - o Telegram ligando com o Windows e os atalhos
echo   O Claude Code nao e removido. Depois abra o Instalar-Assessor de novo.
echo.
choice /c SN /m "  Apagar tudo"
if errorlevel 2 goto fim

echo.
echo   [1/5] Fechando o Hermes...
if exist "%HH%\bin\hermes.exe" "%HH%\bin\hermes.exe" gateway stop >nul 2>&1
call :fechar
echo   [2/5] Tirando o Hermes da inicializacao do Windows e os atalhos...
if not defined UNICIVE_TESTE (
    del /q "%INI%\Hermes_Gateway*" >nul 2>&1
    del /q "%INI%\Assessor-Telegram.cmd" >nul 2>&1
    del /q "%INI%\Atualizar-Claude-Code.vbs" >nul 2>&1
    del /q "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Hermes.lnk" >nul 2>&1
    rmdir /s /q "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Hermes" >nul 2>&1
    del /q "%USERPROFILE%\Desktop\Hermes.lnk" >nul 2>&1
    if defined OneDrive del /q "%OneDrive%\Desktop\Hermes.lnk" >nul 2>&1
    for /f "tokens=1 delims=," %%T in ('schtasks /query /fo csv /nh 2^>nul ^| findstr /i "hermes"') do schtasks /delete /tn %%T /f >nul 2>&1
)

echo   [3/5] Apagando o Hermes (pode levar alguns minutos)...
call :apagar "%HH%"
for /d %%B in ("%HH%.backup-*" "%HH%.apagar-*") do call :apagar "%%~B"
if not defined UNICIVE_TESTE (
    call :apagar "%APPDATA%\Hermes"
    call :apagar "%LOCALAPPDATA%\com.nousresearch.hermes.setup"
    call :apagar "%LOCALAPPDATA%\Nous Research"
    call :apagar "%USERPROFILE%\.hermes"
)

echo   [4/5] Apagando o Python e o cache que o Hermes usa...
if not defined UNICIVE_TESTE (
    for /d %%D in ("%APPDATA%\uv\python\cpython-*") do (rmdir "%%D" >nul 2>&1 || rmdir /s /q "%%D" >nul 2>&1)
    call :apagar "%APPDATA%\uv\python\.temp"
    call :apagar "%LOCALAPPDATA%\uv\cache"
)

echo   [5/5] Apagando arquivos temporarios do instalador...
if not defined UNICIVE_TESTE (
    del /q "%TEMP%\Hermes-Setup.exe" "%TEMP%\assistente-assessor-*.py" "%TEMP%\instalador-assessor*" >nul 2>&1
    for /d %%D in ("%TEMP%\hermes_agy_*" "%TEMP%\hermes-dm") do rmdir /s /q "%%D" >nul 2>&1
)

if exist "%HH%" goto preso
echo.
echo   Pronto: o Hermes foi removido por completo.
echo   Agora abra o Instalar-Assessor de novo.
echo.
pause
exit /b 0

:preso
rem Algo ainda segura a pasta: tira do caminho para a instalacao nova nao travar, e apaga depois.
set "CARIMBO=%RANDOM%%RANDOM%"
ren "%HH%" "hermes.apagar-%CARIMBO%" >nul 2>&1
echo.
if exist "%HH%" (
    echo   Algum programa ainda esta usando a pasta do Hermes.
    echo   Reinicie o computador e rode este arquivo de novo antes de instalar.
) else (
    echo   Parte dos arquivos estava em uso e foi separada para apagar depois.
    echo   Pode abrir o Instalar-Assessor agora. Rode este arquivo de novo outro dia para terminar a limpeza.
)
echo.
pause
exit /b 1

:fim
echo   Nada foi alterado.
pause
exit /b 0

rem ---------- rotinas ----------
:fechar
rem Fecha o aplicativo e todo programa que esteja rodando de dentro da pasta do Hermes ou do Python dele.
if defined UNICIVE_TESTE exit /b
taskkill /f /im Hermes.exe >nul 2>&1
taskkill /f /im Hermes-Setup.exe >nul 2>&1
powershell -NoProfile -Command "Get-Process | Where-Object { $_.Path -and ($_.Path -like ($env:LOCALAPPDATA + '\hermes\*') -or $_.Path -like ($env:APPDATA + '\uv\python\*')) } | Stop-Process -Force" >nul 2>&1
ping -n 3 127.0.0.1 >nul
exit /b

:apagar
rem Apaga a pasta; se algo estiver em uso, fecha o Hermes de novo e tenta mais duas vezes.
if not exist "%~1" exit /b
for /l %%N in (1,1,3) do (
    if exist "%~1" (
        rmdir /s /q "%~1" >nul 2>&1
        if exist "%~1" (call :fechar & ping -n 3 127.0.0.1 >nul)
    )
)
exit /b

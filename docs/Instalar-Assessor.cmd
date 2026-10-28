@echo off
title Instalador do Assessor - UNICIVE
echo Abrindo o instalador do Assessor. Aguarde...
set "UNICIVE_LAUNCHER=1"
powershell -NoProfile -ExecutionPolicy Bypass -STA -Command "$f = Join-Path $env:TEMP 'instalador-assessor.ps1'; Invoke-WebRequest 'https://raw.githubusercontent.com/lfcanhete/unicive-hermes/main/instalador.ps1' -OutFile $f -UseBasicParsing; & $f"
if errorlevel 1 pause

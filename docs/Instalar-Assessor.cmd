@echo off
title Instalador do Assessor - UNICIVE
echo Abrindo o instalador do Assessor. Aguarde...
set "UNICIVE_GOOGLE=eyJpbnN0YWxsZWQiOnsiY2xpZW50X2lkIjoiMzU2NDQ0MTk2MjMzLWVzOTZqazljZHVnZGkydGtuM2RqcWNkZDYxYzUzM3Q4LmFwcHMuZ29vZ2xldXNlcmNvbnRlbnQuY29tIiwicHJvamVjdF9pZCI6Imhlcm1lcy1kaXJlY2FvIiwiYXV0aF91cmkiOiJodHRwczovL2FjY291bnRzLmdvb2dsZS5jb20vby9vYXV0aDIvYXV0aCIsInRva2VuX3VyaSI6Imh0dHBzOi8vb2F1dGgyLmdvb2dsZWFwaXMuY29tL3Rva2VuIiwiYXV0aF9wcm92aWRlcl94NTA5X2NlcnRfdXJsIjoiaHR0cHM6Ly93d3cuZ29vZ2xlYXBpcy5jb20vb2F1dGgyL3YxL2NlcnRzIiwiY2xpZW50X3NlY3JldCI6IkdPQ1NQWC1QRnBSOGZES1FsbFh0alF6R2hzU0QxbXJqV0hyIiwicmVkaXJlY3RfdXJpcyI6WyJodHRwOi8vbG9jYWxob3N0Il19fQ=="
set "UNICIVE_LAUNCHER=1"
powershell -NoProfile -ExecutionPolicy Bypass -STA -Command "$f = Join-Path $env:TEMP 'instalador-assessor.ps1'; Invoke-WebRequest 'https://raw.githubusercontent.com/lfcanhete/unicive-hermes/main/instalador.ps1' -OutFile $f -UseBasicParsing; & $f"
if errorlevel 1 pause

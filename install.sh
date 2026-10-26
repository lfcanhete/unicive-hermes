#!/usr/bin/env bash
# UniCIVE · Instalador do Hermes Agent (macOS / Linux / WSL2)
# Uso:  curl -fsSL https://raw.githubusercontent.com/lfcanhete/unicive-hermes/main/install.sh | bash
set -euo pipefail

REPO="https://raw.githubusercontent.com/lfcanhete/unicive-hermes/main"
SKILLS=(pauta resumo-reuniao oficio-institucional)

passo() { printf '\n\033[36m[%s] %s\033[0m\n' "$1" "$2"; }

passo 1 "Instalando o Hermes Agent (instalador oficial)"
if ! command -v hermes >/dev/null 2>&1; then
  curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
  export PATH="$HOME/.local/bin:$PATH"
else
  echo "Hermes ja instalado, pulando."
fi

passo 2 "Aplicando configuracoes padrao da UniCIVE"
hermes config set model claude-sonnet-4-5

passo 3 "Instalando skills da UniCIVE"
TMP="$(mktemp -d)"
for s in "${SKILLS[@]}"; do
  mkdir -p "$TMP/$s"
  curl -fsSL "$REPO/skills/$s/SKILL.md" -o "$TMP/$s/SKILL.md"
  hermes skills install "$TMP/$s"
done

passo 4 "Login no Claude (abre o navegador)"
echo "Escolha 'Anthropic' e depois 'OAuth login' (ou cole a chave da API da UniCIVE)."
hermes model < /dev/tty

passo 5 "Verificando a instalacao"
hermes doctor

printf '\n\033[32mPronto! Digite "hermes" no terminal.\033[0m\n'
printf '\033[33mProximo passo: diga ao Hermes "Use a skill pauta e configure meu Google Workspace".\033[0m\n'

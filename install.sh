#!/usr/bin/env bash
# UniCIVE - Instalador do Hermes Agent + Pauta (macOS / Linux / WSL2)
# Uso:  curl -fsSL https://raw.githubusercontent.com/lfcanhete/unicive-hermes/main/install.sh | bash
set -uo pipefail

REPO="https://raw.githubusercontent.com/lfcanhete/unicive-hermes/main"
MODELO="claude-sonnet-5-5"
SKILLS=(resumo-reuniao oficio-institucional)
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"

passo() { printf '\n\033[36m[%s/5] %s\033[0m\n' "$1" "$2"; }
erro()  { printf '\n\033[31mERRO: %s\033[0m\nTire uma foto desta tela e envie para o suporte.\n' "$1"; exit 1; }

passo 1 "Instalando o Hermes (pode levar alguns minutos)"
export PATH="$HOME/.local/bin:$PATH"
if ! command -v hermes >/dev/null 2>&1; then
  curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
  export PATH="$HOME/.local/bin:$PATH"
fi
command -v hermes >/dev/null 2>&1 || erro "O Hermes nao foi encontrado depois da instalacao. Abra um terminal novo e rode o comando de novo."

passo 2 "Configurando o Claude como modelo"
hermes config set model.provider anthropic
hermes config set model.default "$MODELO"

passo 3 "Instalando a Pauta e as skills da UniCIVE"
mkdir -p "$HERMES_HOME"
[ -f "$HERMES_HOME/SOUL.md" ] && [ ! -f "$HERMES_HOME/SOUL.md.original" ] && cp "$HERMES_HOME/SOUL.md" "$HERMES_HOME/SOUL.md.original"
curl -fsSL "$REPO/SOUL.md" -o "$HERMES_HOME/SOUL.md"
for s in "${SKILLS[@]}"; do
  mkdir -p "$HERMES_HOME/skills/productivity/$s"
  curl -fsSL "$REPO/skills/$s/SKILL.md" -o "$HERMES_HOME/skills/productivity/$s/SKILL.md"
done

passo 4 "Chave de acesso ao Claude"
KEY="${UNICIVE_KEY:-}"
if [ -z "$KEY" ] && [ -r /dev/tty ]; then
  read -r -s -p "Cole a chave que a UniCIVE te entregou (Enter para pular): " KEY < /dev/tty; echo
fi
if [ -n "$KEY" ]; then
  touch "$HERMES_HOME/.env"; chmod 600 "$HERMES_HOME/.env"
  grep -v '^ANTHROPIC_API_KEY=' "$HERMES_HOME/.env" > "$HERMES_HOME/.env.tmp" || true
  printf 'ANTHROPIC_API_KEY=%s\n' "$KEY" >> "$HERMES_HOME/.env.tmp"
  mv "$HERMES_HOME/.env.tmp" "$HERMES_HOME/.env"; chmod 600 "$HERMES_HOME/.env"
  echo "Chave salva."
else
  echo "Chave nao informada. Rode de novo o instalador quando tiver a chave."
fi

passo 5 "Pronto"
echo "Abrindo a Pauta. Na primeira conversa, diga: 'Pauta, configure meu Google Workspace'."
exec hermes < /dev/tty

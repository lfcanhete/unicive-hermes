# UniCIVE · Hermes em 1 comando

## Windows (PowerShell)
```powershell
iex (irm https://raw.githubusercontent.com/lfcanhete/unicive-hermes/main/install.ps1)
```

## macOS / Linux
```bash
curl -fsSL https://raw.githubusercontent.com/lfcanhete/unicive-hermes/main/install.sh | bash
```

O script instala o Hermes, define o Claude como modelo, instala as skills da UniCIVE (`skills/`) e abre o login no navegador.

Para instalar o app gráfico, baixe o Hermes Desktop no site oficial; ele usa a mesma configuração.

## Pauta, a assistente da direção
A skill `skills/pauta` transforma o Hermes numa assistente executiva: briefing diário, resumo de e-mails, agenda, preparo de reuniões e rascunhos. Ela só lê e rascunha; envia, aceita convites ou apaga algo apenas com confirmação do diretor.

Depois da instalação, o diretor diz ao Hermes:
1. "Use a skill pauta e configure meu Google Workspace" (o Hermes guia o login do Google passo a passo).
2. "Pauta, me conheça": ela pergunta preferências e guarda na memória.
3. Em linguagem natural, agenda as rotinas, por exemplo: "Todo dia útil às 7h30, me mande o briefing do dia."

O Hermes aprende com as correções e oferece criar skills novas; a Pauta pede aprovação antes de criar qualquer rotina.

**Importante para o Google:** se o Workspace da UniCIVE for institucional, a TI pode precisar liberar o app OAuth (Admin Console > Segurança > Controles de API). Idealmente a TI cria um único cliente OAuth para todos; não publique o arquivo de credenciais no repositório.

## Antes da oficina
- Teste em uma máquina limpa.
- Teste o login OAuth com uma conta Claude Pro (a documentação do Hermes pode citar exigência de plano maior; confirme na prática). Plano B: chave de API da instituição.
- Nunca coloque chaves de API neste repositório.

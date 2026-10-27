# UniCIVE · Pauta (Hermes pré-configurado)

Assistente executiva da direção: briefing diário, resumo de e-mails, agenda, preparo de reuniões e rascunhos, com Google Workspace. Instala, configura e abre sozinha.

## Para o diretor (Windows)
Cole no PowerShell e aperte Enter:

```powershell
iex (irm https://raw.githubusercontent.com/lfcanhete/unicive-hermes/main/install.ps1)
```

O que acontece sozinho: instala o Hermes, configura o Claude, instala a Pauta e abre o navegador para o login do Claude (o único passo do diretor: entrar e autorizar). Depois abre a conversa, e a Pauta se apresenta e pergunta as preferências.

**Por enquanto o Google Workspace (e-mail e agenda) não está conectado.** A Pauta trabalha com textos colados ou anexados na conversa. A integração com Google está pronta no instalador (variável `UNICIVE_GOOGLE`, veja abaixo) e pode ser ligada depois.

macOS / Linux: `curl -fsSL https://raw.githubusercontent.com/lfcanhete/unicive-hermes/main/install.sh | bash` (ainda não adaptado para Google pré-instalado).

## Para quem organiza a oficina (opcional, para quando quiser Google e chave única)
1. **Chave do Claude:** no Console da Anthropic crie um *workspace* só da oficina, com limite de gasto mensal, e uma chave de API dentro dele. Arquivar o workspace revoga todas as chaves.
2. **Google:** a TI cria um único projeto no Google Cloud, ativa as APIs (Gmail, Agenda, Drive, Docs, Planilhas, People) e cria um cliente OAuth do tipo *Desktop app*. Se o projeto pertencer à organização da UniCIVE, deixe a tela de consentimento como **Interna**: só contas `@unicive.edu.br` entram, sem verificação do Google. Baixe o `client_secret.json`.
3. Gere a linha dos diretores (ela vai para a área de transferência):
   ```powershell
   .\gerar-comando.ps1 -Chave "sk-ant-..." -ClientSecret "C:\caminho\client_secret.json"
   ```
4. Envie por canal privado. **Nunca** coloque a chave, o `client_secret.json` ou a linha gerada neste repositório, em slides ou em grupos abertos.

## Arquivos
- `install.ps1`: instalador do Windows (se o instalador oficial parar no meio, o script repara sozinho).
- `SOUL.md`: personalidade e regras da Pauta (só lê e rascunha; nada é enviado, aceito ou apagado sem confirmação).
- `primeira-mensagem.txt`: o que a Pauta faz ao abrir pela primeira vez.
- `skills/`: skills de ata e de ofício.
- `gerar-comando.ps1`: gera a linha com as credenciais (uso interno).

## Antes da oficina
- Teste em uma máquina Windows limpa, com a chave e o cliente do Google reais.
- Confirme que o Workspace permite o app (Admin Console > Segurança > Controles de API), principalmente para contas com Proteção Avançada.
- A documentação do Hermes diz que o login OAuth com Claude exige plano Max com créditos extras. Teste o login com uma conta Pro; se não funcionar, use a chave de API (`UNICIVE_KEY`).

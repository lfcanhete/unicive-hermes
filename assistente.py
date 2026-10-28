# UNICIVE - Assistente do Assessor (Hermes Agent + Claude + Google + Telegram)
# Roda no Python que o proprio Hermes instala (aberto pelo Configurar-Assessor.cmd). Confere e ajusta
# cada parte e faz os logins de forma guiada. Sem PowerShell: o antivirus da instituicao barrava.
import base64
import hashlib
import http.server
import json
import os
import queue
import re
import secrets
import shutil
import subprocess
import threading
import time
import traceback
import urllib.parse
import urllib.request
import webbrowser
import winreg
import tkinter as tk
from tkinter import ttk

REPO = "https://raw.githubusercontent.com/lfcanhete/unicive-hermes/main"
SITE = "https://lfcanhete.github.io/unicive-hermes"
MODELO = "claude-sonnet-5-5"
SKILLS = ["resumo-reuniao", "oficio-institucional"]
HOME = os.environ.get("HERMES_HOME") or os.path.join(os.environ["LOCALAPPDATA"], "hermes")
APP = os.path.join(HOME, "hermes-agent", "apps", "desktop", "release", "win-unpacked", "Hermes.exe")
LOG = os.path.join(os.environ.get("TEMP", HOME), "assistente-assessor.log")
SEM_JANELA = 0x08000000  # CREATE_NO_WINDOW: os comandos do Hermes nao abrem janela preta

VERDE, VERDE_ESC, VERDE_MEIO, OURO, MENTA = "#004A3B", "#00382D", "#006652", "#FFC571", "#5BDC9E"
NEVOA, PAPEL, TINTA, ERRO, OK = "#A8CFC0", "#F0F8F4", "#122B23", "#B0472F", "#2F7A4E"

# Comunicacao entre as tarefas em segundo plano e a janela.
fila = queue.Queue()
estado = {"cancelar": False}


def na_tela(funcao):
    fila.put(funcao)


def registrar(msg):
    try:
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(time.strftime("%H:%M:%S ") + msg + "\n")
    except OSError:
        pass


def log(msg):
    registrar(msg)
    na_tela(lambda: janela.mostrar_log(msg))


class Falha(Exception):
    pass


# ---------- Hermes e outros programas ----------
def achar_hermes():
    for c in (os.path.join(HOME, "bin", "hermes.exe"), shutil.which("hermes"),
              os.path.join(HOME, "hermes-agent", ".hermes", "bin", "hermes.cmd")):
        if c and os.path.isfile(c):
            return c
    return None


def ambiente(interativo=False):
    env = dict(os.environ, PYTHONIOENCODING="utf-8", PYTHONUNBUFFERED="1", NO_COLOR="1")
    if not interativo:
        # Ninguem ve as perguntas do terminal: o Hermes usa a resposta padrao (no gateway, a pasta
        # Inicializar do Windows em vez da tarefa agendada que pede administrador).
        env["HERMES_NONINTERACTIVE"] = "1"
    return env


def executar(args, quieto=False):
    """Roda um programa, manda a saida para "Ver detalhes" e devolve (codigo, texto)."""
    try:
        p = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             env=ambiente(), creationflags=SEM_JANELA, text=True, encoding="utf-8", errors="replace")
    except OSError as e:
        log(f"Não consegui rodar {os.path.basename(args[0])}: {e}")
        return 1, ""
    linhas = []
    for linha in p.stdout:
        linha = linha.rstrip()
        linhas.append(linha)
        if not quieto and linha.strip():
            log(linha)
    p.wait()
    return p.returncode, "\n".join(linhas)


def baixar(url, timeout=30):
    req = urllib.request.Request(url, headers={"User-Agent": "assistente-assessor"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def atualizar_path():
    """Traz para este processo o PATH atual do Windows (instalacoes novas entram nele)."""
    partes = []
    for raiz, chave in ((winreg.HKEY_LOCAL_MACHINE, r"SYSTEM\CurrentControlSet\Control\Session Manager\Environment"),
                        (winreg.HKEY_CURRENT_USER, "Environment")):
        try:
            with winreg.OpenKey(raiz, chave) as k:
                partes.append(os.path.expandvars(winreg.QueryValueEx(k, "Path")[0]))
        except OSError:
            pass
    partes.append(os.environ.get("PATH", ""))
    os.environ["PATH"] = ";".join(p for p in partes if p)


def salvar_env(valores):
    """Grava chaves no .env do Hermes; valor None remove a chave."""
    arq = os.path.join(HOME, ".env")
    linhas = []
    if os.path.isfile(arq):
        with open(arq, encoding="utf-8", errors="replace") as f:
            linhas = [l.rstrip("\r\n") for l in f if not any(l.startswith(k + "=") for k in valores)]
    linhas += [f"{k}={v}" for k, v in valores.items() if v is not None]
    with open(arq, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(linhas) + "\n")


def ler_env(chave):
    arq = os.path.join(HOME, ".env")
    if os.path.isfile(arq):
        with open(arq, encoding="utf-8", errors="replace") as f:
            for l in f:
                if l.startswith(chave + "="):
                    return l.split("=", 1)[1].strip()
    return ""


# ---------- Passo 2: verificar e ajustar ----------
def achar_claude():
    for c in (shutil.which("claude"), os.path.expanduser(r"~\.local\bin\claude.exe")):
        if c and os.path.isfile(c):
            return c
    return None


def deixar_claude_visivel(exe):
    """O Hermes procura o claude no PATH. Sem poder mudar o PATH, um claude.cmd na pasta WindowsApps
    (ja no PATH de todo Windows) chama o Claude Code de verdade."""
    pasta = os.path.dirname(exe)
    if pasta.lower() in [p.lower().rstrip("\\") for p in os.environ.get("PATH", "").split(";")]:
        visivel_no_windows = True
    else:
        visivel_no_windows = False
        os.environ["PATH"] += ";" + pasta
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment", 0, winreg.KEY_READ | winreg.KEY_WRITE) as k:
            try:
                atual = winreg.QueryValueEx(k, "Path")[0]
            except OSError:
                atual = ""
            if pasta.lower() not in atual.lower():
                winreg.SetValueEx(k, "Path", 0, winreg.REG_EXPAND_SZ, atual.rstrip(";") + ";" + pasta)
        return
    except OSError:
        if visivel_no_windows:
            return
    try:
        apps = os.path.join(os.environ["LOCALAPPDATA"], "Microsoft", "WindowsApps")
        with open(os.path.join(apps, "claude.cmd"), "w", encoding="mbcs") as f:
            f.write(f'@"{exe}" %*\r\n')
        log("Este computador não deixou mudar o PATH; o Claude Code foi ligado pela pasta WindowsApps.")
    except OSError as e:
        log(f"Aviso: não consegui deixar o Claude Code visível para o Hermes ({e}).")


def tarefa_verificar(sub):
    sub(0, "ativo")
    hx = achar_hermes()
    # O configurador nao instala nem conserta o Hermes: ele e instalado do jeito original, pelo site oficial.
    if not hx:
        raise Falha("O Hermes não está instalado. Instale pelo site oficial (hermes-agent.nousresearch.com), abra o "
                    "Hermes uma vez e depois abra o Configurar-Assessor de novo.")
    rc, out = executar([hx, "--version"], quieto=True)
    if rc != 0 or "Hermes Agent v" not in out:
        raise Falha("O Hermes está instalado, mas não responde. Abra o aplicativo Hermes uma vez e tente de novo; se "
                    "continuar, reinstale o Hermes pelo site oficial.")
    log("Hermes: " + out.splitlines()[0].strip())
    sub(0, "ok")

    sub(1, "ativo")
    trava = os.path.join(HOME, ".hermes-update-in-progress")
    if os.path.exists(trava):
        # Sobra de uma atualizacao que terminou com erro: o app fica esperando para sempre.
        try:
            os.remove(trava)
        except OSError:
            pass
    if os.path.isfile(APP):
        log("Aplicativo Hermes: instalado.")
        sub(1, "ok")
    else:
        log("O aplicativo Hermes não foi encontrado; o Assessor continua disponível pelo Telegram e pelo comando hermes.")
        sub(1, "pulado")

    sub(2, "ativo")
    for chave, valor in (("model.provider", "anthropic"), ("model.default", MODELO)):
        if executar([hx, "config", "set", chave, valor])[0] != 0:
            time.sleep(3)
            if executar([hx, "config", "set", chave, valor])[0] != 0:
                raise Falha(f"Não consegui configurar o Claude no Hermes ({chave}).")
    # Respostas mais rapidas e menos uso da cota do plano: raciocinio baixo e sem chamada extra para titulo.
    executar([hx, "config", "set", "--force", "agent.reasoning_effort", "low"])
    executar([hx, "config", "set", "auxiliary.title_generation.enabled", "false"])
    soul = os.path.join(HOME, "SOUL.md")
    if os.path.isfile(soul) and not os.path.isfile(soul + ".original"):
        shutil.copyfile(soul, soul + ".original")
    arquivos = [("SOUL.md", soul)] + [(f"skills/{s}/SKILL.md", os.path.join(HOME, "skills", "productivity", s, "SKILL.md")) for s in SKILLS]
    for rel, destino in arquivos:
        os.makedirs(os.path.dirname(destino), exist_ok=True)
        with open(destino, "wb") as f:
            f.write(baixar(f"{REPO}/{rel}"))
    log("Assessor: personalidade e skills atualizadas.")
    sub(2, "ok")

    # O Hermes se identifica para a Anthropic com a versao do Claude Code instalado; sem ele usa uma
    # versao antiga fixa e a Anthropic recusa modelos novos ("Claude Code X does not support this model").
    sub(3, "ativo")
    cl = achar_claude()
    if cl:
        log("Atualizando o Claude Code...")
        executar([cl, "update"])
    else:
        wg = shutil.which("winget")
        if wg:
            log("Instalando o Claude Code pela Microsoft (winget)...")
            executar([wg, "install", "--id", "Anthropic.ClaudeCode", "-e", "--silent",
                      "--accept-package-agreements", "--accept-source-agreements"])
            atualizar_path()
            links = os.path.join(os.environ["LOCALAPPDATA"], "Microsoft", "WinGet", "Links")
            if os.path.isfile(os.path.join(links, "claude.exe")) and links not in os.environ["PATH"]:
                os.environ["PATH"] += ";" + links
            cl = achar_claude()
        else:
            log("Aviso: este Windows não tem o winget para instalar o Claude Code.")
    if cl and executar([cl, "--version"], quieto=True)[0] == 0:
        deixar_claude_visivel(cl)
        log("Claude Code pronto: " + executar([cl, "--version"], quieto=True)[1].strip())
        sub(3, "ok")
    else:
        log("Aviso: o Claude Code não ficou instalado; o Hermes pode não acessar os modelos mais novos.")
        sub(3, "erro")

    sub(4, "ativo")
    try:
        cliente = baixar(f"{SITE}/google-client.json").decode("utf-8")
        if '"installed"' not in cliente:
            raise ValueError("arquivo incompleto")
        with open(os.path.join(HOME, "google_client_secret.json"), "w", encoding="utf-8") as f:
            f.write(cliente)
        estado["google"] = True
        log("Instalando os componentes do Google...")
        if executar([hx, "pm", "install", "--extra", "google"])[0] != 0:
            log("Aviso: os componentes do Google não terminaram agora; o Hermes completa no primeiro uso.")
        sub(4, "ok")
    except Exception as e:
        estado["google"] = False
        log(f"Google: configuração não disponível no site ({e}).")
        sub(4, "pulado")
    ligar_no_login()


# ---------- Passo 3: Claude ----------
def claude_conectado():
    hx = achar_hermes()
    return bool(hx) and "hermes_pkce" in executar([hx, "auth", "list"], quieto=True)[1]


def tarefa_claude():
    p = subprocess.Popen([achar_hermes(), "auth", "add", "anthropic", "--type", "oauth"], stdin=subprocess.PIPE,
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=ambiente(interativo=True),
                         creationflags=SEM_JANELA, text=True, encoding="utf-8", errors="replace")
    saida = []

    def ler():
        for linha in p.stdout:
            linha = linha.rstrip()
            saida.append(linha)
            if linha.strip():
                log(linha)
            m = re.search(r"(https://claude\.ai/oauth/authorize\S+)", linha)
            if m:
                # O link basta para mostrar a caixa do codigo (o resto do texto pode vir traduzido).
                estado["claude_url"] = m.group(1)
                na_tela(janela.claude_pedir_codigo)

    leitor = threading.Thread(target=ler, daemon=True)
    leitor.start()
    inicio = time.time()
    enviado = False
    while p.poll() is None:
        if estado["cancelar"]:
            p.kill()
            raise Falha("Cancelado.")
        if not estado.get("claude_url") and time.time() - inicio > 90:
            p.kill()
            raise Falha("O login do Claude não começou.")
        codigo = estado.pop("claude_codigo", None)
        if codigo and not enviado:
            p.stdin.write(codigo + "\n")
            p.stdin.close()
            enviado = True
        time.sleep(0.25)
    leitor.join(5)
    texto = "\n".join(saida)
    if p.returncode != 0 or re.search(r"failed|mismatch|No access token|No code entered", texto):
        raise Falha("O Claude não aceitou o código.")


# ---------- Passo 4: Google ----------
ESCOPOS = ["https://www.googleapis.com/auth/gmail.readonly", "https://www.googleapis.com/auth/gmail.send",
           "https://www.googleapis.com/auth/gmail.modify", "https://www.googleapis.com/auth/calendar",
           "https://www.googleapis.com/auth/drive", "https://www.googleapis.com/auth/contacts.readonly",
           "https://www.googleapis.com/auth/spreadsheets", "https://www.googleapis.com/auth/documents"]


def b64url(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def tarefa_google():
    with open(os.path.join(HOME, "google_client_secret.json"), encoding="utf-8") as f:
        inst = json.load(f)["installed"]
    verificador = b64url(secrets.token_bytes(32))
    estado_oauth = b64url(secrets.token_bytes(32))
    desafio = b64url(hashlib.sha256(verificador.encode()).digest())
    resultado = {}

    class Retorno(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            if "code" not in q and "error" not in q:
                self.send_response(404)
                self.end_headers()
                return
            ok = "code" in q and q.get("state", [""])[0] == estado_oauth
            msg = ("Pronto! O Google foi conectado. Pode fechar esta aba e voltar ao configurador." if ok
                   else "Não deu certo. Volte ao configurador e tente de novo.")
            html = (f"<!doctype html><meta charset=utf-8><title>Assessor</title><body style=\"font-family:Segoe UI,sans-serif;"
                    f"background:#004A3B;color:#fff;display:flex;align-items:center;justify-content:center;height:100vh;margin:0\">"
                    f"<div style=\"text-align:center;max-width:520px;padding:24px\"><h1 style=\"color:#FFC571;font-weight:600\">"
                    f"Assessor &middot; UNICIVE</h1><p style=\"font-size:18px;line-height:1.5\">{msg}</p></div>").encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(html)))
            self.end_headers()
            self.wfile.write(html)
            resultado["codigo"] = q["code"][0] if ok else None
            resultado["erro"] = q.get("error", [""])[0]

        def log_message(self, *args):
            pass

    # O Google devolve o login para este endereco local, sem o diretor precisar colar nada.
    servidor = http.server.HTTPServer(("127.0.0.1", 0), Retorno)
    servidor.timeout = 0.5
    retorno = f"http://127.0.0.1:{servidor.server_address[1]}/"
    parametros = {"client_id": inst["client_id"], "redirect_uri": retorno, "response_type": "code",
                  "scope": " ".join(ESCOPOS), "code_challenge": desafio, "code_challenge_method": "S256",
                  "state": estado_oauth, "access_type": "offline", "prompt": "consent"}
    estado["google_url"] = "https://accounts.google.com/o/oauth2/v2/auth?" + urllib.parse.urlencode(parametros)
    webbrowser.open(estado["google_url"])
    log("Aguardando a autorização no navegador...")
    inicio = time.time()
    try:
        while "codigo" not in resultado:
            if estado["cancelar"]:
                raise Falha("Cancelado.")
            if time.time() - inicio > 600:
                raise Falha("O tempo para entrar no Google acabou.")
            servidor.handle_request()
    finally:
        servidor.server_close()
    if not resultado["codigo"]:
        if resultado.get("erro") == "access_denied":
            raise Falha("O acesso não foi permitido. Clique em Entrar com o Google, use a sua conta @unicive.edu.br e clique em Continuar.")
        raise Falha(f"O Google não autorizou ({resultado.get('erro')}).")

    corpo = urllib.parse.urlencode({"code": resultado["codigo"], "client_id": inst["client_id"],
                                    "client_secret": inst["client_secret"], "redirect_uri": retorno,
                                    "grant_type": "authorization_code", "code_verifier": verificador}).encode()
    with urllib.request.urlopen(urllib.request.Request("https://oauth2.googleapis.com/token", data=corpo), timeout=30) as r:
        tok = json.load(r)
    if not tok.get("refresh_token"):
        raise Falha("O Google não devolveu a autorização completa.")
    # Mesmo formato que a skill google-workspace do Hermes grava (google-auth "authorized_user").
    expira = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() + int(tok.get("expires_in", 3600)) - 60))
    token = {"token": tok["access_token"], "refresh_token": tok["refresh_token"],
             "token_uri": "https://oauth2.googleapis.com/token", "client_id": inst["client_id"],
             "client_secret": inst["client_secret"], "scopes": tok.get("scope", "").split(),
             "universe_domain": "googleapis.com", "account": "", "expiry": expira, "type": "authorized_user"}
    with open(os.path.join(HOME, "google_token.json"), "w", encoding="utf-8") as f:
        json.dump(token, f, indent=2)
    log("Token do Google salvo.")
    try:
        req = urllib.request.Request("https://gmail.googleapis.com/gmail/v1/users/me/profile",
                                     headers={"Authorization": "Bearer " + tok["access_token"]})
        with urllib.request.urlopen(req, timeout=20) as r:
            estado["google_email"] = json.load(r).get("emailAddress")
    except Exception as e:
        log(f"Não consegui ler o endereço do Gmail: {e}")


# ---------- Telegram (configurado a mao, pelo tutorial do site) ----------
INICIAR = r"""@echo off
rem UNICIVE - liga o Assessor (e o Telegram, se configurado) ao entrar no Windows.
rem O Hermes grava um .vbs na inicializacao para isso, mas o antivirus costuma remover; este e o reserva.
if not "%~1"=="min" (start "" /min "%~f0" min & exit /b)
rem Espera o login assentar e o .vbs do Hermes (se existir) ligar primeiro; "start" nao duplica.
ping -n 31 127.0.0.1 >nul
set "HERMES_NONINTERACTIVE=1"
set "HERMES_GATEWAY_INSTALL_START_ON_LOGIN=0"
if exist "%LOCALAPPDATA%\hermes\bin\hermes.exe" "%LOCALAPPDATA%\hermes\bin\hermes.exe" gateway start >nul 2>&1
exit /b
"""


def ligar_no_login():
    """Garante que o Assessor (e o Telegram) volta sozinho depois de reiniciar o computador."""
    pasta = os.path.join(os.environ["APPDATA"], "Microsoft", "Windows", "Start Menu", "Programs", "Startup")
    try:
        with open(os.path.join(pasta, "Assessor-Telegram.cmd"), "w", encoding="ascii", newline="\r\n") as f:
            f.write(INICIAR)
        log("Início automático: o Assessor liga sozinho ao entrar no Windows.")
    except OSError as e:
        log(f"Aviso: não consegui deixar o Assessor ligando com o Windows ({e}).")


def dono_aprovado(hx):
    lista = executar([hx, "pairing", "list"], quieto=True)[1]
    return bool(re.search(r"(?ms)Approved Users.*?^\s*telegram\s+\S+", lista) or ler_env("TELEGRAM_ALLOWED_USERS"))


# ---------- Passo 5: checkup completo ----------
def executar_com_limite(args, segundos):
    """Roda um comando com tempo maximo; devolve (codigo, texto) ou (None, '') se estourar."""
    try:
        r = subprocess.run(args, stdin=subprocess.DEVNULL, capture_output=True, env=ambiente(), creationflags=SEM_JANELA,
                           text=True, encoding="utf-8", errors="replace", timeout=segundos)
        return r.returncode, (r.stdout or "") + (r.stderr or "")
    except subprocess.TimeoutExpired:
        return None, ""
    except OSError as e:
        return 1, str(e)


def google_funcionando():
    """Renova o acesso com o token salvo e abre o Gmail: prova que o Google esta mesmo conectado."""
    with open(os.path.join(HOME, "google_token.json"), encoding="utf-8") as f:
        tok = json.load(f)
    corpo = urllib.parse.urlencode({"client_id": tok["client_id"], "client_secret": tok["client_secret"],
                                    "refresh_token": tok["refresh_token"], "grant_type": "refresh_token"}).encode()
    with urllib.request.urlopen(urllib.request.Request("https://oauth2.googleapis.com/token", data=corpo), timeout=30) as r:
        acesso = json.load(r)["access_token"]
    req = urllib.request.Request("https://gmail.googleapis.com/gmail/v1/users/me/profile", headers={"Authorization": "Bearer " + acesso})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.load(r).get("emailAddress", "")


def tarefa_checkup(item):
    """Testa de verdade cada parte. item(chave, situacao, texto) atualiza a lista na janela."""
    problemas = 0
    hx = achar_hermes()

    item("hermes", "ativo", "Hermes: conferindo...")
    rc, out = executar_com_limite([hx, "--version"], 60) if hx else (1, "")
    if rc == 0 and "Hermes Agent v" in out:
        versao = out.splitlines()[0].split("(")[0].replace("Hermes Agent", "").strip()
        item("hermes", "ok", f"Hermes funcionando ({versao})")
    else:
        item("hermes", "erro", "Hermes não está respondendo")
        problemas += 1
        hx = None

    item("modelo", "ativo", "Modelo: conferindo...")
    rc, out = executar_com_limite([hx, "config", "get", "model.default"], 60) if hx else (1, "")
    if rc == 0 and MODELO in out:
        item("modelo", "ok", "Modelo Claude Sonnet 5.5 configurado")
    else:
        item("modelo", "erro", "O modelo não está configurado como Claude Sonnet 5.5")
        problemas += 1

    item("claude", "ativo", "Claude: fazendo uma pergunta de teste (até 2 minutos)...")
    rc, out = executar_com_limite([hx, "-z", "Responda apenas com a palavra OK."], 150) if hx else (1, "")
    if rc == 0 and re.search(r"\bOK\b", out, re.I):
        item("claude", "ok", "Claude respondeu ao teste")
    else:
        if "does not support this model" in out:
            motivo = "o Claude Code está desatualizado"
        elif re.search(r"rate.?limit|usage limit|429", out, re.I):
            motivo = "o limite de uso do plano foi atingido; tente mais tarde"
        elif re.search(r"auth|credential|login|401", out, re.I):
            motivo = "o login do Claude não está valendo"
        else:
            motivo = "não respondeu a tempo" if rc is None else "não respondeu"
        item("claude", "erro", f"Claude não respondeu ao teste: {motivo}")
        log("Teste do Claude: " + out[-600:])
        problemas += 1

    soul = os.path.join(HOME, "SOUL.md")
    skills_ok = all(os.path.isfile(os.path.join(HOME, "skills", "productivity", s, "SKILL.md")) for s in SKILLS)
    try:
        soul_ok = "Assessor" in open(soul, encoding="utf-8", errors="replace").read()
    except OSError:
        soul_ok = False
    if soul_ok and skills_ok:
        item("assessor", "ok", "Personalidade e skills do Assessor instaladas")
    else:
        item("assessor", "erro", "Personalidade ou skills do Assessor faltando")
        problemas += 1

    cl = achar_claude()
    if cl and executar_com_limite([cl, "--version"], 30)[0] == 0:
        item("claudecode", "ok", "Claude Code encontrado")
    else:
        item("claudecode", "erro", "Claude Code não encontrado (pode impedir os modelos mais novos)")
        problemas += 1

    if os.path.isfile(os.path.join(HOME, "google_token.json")):
        item("google", "ativo", "Google: abrindo o Gmail...")
        try:
            email = google_funcionando()
            item("google", "ok", f"Google funcionando{': ' + email if email else ''}")
        except Exception as e:
            item("google", "erro", "Google conectado, mas o Gmail não abriu: entre no Google de novo")
            log(f"Teste do Google: {e}")
            problemas += 1
    else:
        item("google", "pulado", "Google: não conectado")

    if ler_env("TELEGRAM_BOT_TOKEN"):
        item("telegram", "ativo", "Telegram: conferindo...")
        ligado = bool(hx) and not re.search(r"(?i)not running", executar_com_limite([hx, "gateway", "status"], 60)[1])
        aprovado = bool(hx) and dono_aprovado(hx)
        if ligado and aprovado:
            item("telegram", "ok", "Telegram ligado e com o dono aprovado")
        else:
            item("telegram", "erro", "Telegram: " + ("o Assessor está desligado" if not ligado else "o dono ainda não foi aprovado"))
            problemas += 1
        inicio = os.path.join(os.environ["APPDATA"], "Microsoft", "Windows", "Start Menu", "Programs", "Startup")
        if os.path.isfile(os.path.join(inicio, "Assessor-Telegram.cmd")) or os.path.isfile(os.path.join(inicio, "Hermes_Gateway.vbs")):
            item("inicio", "ok", "Telegram liga sozinho ao entrar no Windows")
        else:
            item("inicio", "erro", "O Telegram não vai ligar sozinho depois de reiniciar")
            problemas += 1
    else:
        item("telegram", "pulado", "Telegram: ainda não configurado (veja o tutorial no site)")
        item("inicio", "pulado", "Início automático do Telegram: depois de configurar o Telegram")
    return problemas


# ---------- Janela ----------
PASSOS = ["Boas-vindas", "Verificação", "Claude", "Google", "Pronto"]
TITULOS = ["Vamos deixar o Assessor pronto", "Verificando e ajustando", "Conecte o Claude", "Conecte o Google",
           "Checkup final"]
STATUS = ["Pronto para começar", "Verificando... pode levar alguns minutos", "Aguardando o login do Claude",
          "Aguardando o login do Google", "Configuração concluída"]
SUBS = ["Hermes", "Aplicativo Hermes", "Claude Sonnet 5.5 e o Assessor", "Claude Code (acesso aos modelos mais novos)",
        "Conexão com o Google"]


class Marcador:
    """Bolinha numerada com o nome do passo, que vira check, traco ou exclamacao."""

    def __init__(self, pai, texto, numero, escuro):
        self.escuro, self.numero, self.estado = escuro, numero, "pendente"
        fundo = VERDE if escuro else PAPEL
        self.quadro = tk.Frame(pai, bg=fundo)
        self.bola = tk.Canvas(self.quadro, width=26, height=26, bg=fundo, highlightthickness=0)
        self.bola.pack(side="left")
        self.texto = tk.Label(self.quadro, text=texto, bg=fundo, font=("Segoe UI", 11), anchor="w", justify="left")
        self.texto.pack(side="left", padx=(12, 0))
        self.quadro.pack(anchor="w", pady=(0, 12))
        self.marcar("pendente")

    def marcar(self, estado):
        self.estado = estado
        cor = {"pendente": "", "ativo": OURO, "ok": MENTA, "pulado": "", "erro": ERRO}[estado]
        sinal = {"pendente": self.numero, "ativo": self.numero, "ok": "✓", "pulado": "–", "erro": "!"}[estado]
        apagado = estado in ("pendente", "pulado")
        borda = ("#3F7A6A" if self.escuro else NEVOA) if apagado else cor
        self.bola.delete("all")
        self.bola.create_oval(2, 2, 24, 24, fill=cor, outline=borda, width=1.5)
        cor_sinal = ("#A8CFC0" if self.escuro else "#6B8F82") if apagado else ("white" if estado == "erro" else VERDE_ESC)
        self.bola.create_text(13, 13, text=sinal, fill=cor_sinal, font=("Segoe UI", 9, "bold"))
        if self.escuro:
            self.texto.config(fg="white" if estado in ("ativo", "ok") else NEVOA,
                              font=("Segoe UI", 11, "bold" if estado == "ativo" else "normal"))
        else:
            self.texto.config(fg="#6B8F82" if apagado else TINTA)


def botao(pai, texto, comando, primario=True, **kw):
    return tk.Button(pai, text=texto, command=comando, bg=OURO if primario else "#DDEFE6",
                     fg=VERDE_ESC if primario else VERDE_MEIO, activebackground="#FFD48F" if primario else "#CFE7DB",
                     relief="flat", bd=0, font=("Segoe UI", 10, "bold"), padx=20, pady=8, cursor="hand2", **kw)


def cartao(pai):
    c = tk.Frame(pai, bg="white", padx=16, pady=12)
    c.pack(fill="x", pady=(10, 0))
    return c


def texto(pai, conteudo, **kw):
    kw.setdefault("bg", pai["bg"])
    kw.setdefault("fg", TINTA)
    kw.setdefault("font", ("Segoe UI", 11))
    rotulo = tk.Label(pai, text=conteudo, wraplength=560, justify="left", anchor="w", **kw)
    rotulo.pack(fill="x", anchor="w")
    return rotulo


class Janela:
    def __init__(self, raiz):
        self.raiz, self.pagina, self.tarefa, self.feito = raiz, 0, None, {}
        raiz.title("Configurar o Assessor · UNICIVE")
        raiz.geometry("940x720")
        raiz.resizable(False, False)
        raiz.configure(bg=PAPEL)

        rodape = tk.Frame(raiz, bg=VERDE_ESC, padx=26, pady=8)
        rodape.pack(side="bottom", fill="x")
        self.pct = tk.Label(rodape, text="0%", bg=VERDE_ESC, fg=OURO, font=("Segoe UI", 9, "bold"), width=5, anchor="e")
        self.pct.pack(side="right")
        estilo = ttk.Style()
        estilo.theme_use("clam")
        estilo.configure("Geral.Horizontal.TProgressbar", troughcolor="#0F5A48", background=MENTA, bordercolor=VERDE_ESC,
                         lightcolor=MENTA, darkcolor=MENTA)
        estilo.configure("Passo.Horizontal.TProgressbar", troughcolor="#D8EDE3", background=VERDE_MEIO, bordercolor=PAPEL,
                         lightcolor=VERDE_MEIO, darkcolor=VERDE_MEIO)
        self.barra_geral = ttk.Progressbar(rodape, length=220, maximum=100, style="Geral.Horizontal.TProgressbar")
        self.barra_geral.pack(side="right", padx=(16, 8))
        self.status = tk.Label(rodape, text="", bg=VERDE_ESC, fg=NEVOA, font=("Segoe UI", 9), anchor="w")
        self.status.pack(side="left", fill="x", expand=True)

        lateral = tk.Frame(raiz, bg=VERDE, width=250, padx=26, pady=28)
        lateral.pack(side="left", fill="y")
        lateral.pack_propagate(False)
        tk.Label(lateral, text="UNICIVE · DIREÇÃO", bg=VERDE, fg=OURO, font=("Segoe UI", 8, "bold")).pack(anchor="w")
        tk.Label(lateral, text="Assessor", bg=VERDE, fg="white", font=("Georgia", 26)).pack(anchor="w", pady=(4, 0))
        tk.Label(lateral, text="Configuração guiada", bg=VERDE, fg=NEVOA, font=("Segoe UI", 10)).pack(anchor="w", pady=(0, 36))
        self.passos = [Marcador(lateral, n, str(i + 1), True) for i, n in enumerate(PASSOS)]
        tk.Label(lateral, text="Dúvidas? Chame o Luiz Fernando.", bg=VERDE, fg=NEVOA, font=("Segoe UI", 9),
                 wraplength=190, justify="left").pack(side="bottom", anchor="w")

        direita = tk.Frame(raiz, bg=PAPEL, padx=44, pady=26)
        direita.pack(side="left", fill="both", expand=True)
        self.txt_passo = tk.Label(direita, bg=PAPEL, fg="#B27B2E", font=("Segoe UI", 9, "bold"), anchor="w")
        self.txt_passo.pack(fill="x")
        self.titulo = tk.Label(direita, bg=PAPEL, fg=TINTA, font=("Georgia", 22), anchor="w")
        self.titulo.pack(fill="x", pady=(4, 10))

        baixo = tk.Frame(direita, bg=PAPEL)
        baixo.pack(side="bottom", fill="x", pady=(10, 0))
        self.btn_avancar = botao(baixo, "Continuar", self.avancar)
        self.btn_avancar.pack(side="right")
        self.btn_pular = botao(baixo, "Pular por enquanto", self.pular, primario=False)
        self.detalhes = tk.Frame(direita, bg=PAPEL)
        self.detalhes.pack(side="bottom", fill="x")
        self.btn_detalhes = tk.Label(self.detalhes, text="▸ Ver detalhes", bg=PAPEL, fg=VERDE_MEIO, cursor="hand2",
                                     font=("Segoe UI", 10))
        self.btn_detalhes.pack(anchor="w")
        self.btn_detalhes.bind("<Button-1>", lambda e: self.alternar_detalhes())
        self.caixa_log = tk.Text(self.detalhes, height=7, bg=VERDE_ESC, fg=MENTA, font=("Consolas", 9), relief="flat",
                                 wrap="word", padx=8, pady=6)

        self.area = tk.Frame(direita, bg=PAPEL)
        self.area.pack(fill="both", expand=True)
        self.paginas = [tk.Frame(self.area, bg=PAPEL) for _ in PASSOS]
        self.montar_paginas()
        raiz.protocol("WM_DELETE_WINDOW", self.fechar)
        # Enter aciona o botao principal quando ele esta liberado.
        raiz.bind("<Return>", lambda e: self.avancar() if str(self.btn_avancar["state"]) == "normal" else None)
        self.ir(0)
        raiz.after(150, self.relogio)

    # ----- paginas -----
    def montar_paginas(self):
        p = self.paginas[0]
        texto(p, "Este configurador deixa o Assessor pronto no seu Hermes: confere a instalação, ajusta o que faltar e conecta o "
                 "Claude e o Google. O que já estiver certo passa sozinho.", font=("Segoe UI", 12))
        tk.Frame(p, bg=PAPEL, height=14).pack()
        texto(p, "Tenha por perto:", font=("Segoe UI", 11, "bold"))
        for item in ("a sua conta do Claude", "a sua conta @unicive.edu.br"):
            texto(p, "•   " + item)
        aviso = tk.Frame(p, bg="#FFF1DA", padx=14, pady=10)
        aviso.pack(fill="x", pady=(18, 0))
        texto(aviso, "Leva uns 10 minutos. Não feche esta janela até o final. Se algo der errado, ela mesma explica o que fazer.")

        p = self.paginas[1]
        texto(p, "Agora é com o configurador: ele confere cada parte e ajusta o que faltar. Você não precisa fazer nada.",
              font=("Segoe UI", 12))
        lista = tk.Frame(p, bg=PAPEL)
        lista.pack(fill="x", pady=(16, 0))
        self.subs = [Marcador(lista, n, str(i + 1), False) for i, n in enumerate(SUBS)]
        self.barra = ttk.Progressbar(p, mode="indeterminate", style="Passo.Horizontal.TProgressbar")
        self.barra.pack(fill="x", pady=(6, 0))
        self.erro_verif = texto(p, "", fg=ERRO)

        p = self.paginas[2]
        texto(p, "O Claude é o cérebro do Assessor. Conecte a sua conta em três passos:", font=("Segoe UI", 12))
        c = cartao(p)
        texto(c, "1.  Clique em Entrar com o Claude. O navegador vai abrir.")
        texto(c, "2.  Entre na sua conta e clique em Authorize (Autorizar).")
        texto(c, "3.  Vai aparecer um código. Clique em Copy (Copiar), volte aqui e cole no campo abaixo (Ctrl+V).")
        self.btn_claude = botao(p, "Entrar com o Claude", self.entrar_claude)
        self.btn_claude.pack(anchor="w", pady=(16, 0))
        self.caixa_codigo = tk.Frame(p, bg=PAPEL)
        texto(self.caixa_codigo, "Cole o código aqui (Ctrl+V):")
        self.codigo = tk.StringVar()
        tk.Entry(self.caixa_codigo, textvariable=self.codigo, font=("Consolas", 10), width=52).pack(anchor="w", pady=(6, 0), ipady=5)
        self.codigo.trace_add("write", lambda *a: self.codigo_colado())
        self.st_claude = texto(p, "", font=("Segoe UI", 11, "bold"))

        p = self.paginas[3]
        texto(p, "Com o Google conectado, o Assessor lê seus e-mails, sua agenda e seus documentos para fazer briefings e "
                 "rascunhos. Ele nunca envia nada sem você pedir.", font=("Segoe UI", 12))
        c = cartao(p)
        texto(c, "1.  Clique em Entrar com o Google.")
        texto(c, "2.  Escolha a sua conta @unicive.edu.br.")
        texto(c, "3.  Marque as permissões e clique em Continuar. Depois é só voltar para esta janela.")
        texto(c, "Se o Google mostrar \"acesso bloqueado\" ou \"org_internal\", você entrou com outra conta: clique em "
                 "Abrir o navegador de novo e troque para a conta @unicive.edu.br.", fg="#8A5A12")
        self.btn_google = botao(p, "Entrar com o Google", self.entrar_google)
        self.btn_google.pack(anchor="w", pady=(16, 0))
        self.st_google = texto(p, "", font=("Segoe UI", 11, "bold"))

        p = self.paginas[4]
        texto(p, "Checkup final: o configurador testa de verdade cada parte do Assessor.", font=("Segoe UI", 12))
        self.resumo = tk.Frame(p, bg=PAPEL)
        self.resumo.pack(fill="x", pady=(12, 0))
        self.ck = {}
        for chave, rotulo in (("hermes", "Hermes"), ("modelo", "Modelo"), ("claude", "Claude"), ("assessor", "Assessor"),
                              ("claudecode", "Claude Code"), ("google", "Google"), ("telegram", "Telegram"),
                              ("inicio", "Início automático do Telegram")):
            m = Marcador(self.resumo, rotulo, "•", False)
            m.quadro.pack_configure(pady=(0, 7))
            self.ck[chave] = m
        self.ck_resumo = texto(p, "", font=("Segoe UI", 11, "bold"))
        acoes = tk.Frame(p, bg=PAPEL)
        acoes.pack(anchor="w", pady=(12, 0))
        botao(acoes, "Abrir o Assessor", self.abrir_assessor).pack(side="left")
        self.btn_checkup = botao(acoes, "Refazer o checkup", self.montar_resumo, primario=False)
        self.btn_checkup.pack(side="left", padx=(10, 0))
        self.final = texto(p, "", fg=VERDE_MEIO)

    # ----- navegacao -----
    def ir(self, i):
        registrar(f"[passo] {i + 1}: {PASSOS[i]}")
        for p in self.paginas:
            p.pack_forget()
        self.paginas[i].pack(fill="both", expand=True)
        if self.passos[self.pagina].estado == "ativo":
            self.passos[self.pagina].marcar("pendente")
        self.pagina = i
        self.passos[i].marcar("ativo")
        self.txt_passo.config(text=f"PASSO {i + 1} DE {len(PASSOS)}")
        self.titulo.config(text=TITULOS[i])
        self.status.config(text=STATUS[i])
        self.btn_avancar.config(text="Começar" if i == 0 else "Concluir" if i == 4 else "Continuar",
                                state="normal" if i in (0, 4) else "disabled")
        if i == 3:
            self.btn_pular.pack(side="left")
        else:
            self.btn_pular.pack_forget()
        if i == 1:
            self.verificar()
        elif i == 2:
            self.rodar(claude_conectado, self.depois_checar_claude)
        elif i == 3:
            if not estado.get("google"):
                self.st_google.config(text="Este computador não recebeu a configuração do Google. Por enquanto o Assessor "
                                           "trabalha com o que você colar na conversa.", fg=VERDE_MEIO)
                self.btn_google.pack_forget()
                self.concluir(3, "pulado")
                self.raiz.after(1200, lambda: self.ir(4))
            elif os.path.isfile(os.path.join(HOME, "google_token.json")):
                self.st_google.config(text="✓  Este computador já está conectado ao Google.", fg=OK)
                self.concluir(3, "ok")
                self.raiz.after(1200, lambda: self.ir(4))
        elif i == 4:
            self.montar_resumo()

    def concluir(self, i, situacao):
        self.feito[i] = situacao
        self.passos[i].marcar(situacao)

    def avancar(self):
        if self.pagina == 0:
            self.concluir(0, "ok")
            self.ir(1)
        elif self.pagina == 1:
            self.ir(2) if not self.feito.get("verif_erro") else self.verificar()
        elif self.pagina == 4:
            self.fechar()
        else:
            if self.pagina not in self.feito:
                self.concluir(self.pagina, "ok")
            self.ir(self.pagina + 1)

    def pular(self):
        estado["cancelar"] = True
        self.concluir(self.pagina, "pulado")
        self.ir(self.pagina + 1)

    def fechar(self):
        estado["cancelar"] = True
        self.raiz.destroy()

    # ----- tarefas -----
    def rodar(self, funcao, ao_terminar, *args):
        """Roda em segundo plano; ao_terminar(resultado, erro) volta na janela."""
        if self.tarefa and self.tarefa.is_alive():
            # A tarefa anterior ainda esta encerrando (ou foi cancelada pelo "Pular"): tenta em seguida.
            self.raiz.after(300, lambda: self.rodar(funcao, ao_terminar, *args))
            return False
        estado["cancelar"] = False

        def alvo():
            try:
                r = funcao(*args)
                na_tela(lambda: ao_terminar(r, None))
            except Falha as e:
                msg = str(e)
                log("ERRO: " + msg)
                na_tela(lambda: ao_terminar(None, msg))
            except Exception as e:
                msg = str(e)
                registrar(traceback.format_exc())
                log("ERRO: " + msg)
                na_tela(lambda: ao_terminar(None, msg))

        self.tarefa = threading.Thread(target=alvo, daemon=True)
        self.tarefa.start()
        return True

    def verificar(self):
        self.feito.pop("verif_erro", None)
        self.erro_verif.config(text="")
        self.barra.start(12)
        self.btn_avancar.config(state="disabled", text="Continuar")
        for s in self.subs:
            if s.estado == "erro":
                s.marcar("pendente")
        self.passos[1].marcar("ativo")

        def sub(i, situacao):
            na_tela(lambda: self.subs[i].marcar(situacao))

        def fim(_, erro):
            self.barra.stop()
            if erro:
                for s in self.subs:
                    if s.estado == "ativo":
                        s.marcar("erro")
                self.erro_verif.config(text=f"Algo deu errado: {erro}\nClique em Tentar de novo. Se continuar, envie para o "
                                            f"suporte o arquivo {LOG}")
                self.passos[1].marcar("erro")
                self.feito["verif_erro"] = True
                self.btn_avancar.config(state="normal", text="Tentar de novo")
            else:
                self.concluir(1, "ok")
                self.ir(2)

        self.rodar(tarefa_verificar, fim, sub)

    def depois_checar_claude(self, conectado, erro):
        if conectado and self.pagina == 2:
            self.st_claude.config(text="✓  Este computador já está conectado ao Claude.", fg=OK)
            self.concluir(2, "ok")
            self.raiz.after(1200, lambda: self.ir(3))

    def entrar_claude(self):
        if self.tarefa and self.tarefa.is_alive():
            if estado.get("claude_url"):
                webbrowser.open(estado["claude_url"])
            return
        estado.pop("claude_url", None)
        estado.pop("claude_codigo", None)
        self.codigo.set("")
        self.btn_claude.config(text="Abrir o navegador de novo")
        self.st_claude.config(text="Abrindo o navegador...", fg=VERDE_MEIO)

        def fim(_, erro):
            self.caixa_codigo.pack_forget()
            self.btn_claude.config(text="Entrar com o Claude")
            if erro:
                self.st_claude.config(text=f"Não deu certo: {erro} Clique em Entrar com o Claude para tentar de novo.", fg=ERRO)
            else:
                self.st_claude.config(text="✓  Claude conectado.", fg=OK)
                self.concluir(2, "ok")
                self.btn_avancar.config(state="normal")

        self.rodar(tarefa_claude, fim)

    def claude_pedir_codigo(self):
        self.caixa_codigo.pack(fill="x", pady=(14, 0), before=self.st_claude)
        self.st_claude.config(text="Aguardando o código do Claude...", fg=VERDE_MEIO)

    def codigo_colado(self):
        c = self.codigo.get().strip()
        if re.fullmatch(r"[\w-]{10,}#[\w-]{10,}", c) and "claude_codigo" not in estado and estado.get("claude_url"):
            estado["claude_codigo"] = c
            self.st_claude.config(text="Código recebido. Conferindo...", fg=VERDE_MEIO)

    def entrar_google(self):
        if self.tarefa and self.tarefa.is_alive():
            if estado.get("google_url"):
                webbrowser.open(estado["google_url"])
            return
        self.btn_google.config(text="Abrir o navegador de novo")
        self.st_google.config(text="Aguardando você entrar no Google, no navegador...", fg=VERDE_MEIO)

        def fim(_, erro):
            self.btn_google.config(text="Entrar com o Google")
            if erro:
                if erro != "Cancelado.":
                    self.st_google.config(text=f"Não deu certo: {erro}", fg=ERRO)
            else:
                email = estado.get("google_email")
                self.st_google.config(text=f"✓  Google conectado{': ' + email if email else '.'}", fg=OK)
                self.btn_google.pack_forget()
                self.btn_pular.pack_forget()
                self.concluir(3, "ok")
                self.btn_avancar.config(state="normal")

        self.rodar(tarefa_google, fim)

    def montar_resumo(self):
        """Roda o checkup completo e mostra cada item com o resultado."""
        if self.tarefa and self.tarefa.is_alive():
            self.raiz.after(500, self.montar_resumo)
            return
        for m in self.ck.values():
            m.marcar("pendente")
        self.btn_checkup.config(state="disabled")
        self.ck_resumo.config(text="Testando... (o teste do Claude pode levar até 2 minutos)", fg=VERDE_MEIO)
        self.final.config(text="")

        def item(chave, situacao, rotulo):
            def aplicar():
                self.ck[chave].marcar(situacao)
                self.ck[chave].texto.config(text=rotulo)
            na_tela(aplicar)

        def fim(problemas, erro):
            self.btn_checkup.config(state="normal")
            if self.pagina == 4:
                self.titulo.config(text="Tudo pronto!" if not erro and not problemas else "Quase pronto")
            if erro:
                self.ck_resumo.config(text=f"O checkup não terminou: {erro}", fg=ERRO)
            elif problemas:
                self.ck_resumo.config(text=f"Atenção: {problemas} item(ns) com problema. Abra o Configurar-Assessor de novo para "
                                           "ajustar; se o problema for no Hermes, reinstale pelo site oficial.", fg=ERRO)
            else:
                self.ck_resumo.config(text="✓  Tudo funcionando. O Assessor está pronto para usar.", fg=OK)
                self.final.config(text=("Fale com o Assessor pelo seu robô no Telegram ou pelo aplicativo Hermes. Na primeira "
                                        "conversa ele se apresenta e pergunta as suas preferências."))
            registrar(f"[checkup] problemas: {problemas if not erro else erro}")

        self.rodar(tarefa_checkup, fim, item)

    def abrir_assessor(self):
        if os.path.isfile(APP):
            os.startfile(APP)
        else:
            hx = achar_hermes()
            if hx:
                subprocess.Popen(["cmd", "/c", "start", "", hx, "chat"])

    # ----- relogio da janela -----
    def mostrar_log(self, msg):
        self.caixa_log.insert("end", msg + "\n")
        self.caixa_log.see("end")
        if self.tarefa and self.tarefa.is_alive():
            self.status.config(text=msg[:120])

    def alternar_detalhes(self):
        if self.caixa_log.winfo_ismapped():
            self.caixa_log.pack_forget()
            self.btn_detalhes.config(text="▸ Ver detalhes")
        else:
            self.caixa_log.pack(fill="x", pady=(6, 0))
            self.btn_detalhes.config(text="▾ Ver detalhes")

    def relogio(self):
        try:
            while True:
                fila.get_nowait()()
        except queue.Empty:
            pass
        except Exception:
            registrar(traceback.format_exc())
        if not (self.tarefa and self.tarefa.is_alive()) and self.status.cget("text") != STATUS[self.pagina]:
            self.status.config(text=STATUS[self.pagina])
        feitos = sum(1 for p in self.passos if p.estado in ("ok", "pulado"))
        fracao = sum(1 for s in self.subs if s.estado in ("ok", "pulado", "erro")) / len(self.subs) if self.pagina == 1 else 0
        pct = 100 if self.pagina == 4 else int((feitos + fracao) / len(PASSOS) * 100)
        self.barra_geral["value"] = pct
        self.pct.config(text=f"{pct}%")
        self.raiz.after(150, self.relogio)


if __name__ == "__main__":
    registrar("=== Assistente do Assessor aberto ===")
    raiz = tk.Tk()
    try:
        raiz.iconbitmap(default="")
    except tk.TclError:
        pass
    janela = Janela(raiz)
    raiz.mainloop()

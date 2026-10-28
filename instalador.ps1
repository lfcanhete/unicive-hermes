# UNICIVE - Instalador visual da Pauta (Hermes Agent + Claude + Google + Telegram)
# Aberto pelo Instalar-Pauta.cmd (gerado pelo gerar-instalador.ps1). Variaveis opcionais:
#   UNICIVE_GOOGLE   client_secret.json do Google em base64
#   UNICIVE_DEMO=1   percorre as telas sem instalar nada (para conferir o visual)
$ErrorActionPreference = "Continue"
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$HermesHome = if ($env:HERMES_HOME) { $env:HERMES_HOME } else { Join-Path $env:LOCALAPPDATA "hermes" }
$cfg = @{
    Repo       = "https://raw.githubusercontent.com/lfcanhete/unicive-hermes/main"
    Modelo     = "claude-sonnet-5-5"
    Skills     = @("productivity\resumo-reuniao", "productivity\oficio-institucional")
    HermesHome = $HermesHome
    AppExe     = Join-Path $HermesHome "hermes-agent\apps\desktop\release\win-unpacked\Hermes.exe"
    Atalho     = Join-Path ([Environment]::GetFolderPath("Desktop")) "Hermes.lnk"
    Google     = [bool]$env:UNICIVE_GOOGLE
    GoogleB64  = $env:UNICIVE_GOOGLE
    Demo       = [bool]$env:UNICIVE_DEMO
}
$sync = [hashtable]::Synchronized(@{
    Log = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
    Sub = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
})

# ---------- Codigo que roda em segundo plano (a janela continua respondendo) ----------
$Comum = {
    $ErrorActionPreference = "Stop"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $HermesHome = $cfg.HermesHome

    function Log([string]$m) { $sync.Log.Enqueue($m) }
    function Sub([int]$i, [string]$estado) { $sync.Sub.Enqueue("$i|$estado") }

    function AcharHermes {
        if ($cfg.Demo) { return "hermes.exe" }
        $exe = Join-Path $HermesHome "bin\hermes.exe"
        if (Test-Path $exe) { return $exe }
        $cmd = Get-Command hermes -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
        # O instalador oficial pode deixar so o hermes.cmd dentro da pasta do projeto.
        $hcmd = Join-Path $HermesHome "hermes-agent\.hermes\bin\hermes.cmd"
        if (Test-Path $hcmd) { return $hcmd }
        return $null
    }

    function Juntar([string[]]$a) {
        ($a | ForEach-Object { if ($_ -match '[\s"]') { '"' + $_.Replace('"', '\"') + '"' } else { $_ } }) -join ' '
    }

    function NovoProcesso([string]$exe, [string[]]$argumentos) {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        if ($exe -like "*.cmd") { $psi.FileName = $env:ComSpec; $psi.Arguments = '/d /s /c ""' + $exe + '" ' + (Juntar $argumentos) + '"' }
        else { $psi.FileName = $exe; $psi.Arguments = Juntar $argumentos }
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
        $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
        $psi.EnvironmentVariables["PYTHONIOENCODING"] = "utf-8"
        $psi.EnvironmentVariables["NO_COLOR"] = "1"
        return $psi
    }

    # Roda um programa, manda a saida para "Ver detalhes" e devolve o codigo de saida.
    function Executar([string]$exe, [string[]]$argumentos) {
        $script:saida = ""
        if ($cfg.Demo) { Log "[demo] $exe $($argumentos -join ' ')"; Start-Sleep -Milliseconds 900; $script:saida = "Hermes Agent v0"; return 0 }
        $p = [Diagnostics.Process]::Start((NovoProcesso $exe $argumentos))
        $erros = $p.StandardError.ReadToEndAsync()
        $tudo = New-Object Text.StringBuilder
        while ($null -ne ($l = $p.StandardOutput.ReadLine())) { Log $l; [void]$tudo.AppendLine($l) }
        $p.WaitForExit()
        foreach ($l in ($erros.Result -split "`r?`n")) { if ($l) { Log $l; [void]$tudo.AppendLine($l) } }
        $script:saida = $tudo.ToString()
        return $p.ExitCode
    }

    function Pegar($rel, $destino) {
        if ($cfg.Demo) { Log "[demo] baixar $rel"; return }
        New-Item -ItemType Directory -Force -Path (Split-Path $destino) | Out-Null
        Invoke-WebRequest "$($cfg.Repo)/$($rel.Replace('\','/'))" -OutFile $destino -UseBasicParsing
    }

    function SalvarEnv([hashtable]$valores) {
        if ($cfg.Demo) { Log "[demo] .env: $($valores.Keys -join ', ')"; return }
        $arq = Join-Path $HermesHome ".env"
        $linhas = @()
        if (Test-Path $arq) {
            $linhas = @(Get-Content $arq | Where-Object { $l = $_; -not ($valores.Keys | Where-Object { $l -match "^$_=" }) })
        }
        foreach ($k in $valores.Keys) { $linhas += "$k=$($valores[$k])" }
        [IO.File]::WriteAllLines($arq, [string[]]$linhas, (New-Object Text.UTF8Encoding($false)))
    }

    function B64Url([byte[]]$b) { [Convert]::ToBase64String($b).TrimEnd('=').Replace('+', '-').Replace('/', '_') }

    # A virgula impede o PowerShell de desmontar o byte[] em uma lista de numeros.
    function JsonUtf8($obj) { return , [Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Depth 5)) }
}

$TarefaInstalar = {
    Sub 0 "ativo"
    $hx = AcharHermes
    if (-not $hx) {
        Log "Baixando o instalador oficial do Hermes..."
        [void](Executar "powershell.exe" @("-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", "iex (irm https://hermes-agent.nousresearch.com/install.ps1)"))
        $env:Path = [Environment]::GetEnvironmentVariable("Path", "User") + ";" + [Environment]::GetEnvironmentVariable("Path", "Machine")
        $hx = AcharHermes
    }
    if (-not $hx) { throw "O Hermes não foi encontrado depois da instalação." }
    [void](Executar $hx @("--version"))
    if ($script:saida -notmatch "Hermes Agent v") {
        Log "Completando a instalação (reparo automático)..."
        [void](Executar $hx @("pm", "repair"))
    }
    if (-not $cfg.Demo) {
        # Deixa o comando "hermes" disponivel em novas janelas do PowerShell.
        $pasta = Split-Path $hx
        $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if (-not (($userPath -split ';') -contains $pasta)) {
            [Environment]::SetEnvironmentVariable("Path", ($userPath.TrimEnd(';') + ";" + $pasta), "User")
        }
    }
    Sub 0 "ok"

    Sub 1 "ativo"
    $trava = Join-Path $HermesHome ".hermes-update-in-progress"
    $instLocal = Join-Path $HermesHome "hermes-agent\scripts\install.ps1"
    if ($cfg.Demo) { [void](Executar "install.ps1" @("-Stage", "products", "-IncludeDesktop")) }
    elseif (-not (Test-Path $cfg.AppExe) -and (Test-Path $instLocal)) {
        Log "Instalando o aplicativo Hermes Desktop..."
        if (Test-Path $trava) { Remove-Item $trava -Force -ErrorAction SilentlyContinue }
        # Pode terminar com erro na etapa do launcher mesmo com o app pronto; o que vale e o Hermes.exe.
        [void](Executar "powershell.exe" @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $instLocal, "-Stage", "products", "-IncludeDesktop"))
    }
    # Uma etapa do app que termina com erro deixa esta trava, e o app fica esperando uma atualizacao que nao existe.
    if (-not $cfg.Demo -and (Test-Path $trava)) { Remove-Item $trava -Force -ErrorAction SilentlyContinue }
    if (-not $cfg.Demo -and (Test-Path $cfg.AppExe) -and -not (Test-Path $cfg.Atalho)) {
        $ws = New-Object -ComObject WScript.Shell
        foreach ($dir in @([Environment]::GetFolderPath("Desktop"), [Environment]::GetFolderPath("Programs"))) {
            $sc = $ws.CreateShortcut((Join-Path $dir "Hermes.lnk")); $sc.TargetPath = $cfg.AppExe; $sc.WorkingDirectory = Split-Path $cfg.AppExe; $sc.Save()
        }
        Log "Atalho do Hermes criado na área de trabalho."
    }
    if ($cfg.Demo -or (Test-Path $cfg.AppExe)) { Sub 1 "ok" } else { Log "O aplicativo não ficou pronto; a Pauta continua disponível pelo comando hermes."; Sub 1 "pulado" }

    Sub 2 "ativo"
    [void](Executar $hx @("config", "set", "model.provider", "anthropic"))
    [void](Executar $hx @("config", "set", "model.default", $cfg.Modelo))
    $soul = Join-Path $HermesHome "SOUL.md"
    if (-not $cfg.Demo -and (Test-Path $soul) -and -not (Test-Path "$soul.original")) { Copy-Item $soul "$soul.original" }
    Pegar "SOUL.md" $soul
    foreach ($s in $cfg.Skills) { Pegar "skills\$(Split-Path $s -Leaf)\SKILL.md" (Join-Path $HermesHome "skills\$s\SKILL.md") }
    Sub 2 "ok"

    if ($cfg.Google) {
        Sub 3 "ativo"
        $json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($cfg.GoogleB64))
        if ($json -notmatch '"installed"') { throw "A configuração do Google deste instalador está incompleta." }
        if (-not $cfg.Demo) { [IO.File]::WriteAllText((Join-Path $HermesHome "google_client_secret.json"), $json, (New-Object Text.UTF8Encoding($false))) }
        Log "Instalando os componentes do Google..."
        [void](Executar $hx @("pm", "install", "--extra", "google"))
        Sub 3 "ok"
    }
}

$TarefaClaude = {
    if ($cfg.Demo) {
        $sync.ClaudeUrl = "https://claude.ai/oauth/authorize?demo"; $sync.ClaudeEsperando = $true
        while (-not $sync.ClaudeCodigo) { if ($sync.Cancelar) { throw "Cancelado." }; Start-Sleep -Milliseconds 200 }
        $sync.ClaudeEsperando = $false; Start-Sleep 1; return
    }
    $psi = NovoProcesso (AcharHermes) @("auth", "add", "anthropic", "--type", "oauth")
    $psi.RedirectStandardInput = $true
    $p = [Diagnostics.Process]::Start($psi)
    $erros = $p.StandardError.ReadToEndAsync()
    $tudo = New-Object Text.StringBuilder
    $inicio = Get-Date
    $leitura = $p.StandardOutput.ReadLineAsync()
    while ($true) {
        if ($leitura.Wait(250)) {
            $l = $leitura.Result
            if ($null -eq $l) { break }
            Log $l; [void]$tudo.AppendLine($l)
            if ($l -match '(https://claude\.ai/oauth/authorize\S+)') { $sync.ClaudeUrl = $Matches[1] }
            if ($l -match 'Paste it below') { $sync.ClaudeEsperando = $true }
            $leitura = $p.StandardOutput.ReadLineAsync()
        }
        if ($sync.ClaudeEsperando -and $sync.ClaudeCodigo) {
            $p.StandardInput.WriteLine($sync.ClaudeCodigo); $p.StandardInput.Close()
            $sync.ClaudeEsperando = $false; $sync.ClaudeCodigo = $null
        }
        if ($sync.Cancelar) { try { $p.Kill() } catch {}; throw "Cancelado." }
        if (-not $sync.ClaudeUrl -and ((Get-Date) - $inicio).TotalSeconds -gt 90) { try { $p.Kill() } catch {}; throw "O login do Claude não começou." }
    }
    $p.WaitForExit()
    foreach ($l in ($erros.Result -split "`r?`n")) { if ($l) { Log $l; [void]$tudo.AppendLine($l) } }
    if ($p.ExitCode -ne 0 -or $tudo.ToString() -match 'failed|mismatch|No access token|No code entered') {
        throw "O Claude não aceitou o código."
    }
}

$TarefaGoogle = {
    if ($cfg.Demo) { Start-Sleep 3; $sync.GoogleEmail = "diretor@unicive.edu.br"; return }
    $inst = (Get-Content (Join-Path $HermesHome "google_client_secret.json") -Raw | ConvertFrom-Json).installed
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    $buf = New-Object byte[] 32
    $rng.GetBytes($buf); $verifier = B64Url $buf
    $rng.GetBytes($buf); $state = B64Url $buf
    $challenge = B64Url ([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::ASCII.GetBytes($verifier)))
    # Mesmos escopos da skill google-workspace do Hermes.
    $escopos = @(
        "https://www.googleapis.com/auth/gmail.readonly", "https://www.googleapis.com/auth/gmail.send",
        "https://www.googleapis.com/auth/gmail.modify", "https://www.googleapis.com/auth/calendar",
        "https://www.googleapis.com/auth/drive", "https://www.googleapis.com/auth/contacts.readonly",
        "https://www.googleapis.com/auth/spreadsheets", "https://www.googleapis.com/auth/documents")
    # O Google devolve o login para este endereco local, sem o diretor precisar colar nada.
    $ouvinte = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0)
    $ouvinte.Start()
    $retorno = "http://127.0.0.1:$($ouvinte.LocalEndpoint.Port)/"
    $q = [ordered]@{ client_id = $inst.client_id; redirect_uri = $retorno; response_type = "code"; scope = ($escopos -join ' ')
        code_challenge = $challenge; code_challenge_method = "S256"; state = $state; access_type = "offline"; prompt = "consent" }
    $sync.GoogleUrl = "https://accounts.google.com/o/oauth2/v2/auth?" + (($q.GetEnumerator() | ForEach-Object { $_.Key + "=" + [Uri]::EscapeDataString($_.Value) }) -join "&")
    Start-Process $sync.GoogleUrl
    Log "Aguardando a autorização no navegador..."
    $codigo = $null; $inicio = Get-Date
    try {
        while (-not $codigo) {
            if ($sync.Cancelar) { throw "Cancelado." }
            if (((Get-Date) - $inicio).TotalMinutes -gt 10) { throw "O tempo para entrar no Google acabou." }
            if (-not $ouvinte.Pending()) { Start-Sleep -Milliseconds 200; continue }
            $cli = $ouvinte.AcceptTcpClient(); $cli.ReceiveTimeout = 3000
            try {
                $fluxo = $cli.GetStream()
                $linha = (New-Object IO.StreamReader($fluxo)).ReadLine()
                $par = @{}
                if ($linha -match '^GET\s+/\?(\S+)') {
                    foreach ($kv in ($Matches[1] -split '&')) { $x = $kv -split '=', 2; if ($x.Count -eq 2) { $par[$x[0]] = [Uri]::UnescapeDataString($x[1].Replace('+', ' ')) } }
                }
                if ($par.code -or $par.error) {
                    $ok = $par.code -and ($par.state -eq $state)
                    $msg = if ($ok) { "Pronto! O Google foi conectado. Pode fechar esta aba e voltar ao instalador." } else { "Não deu certo. Volte ao instalador e tente de novo." }
                    $html = "<!doctype html><meta charset=utf-8><title>Pauta</title><body style=`"font-family:Segoe UI,sans-serif;background:#004A3B;color:#fff;display:flex;align-items:center;justify-content:center;height:100vh;margin:0`"><div style=`"text-align:center;max-width:520px;padding:24px`"><h1 style=`"color:#FFC571;font-weight:600`">Pauta &middot; UNICIVE</h1><p style=`"font-size:18px;line-height:1.5`">$msg</p></div>"
                    $corpo = [Text.Encoding]::UTF8.GetBytes($html)
                    $cab = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 200 OK`r`nContent-Type: text/html; charset=utf-8`r`nContent-Length: $($corpo.Length)`r`nConnection: close`r`n`r`n")
                    $fluxo.Write($cab, 0, $cab.Length); $fluxo.Write($corpo, 0, $corpo.Length); $fluxo.Flush()
                    if (-not $ok) { throw "O Google não autorizou ($($par.error))." }
                    $codigo = $par.code
                } else {
                    $b = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 404 Not Found`r`nContent-Length: 0`r`nConnection: close`r`n`r`n")
                    $fluxo.Write($b, 0, $b.Length)
                }
            } catch [IO.IOException] { } finally { $cli.Close() }
        }
    } finally { $ouvinte.Stop() }

    $r = Invoke-RestMethod -Method Post -Uri "https://oauth2.googleapis.com/token" -UseBasicParsing -Body @{
        code = $codigo; client_id = $inst.client_id; client_secret = $inst.client_secret
        redirect_uri = $retorno; grant_type = "authorization_code"; code_verifier = $verifier }
    if (-not $r.refresh_token) { throw "O Google não devolveu a autorização completa." }
    # Mesmo formato que a skill google-workspace grava (google-auth "authorized_user").
    $token = [ordered]@{
        token = $r.access_token; refresh_token = $r.refresh_token; token_uri = "https://oauth2.googleapis.com/token"
        client_id = $inst.client_id; client_secret = $inst.client_secret; scopes = @($r.scope -split ' ')
        universe_domain = "googleapis.com"; account = ""
        expiry = (Get-Date).ToUniversalTime().AddSeconds([int]$r.expires_in - 60).ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture)
        type = "authorized_user" }
    [IO.File]::WriteAllText((Join-Path $HermesHome "google_token.json"), ($token | ConvertTo-Json -Depth 3), (New-Object Text.UTF8Encoding($false)))
    Log "Token do Google salvo."
    try {
        $perfil = Invoke-RestMethod -Uri "https://gmail.googleapis.com/gmail/v1/users/me/profile" -Headers @{ Authorization = "Bearer $($r.access_token)" } -UseBasicParsing
        $sync.GoogleEmail = $perfil.emailAddress
    } catch { Log "Não consegui ler o endereço do Gmail: $($_.Exception.Message)" }
}

$TarefaVerificarBot = {
    if ($cfg.Demo) { Start-Sleep 1; $sync.TgBot = "pauta_direcao_bot"; return }
    try { $r = Invoke-RestMethod "https://api.telegram.org/bot$($sync.TgToken)/getMe" -UseBasicParsing }
    catch { throw "O Telegram não reconheceu este token. Copie de novo a mensagem do BotFather." }
    $sync.TgBot = $r.result.username
}

$TarefaTelegram = {
    if ($cfg.Demo) { Start-Sleep 4; $sync.TgNome = "Diretor"; [void](Executar "hermes.exe" @("gateway", "install")); return }
    $base = "https://api.telegram.org/bot$($sync.TgToken)"
    # Ignora mensagens antigas: so vale a que chegar agora.
    $offset = 0
    foreach ($x in (Invoke-RestMethod "$base/getUpdates?timeout=0" -UseBasicParsing).result) { $offset = [Math]::Max($offset, [int64]$x.update_id + 1) }
    Log "Aguardando a sua mensagem no Telegram..."
    $de = $null
    while (-not $de) {
        if ($sync.Cancelar) { throw "Cancelado." }
        $u = Invoke-RestMethod "$base/getUpdates?timeout=15&offset=$offset" -TimeoutSec 25 -UseBasicParsing
        foreach ($x in $u.result) {
            $offset = [int64]$x.update_id + 1
            if ($x.message -and $x.message.chat.type -eq "private") { $de = $x.message.from }
        }
    }
    [void](Invoke-RestMethod "$base/getUpdates?offset=$offset&timeout=0" -UseBasicParsing)
    $sync.TgNome = $de.first_name
    Log "Mensagem recebida de $($de.first_name) (id $($de.id))."
    SalvarEnv @{ TELEGRAM_BOT_TOKEN = $sync.TgToken; TELEGRAM_ALLOWED_USERS = "$($de.id)"; TELEGRAM_HOME_CHANNEL = "$($de.id)" }
    $texto = "Olá, $($de.first_name)! Aqui é a Pauta, assistente da direção do UNICIVE. A partir de agora você também pode falar comigo por aqui."
    [void](Invoke-RestMethod -Method Post "$base/sendMessage" -ContentType "application/json; charset=utf-8" -Body (JsonUtf8 @{ chat_id = $de.id; text = $texto }) -UseBasicParsing)
    $hx = AcharHermes
    Log "Deixando a Pauta ligada no Telegram (inicia junto com o Windows)..."
    [void](Executar $hx @("gateway", "install", "--if-missing", "--start-now", "--start-on-login"))
    [void](Executar $hx @("gateway", "restart"))
}

# ---------- Janela ----------
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Instalar a Pauta · UNICIVE" Width="940" Height="700" WindowStartupLocation="CenterScreen"
        ResizeMode="CanMinimize" Background="#F0F8F4" FontFamily="Segoe UI" FontSize="14" Foreground="#122B23">
  <Window.Resources>
    <Style x:Key="Primario" TargetType="Button">
      <Setter Property="Background" Value="#FFC571"/>
      <Setter Property="Foreground" Value="#00382D"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="24,10"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="20" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.85"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.4"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Secundario" TargetType="Button" BasedOn="{StaticResource Primario}">
      <Setter Property="Background" Value="#DDEFE6"/>
      <Setter Property="Foreground" Value="#006652"/>
    </Style>
    <Style x:Key="Cartao" TargetType="Border">
      <Setter Property="Background" Value="White"/>
      <Setter Property="CornerRadius" Value="12"/>
      <Setter Property="Padding" Value="16,12"/>
      <Setter Property="Margin" Value="0,10,0,0"/>
    </Style>
    <Style x:Key="Campo" TargetType="TextBox">
      <Setter Property="Padding" Value="8,7"/>
      <Setter Property="FontFamily" Value="Consolas"/>
      <Setter Property="BorderBrush" Value="#A8CFC0"/>
    </Style>
  </Window.Resources>
  <Grid>
    <Grid.ColumnDefinitions><ColumnDefinition Width="250"/><ColumnDefinition/></Grid.ColumnDefinitions>
    <Border Background="#004A3B">
      <DockPanel Margin="26,30">
        <StackPanel DockPanel.Dock="Top">
          <TextBlock Text="UNICIVE · DIREÇÃO" Foreground="#FFC571" FontWeight="Bold" FontSize="11"/>
          <TextBlock Text="Pauta" Foreground="White" FontSize="34" FontFamily="Georgia" Margin="0,6,0,0"/>
          <TextBlock Text="Instalação guiada" Foreground="#A8CFC0"/>
        </StackPanel>
        <TextBlock DockPanel.Dock="Bottom" Text="Dúvidas? Chame o Luiz Fernando." Foreground="#A8CFC0" FontSize="12" TextWrapping="Wrap"/>
        <StackPanel x:Name="ListaPassos" Margin="0,40,0,0"/>
      </DockPanel>
    </Border>
    <Grid Grid.Column="1" Margin="44,34,44,26">
      <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
      <TextBlock x:Name="TxtPasso" Foreground="#B27B2E" FontWeight="Bold" FontSize="12"/>
      <TextBlock x:Name="TxtTitulo" Grid.Row="1" FontSize="28" FontFamily="Georgia" Margin="0,6,0,12" TextWrapping="Wrap"/>
      <DockPanel Grid.Row="2">
        <Expander x:Name="Detalhes" DockPanel.Dock="Bottom" Header="Ver detalhes" Foreground="#006652" Margin="0,10,0,0">
          <TextBox x:Name="TxtLog" Height="130" IsReadOnly="True" FontFamily="Consolas" FontSize="11" TextWrapping="Wrap"
                   VerticalScrollBarVisibility="Auto" Background="#00382D" Foreground="#5BDC9E" BorderThickness="0" Padding="8" Margin="0,6,0,0"/>
        </Expander>
        <ScrollViewer VerticalScrollBarVisibility="Auto" Focusable="False">
          <Grid>
            <StackPanel x:Name="P0">
              <TextBlock TextWrapping="Wrap" FontSize="15" Text="Este instalador deixa a Pauta pronta para usar: instala o Hermes, conecta o Claude, o Google e o Telegram. No final, é só abrir e conversar."/>
              <TextBlock Margin="0,20,0,6" FontWeight="SemiBold" Text="Tenha por perto:"/>
              <TextBlock Margin="0,3" Text="•   a sua conta do Claude"/>
              <TextBlock Margin="0,3" Text="•   a sua conta @unicive.edu.br"/>
              <TextBlock Margin="0,3" Text="•   o Telegram instalado no celular ou no computador"/>
              <Border Background="#FFF1DA" CornerRadius="10" Padding="14,10" Margin="0,22,0,0">
                <TextBlock TextWrapping="Wrap" Text="Leva uns 10 minutos. Não feche esta janela até o final. Se algo der errado, ela mesma explica o que fazer."/>
              </Border>
            </StackPanel>
            <StackPanel x:Name="P1" Visibility="Collapsed">
              <TextBlock TextWrapping="Wrap" FontSize="15" Text="Agora é com o instalador: ele baixa e configura tudo sozinho. Pode levar alguns minutos, e você não precisa fazer nada."/>
              <StackPanel x:Name="ListaInstala" Margin="0,18,0,0"/>
              <ProgressBar x:Name="Barra" Height="6" Margin="0,14,0,0" IsIndeterminate="True" Foreground="#006652" Background="#D8EDE3" BorderThickness="0"/>
              <TextBlock x:Name="TxtErroInstala" Foreground="#B0472F" TextWrapping="Wrap" Margin="0,12,0,0" Visibility="Collapsed"/>
            </StackPanel>
            <StackPanel x:Name="P2" Visibility="Collapsed">
              <TextBlock TextWrapping="Wrap" FontSize="15" Text="O Claude é o cérebro da Pauta. Conecte a sua conta em três passos:"/>
              <Border Style="{StaticResource Cartao}">
                <StackPanel>
                  <TextBlock TextWrapping="Wrap" Text="1.  Clique em Entrar com o Claude. O navegador vai abrir."/>
                  <TextBlock TextWrapping="Wrap" Margin="0,6,0,0" Text="2.  Entre na sua conta e clique em Authorize (Autorizar)."/>
                  <TextBlock TextWrapping="Wrap" Margin="0,6,0,0" Text="3.  Vai aparecer um código. Clique em Copy (Copiar): o instalador percebe sozinho."/>
                </StackPanel>
              </Border>
              <Button x:Name="BtnClaude" Style="{StaticResource Primario}" Content="Entrar com o Claude" HorizontalAlignment="Left" Margin="0,16,0,0"/>
              <StackPanel x:Name="CaixaCodigo" Margin="0,16,0,0" Visibility="Collapsed">
                <TextBlock Text="Se ele não perceber, cole o código aqui:" Margin="0,0,0,6"/>
                <StackPanel Orientation="Horizontal">
                  <TextBox x:Name="TxtCodigo" Width="380" Style="{StaticResource Campo}"/>
                  <Button x:Name="BtnCodigo" Style="{StaticResource Secundario}" Content="Confirmar" Margin="10,0,0,0"/>
                </StackPanel>
              </StackPanel>
              <TextBlock x:Name="TxtClaude" Margin="0,14,0,0" TextWrapping="Wrap" FontWeight="SemiBold"/>
            </StackPanel>
            <StackPanel x:Name="P3" Visibility="Collapsed">
              <TextBlock x:Name="TxtGoogleIntro" TextWrapping="Wrap" FontSize="15" Text="Com o Google conectado, a Pauta lê seus e-mails, sua agenda e seus documentos para fazer briefings e rascunhos. Ela nunca envia nada sem você pedir."/>
              <Border x:Name="CartaoGoogle" Style="{StaticResource Cartao}">
                <StackPanel>
                  <TextBlock TextWrapping="Wrap" Text="1.  Clique em Entrar com o Google."/>
                  <TextBlock TextWrapping="Wrap" Margin="0,6,0,0" Text="2.  Escolha a sua conta @unicive.edu.br."/>
                  <TextBlock TextWrapping="Wrap" Margin="0,6,0,0" Text="3.  Marque as permissões e clique em Continuar. Depois é só voltar para esta janela."/>
                </StackPanel>
              </Border>
              <Button x:Name="BtnGoogle" Style="{StaticResource Primario}" Content="Entrar com o Google" HorizontalAlignment="Left" Margin="0,16,0,0"/>
              <TextBlock x:Name="TxtGoogle" Margin="0,14,0,0" TextWrapping="Wrap" FontWeight="SemiBold"/>
            </StackPanel>
            <StackPanel x:Name="P4" Visibility="Collapsed">
              <TextBlock TextWrapping="Wrap" FontSize="15" Text="Pelo Telegram você fala com a Pauta de qualquer lugar. Você vai criar um robô só seu:"/>
              <Border Style="{StaticResource Cartao}">
                <StackPanel>
                  <TextBlock FontWeight="SemiBold" Text="1.  Crie o seu robô"/>
                  <TextBlock TextWrapping="Wrap" Margin="0,4,0,0" Text="No BotFather, envie /newbot. Dê um nome (ex.: Pauta Marcela) e depois um usuário que termine em bot (ex.: pauta_marcela_bot). Ele responde com um token: copie a linha com o token."/>
                  <Button x:Name="BtnBotFather" Style="{StaticResource Secundario}" Content="Abrir o BotFather" HorizontalAlignment="Left" Margin="0,10,0,0" Padding="18,7"/>
                </StackPanel>
              </Border>
              <Border Style="{StaticResource Cartao}">
                <StackPanel>
                  <TextBlock FontWeight="SemiBold" Text="2.  Cole o token"/>
                  <StackPanel Orientation="Horizontal" Margin="0,8,0,0">
                    <TextBox x:Name="TxtToken" Width="380" Style="{StaticResource Campo}"/>
                    <Button x:Name="BtnToken" Style="{StaticResource Secundario}" Content="Verificar" Margin="10,0,0,0" Padding="18,7"/>
                  </StackPanel>
                  <TextBlock x:Name="TxtTokenOk" Margin="0,8,0,0" TextWrapping="Wrap" FontWeight="SemiBold"/>
                </StackPanel>
              </Border>
              <Border Style="{StaticResource Cartao}">
                <StackPanel>
                  <TextBlock FontWeight="SemiBold" Text="3.  Diga oi para o seu robô"/>
                  <TextBlock TextWrapping="Wrap" Margin="0,4,0,0" Text="Abra o seu robô e toque em Iniciar (ou mande um oi). Assim ele fica sabendo que você é o dono."/>
                  <Button x:Name="BtnAbrirBot" Style="{StaticResource Secundario}" Content="Abrir o meu robô" HorizontalAlignment="Left" Margin="0,10,0,0" Padding="18,7" IsEnabled="False"/>
                  <TextBlock x:Name="TxtTelegram" Margin="0,8,0,0" TextWrapping="Wrap" FontWeight="SemiBold"/>
                </StackPanel>
              </Border>
            </StackPanel>
            <StackPanel x:Name="P5" Visibility="Collapsed">
              <TextBlock TextWrapping="Wrap" FontSize="15" Text="A Pauta está instalada e configurada. Na primeira conversa ela se apresenta e pergunta as suas preferências."/>
              <StackPanel x:Name="ListaResumo" Margin="0,18,0,0"/>
              <Button x:Name="BtnAbrir" Style="{StaticResource Primario}" Content="Abrir a Pauta" HorizontalAlignment="Left" Margin="0,22,0,0"/>
              <TextBlock x:Name="TxtFinal" Margin="0,16,0,0" TextWrapping="Wrap" Foreground="#006652"/>
            </StackPanel>
          </Grid>
        </ScrollViewer>
      </DockPanel>
      <DockPanel Grid.Row="3" Margin="0,16,0,0" LastChildFill="False">
        <Button x:Name="BtnPular" Style="{StaticResource Secundario}" Content="Pular por enquanto" DockPanel.Dock="Left" Visibility="Collapsed"/>
        <Button x:Name="BtnAvancar" Style="{StaticResource Primario}" Content="Começar" DockPanel.Dock="Right"/>
      </DockPanel>
    </Grid>
  </Grid>
</Window>
'@
$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
foreach ($n in $xaml.SelectNodes("//*[@*[local-name()='Name']]")) {
    $nome = $n.Attributes | Where-Object { $_.LocalName -eq "Name" } | Select-Object -First 1 -ExpandProperty Value
    Set-Variable -Name $nome -Value $win.FindName($nome) -Scope Script
}

function Cor([string]$hex) { (New-Object Windows.Media.BrushConverter).ConvertFromString($hex) }

function NovoItem([string]$texto, [string]$marca, [bool]$escuro) {
    $sp = New-Object Windows.Controls.StackPanel; $sp.Orientation = "Horizontal"; $sp.Margin = "0,0,0,14"
    $bola = New-Object Windows.Controls.Border; $bola.Width = 26; $bola.Height = 26; $bola.CornerRadius = 13; $bola.BorderThickness = 1.5
    $m = New-Object Windows.Controls.TextBlock; $m.Text = $marca; $m.HorizontalAlignment = "Center"; $m.VerticalAlignment = "Center"; $m.FontWeight = [Windows.FontWeights]::Bold; $m.FontSize = 12
    $bola.Child = $m
    $t = New-Object Windows.Controls.TextBlock; $t.Text = $texto; $t.Margin = "12,0,0,0"; $t.VerticalAlignment = "Center"; $t.TextWrapping = "Wrap"
    if (-not $escuro) { $t.MaxWidth = 520 }
    [void]$sp.Children.Add($bola); [void]$sp.Children.Add($t)
    return @{ Painel = $sp; Bola = $bola; Marca = $m; Texto = $t; Numero = $marca; Escuro = $escuro }
}

# estados: pendente, ativo, ok, pulado, erro
function Marcar($item, [string]$estado) {
    $fundo = @{ pendente = "Transparent"; ativo = "#FFC571"; ok = "#5BDC9E"; pulado = "Transparent"; erro = "#B0472F" }[$estado]
    $marca = @{ pendente = $item.Numero; ativo = $item.Numero; ok = "✓"; pulado = "–"; erro = "!" }[$estado]
    $item.Bola.Background = Cor $fundo
    $item.Marca.Text = $marca
    if ($item.Escuro) {
        $item.Bola.BorderBrush = Cor $(if ($estado -eq "pendente" -or $estado -eq "pulado") { "#3F7A6A" } else { $fundo })
        $item.Marca.Foreground = Cor $(if ($estado -eq "pendente" -or $estado -eq "pulado") { "#A8CFC0" } elseif ($estado -eq "erro") { "White" } else { "#00382D" })
        $item.Texto.Foreground = Cor $(if ($estado -eq "ativo" -or $estado -eq "ok") { "White" } else { "#A8CFC0" })
        $item.Texto.FontWeight = $(if ($estado -eq "ativo") { [Windows.FontWeights]::SemiBold } else { [Windows.FontWeights]::Normal })
    } else {
        $item.Bola.BorderBrush = Cor $(if ($estado -eq "pendente" -or $estado -eq "pulado") { "#A8CFC0" } else { $fundo })
        $item.Marca.Foreground = Cor $(if ($estado -eq "pendente" -or $estado -eq "pulado") { "#6B8F82" } elseif ($estado -eq "erro") { "White" } else { "#00382D" })
        $item.Texto.Foreground = Cor $(if ($estado -eq "pendente" -or $estado -eq "pulado") { "#6B8F82" } else { "#122B23" })
    }
    $item.Estado = $estado
}

$nomesPassos = @("Boas-vindas", "Instalação", "Claude", "Google", "Telegram", "Pronto")
$titulos = @("Vamos deixar a Pauta pronta", "Instalando o Hermes e a Pauta", "Conecte o Claude", "Conecte o Google", "Conecte o Telegram", "Tudo pronto!")
$passos = @()
for ($i = 0; $i -lt $nomesPassos.Count; $i++) {
    $it = NovoItem $nomesPassos[$i] "$($i + 1)" $true
    [void]$ListaPassos.Children.Add($it.Painel); Marcar $it "pendente"; $passos += $it
}
$subs = @()
$nomesSubs = @("Baixar e instalar o Hermes", "Instalar o aplicativo Hermes", "Configurar o Claude Sonnet 5.5 e a Pauta", "Preparar a conexão com o Google")
for ($i = 0; $i -lt $nomesSubs.Count; $i++) {
    $it = NovoItem $nomesSubs[$i] "$($i + 1)" $false
    [void]$ListaInstala.Children.Add($it.Painel); Marcar $it "pendente"; $subs += $it
}
if (-not $cfg.Google) { $subs[3].Texto.Text = "Google: não incluído neste instalador"; Marcar $subs[3] "pulado" }

# ---------- Tarefas em segundo plano ----------
$script:tarefa = $null
function Rodar([scriptblock]$Bloco, [scriptblock]$AoTerminar) {
    $sync.Erro = $null; $sync.Cancelar = $false
    $ps = [PowerShell]::Create()
    $ps.Runspace = [RunspaceFactory]::CreateRunspace()
    $ps.Runspace.Open()
    $ps.Runspace.SessionStateProxy.SetVariable("sync", $sync)
    $ps.Runspace.SessionStateProxy.SetVariable("cfg", $cfg)
    $codigo = $Comum.ToString() + "`ntry {`n" + $Bloco.ToString() + "`n} catch { `$sync.Erro = `$_.Exception.Message; Log ('ERRO: ' + `$_.Exception.Message) }"
    [void]$ps.AddScript($codigo)
    $script:tarefa = @{ PS = $ps; H = $ps.BeginInvoke(); Fim = $AoTerminar }
}

function Status($controle, [string]$texto, [string]$tipo) {
    $controle.Text = $texto
    $controle.Foreground = Cor $(switch ($tipo) { "ok" { "#2F7A4E" } "erro" { "#B0472F" } default { "#006652" } })
}

# ---------- Navegacao ----------
$script:pagina = 0
$script:feito = @{}
function IrPara([int]$i) {
    for ($k = 0; $k -le 5; $k++) { (Get-Variable "P$k" -ValueOnly).Visibility = "Collapsed" }
    (Get-Variable "P$i" -ValueOnly).Visibility = "Visible"
    if ($passos[$script:pagina].Estado -eq "ativo") { Marcar $passos[$script:pagina] "pendente" }
    $script:pagina = $i
    Marcar $passos[$i] "ativo"
    $TxtPasso.Text = "PASSO $($i + 1) DE $($passos.Count)"
    $TxtTitulo.Text = $titulos[$i]
    $BtnPular.Visibility = $(if ($i -eq 3 -or $i -eq 4) { "Visible" } else { "Collapsed" })
    $BtnAvancar.Content = $(if ($i -eq 0) { "Começar" } elseif ($i -eq 5) { "Concluir" } else { "Continuar" })
    $BtnAvancar.IsEnabled = ($i -eq 0 -or $i -eq 5)
    switch ($i) {
        1 { IniciarInstalacao }
        2 {
            if (-not $cfg.Demo -and (Test-Path (Join-Path $HermesHome ".anthropic_oauth.json"))) {
                Status $TxtClaude "✓  Este computador já está conectado ao Claude. Pode continuar, ou entrar de novo com outra conta." "ok"
                $BtnClaude.Content = "Entrar de novo"; $BtnAvancar.IsEnabled = $true
            }
        }
        3 {
            if (-not $cfg.Google) {
                $TxtGoogleIntro.Text = "Este instalador veio sem a configuração do Google. Peça à organização o instalador completo para conectar e-mail e agenda. Por enquanto a Pauta trabalha com o que você colar na conversa."
                $CartaoGoogle.Visibility = "Collapsed"; $BtnGoogle.Visibility = "Collapsed"; $BtnPular.Visibility = "Collapsed"; $BtnAvancar.IsEnabled = $true
            } elseif (-not $cfg.Demo -and (Test-Path (Join-Path $HermesHome "google_token.json"))) {
                Status $TxtGoogle "✓  Este computador já está conectado ao Google. Pode continuar, ou entrar de novo com outra conta." "ok"
                $BtnGoogle.Content = "Entrar de novo"; $BtnAvancar.IsEnabled = $true; $BtnPular.Visibility = "Collapsed"
            }
        }
        5 { MontarResumo }
    }
}

function Concluir([int]$i, [string]$estado) {
    $script:feito[$i] = $estado
    Marcar $passos[$i] $estado
}

function IniciarInstalacao {
    $TxtErroInstala.Visibility = "Collapsed"; $Barra.Visibility = "Visible"; $Barra.IsIndeterminate = $true
    $BtnAvancar.IsEnabled = $false; $BtnAvancar.Content = "Continuar"; $script:erroInstala = $false
    Rodar $TarefaInstalar {
        if ($sync.Erro) {
            foreach ($s in $subs) { if ($s.Estado -eq "ativo") { Marcar $s "erro" } }
            $Barra.Visibility = "Collapsed"
            $TxtErroInstala.Text = "Algo deu errado: $($sync.Erro)`nClique em Tentar de novo. Se continuar, abra Ver detalhes, tire uma foto da tela e envie para o suporte."
            $TxtErroInstala.Visibility = "Visible"
            Marcar $passos[1] "erro"; $script:erroInstala = $true
            $BtnAvancar.Content = "Tentar de novo"; $BtnAvancar.IsEnabled = $true
        } else {
            $Barra.IsIndeterminate = $false; $Barra.Value = 100
            Concluir 1 "ok"
            IrPara 2
        }
    }
}

function MontarResumo {
    $ListaResumo.Children.Clear()
    $linhas = @(
        @("Hermes e Pauta instalados", "ok"),
        @("Claude conectado (Sonnet 5.5)", $script:feito[2]),
        @($(if ($sync.GoogleEmail) { "Google conectado: $($sync.GoogleEmail)" } elseif ($script:feito[3] -eq "ok") { "Google conectado" } else { "Google: fica para depois" }), $script:feito[3]),
        @($(if ($sync.TgBot -and $script:feito[4] -eq "ok") { "Telegram conectado: @$($sync.TgBot)" } else { "Telegram: fica para depois" }), $script:feito[4])
    )
    foreach ($l in $linhas) {
        $estado = $(if ($l[1] -eq "ok") { "ok" } else { "pulado" })
        $it = NovoItem $l[0] "•" $false; Marcar $it $estado; [void]$ListaResumo.Children.Add($it.Painel)
    }
    $TxtFinal.Text = $(if ($script:feito[4] -eq "ok") { "No celular, procure @$($sync.TgBot) no Telegram: a Pauta já mandou uma mensagem para você." } else { "Nas próximas vezes, abra pelo atalho Hermes na área de trabalho." })
}

# ---------- Botoes ----------
$BtnAvancar.Add_Click({
    switch ($script:pagina) {
        0 { Concluir 0 "ok"; IrPara 1 }
        1 { if ($script:erroInstala) { Marcar $passos[1] "ativo"; foreach ($s in $subs) { if ($s.Estado -eq "erro") { Marcar $s "pendente" } }; IniciarInstalacao } else { IrPara 2 } }
        2 { if (-not $script:feito[2]) { Concluir 2 "ok" }; IrPara 3 }
        3 { if (-not $script:feito[3]) { Concluir 3 $(if (Test-Path (Join-Path $HermesHome "google_token.json")) { "ok" } else { "pulado" }) }; IrPara 4 }
        4 { IrPara 5 }
        5 { Concluir 5 "ok"; $win.Close() }
    }
})
$BtnPular.Add_Click({
    if ($script:tarefa) { $sync.Cancelar = $true }
    Concluir $script:pagina "pulado"; IrPara ($script:pagina + 1)
})

$BtnClaude.Add_Click({
    if ($script:tarefa) { if ($sync.ClaudeUrl) { Start-Process $sync.ClaudeUrl }; return }
    $sync.ClaudeUrl = $null; $sync.ClaudeCodigo = $null; $sync.ClaudeEsperando = $false; $sync.Cancelar = $false
    $BtnClaude.Content = "Abrir o navegador de novo"
    Status $TxtClaude "Abrindo o navegador..." ""
    Rodar $TarefaClaude {
        $CaixaCodigo.Visibility = "Collapsed"; $BtnClaude.Content = "Entrar com o Claude"
        if ($sync.Erro) { Status $TxtClaude "Não deu certo: $($sync.Erro) Clique em Entrar com o Claude para tentar de novo." "erro" }
        else { Status $TxtClaude "✓  Claude conectado." "ok"; Concluir 2 "ok"; $BtnAvancar.IsEnabled = $true }
    }
})
$BtnCodigo.Add_Click({ $c = $TxtCodigo.Text.Trim(); if ($c) { $sync.ClaudeCodigo = $c; Status $TxtClaude "Conferindo o código..." "" } })

$BtnGoogle.Add_Click({
    if ($script:tarefa) { if ($sync.GoogleUrl) { Start-Process $sync.GoogleUrl }; return }
    $sync.Cancelar = $false; $sync.GoogleUrl = $null
    $BtnGoogle.Content = "Abrir o navegador de novo"
    Status $TxtGoogle "Aguardando você entrar no Google, no navegador..." ""
    Rodar $TarefaGoogle {
        $BtnGoogle.Content = "Entrar com o Google"
        if ($sync.Erro) { if ($sync.Erro -ne "Cancelado.") { Status $TxtGoogle "Não deu certo: $($sync.Erro) Tente de novo." "erro" } }
        else {
            Status $TxtGoogle $(if ($sync.GoogleEmail) { "✓  Google conectado: $($sync.GoogleEmail)" } else { "✓  Google conectado." }) "ok"
            Concluir 3 "ok"; $BtnAvancar.IsEnabled = $true; $BtnPular.Visibility = "Collapsed"; $BtnGoogle.Visibility = "Collapsed"
        }
    }
})

$BtnBotFather.Add_Click({ Start-Process "https://t.me/BotFather" })
$BtnAbrirBot.Add_Click({ if ($sync.TgBot) { Start-Process "https://t.me/$($sync.TgBot)" } })
function VerificarToken {
    if ($script:tarefa) { return }
    $t = ($TxtToken.Text -replace '\s', '')
    if ($t -notmatch '^\d{5,15}:[\w-]{30,}$') { Status $TxtTokenOk "Isso não parece um token. Ele tem números, dois-pontos e letras, assim: 123456789:AAH..." "erro"; return }
    $sync.TgToken = $t; $sync.TgBot = $null; $sync.Cancelar = $false
    Status $TxtTokenOk "Conferindo com o Telegram..." ""
    Rodar $TarefaVerificarBot {
        if ($sync.Erro) { Status $TxtTokenOk $sync.Erro "erro"; return }
        Status $TxtTokenOk "✓  Robô encontrado: @$($sync.TgBot)" "ok"
        $BtnAbrirBot.IsEnabled = $true; $BtnAbrirBot.Content = "Abrir @$($sync.TgBot)"
        Status $TxtTelegram "Esperando o seu oi no Telegram..." ""
        Rodar $TarefaTelegram {
            if ($sync.Erro) { if ($sync.Erro -ne "Cancelado.") { Status $TxtTelegram "Não deu certo: $($sync.Erro)" "erro" } }
            else {
                Status $TxtTelegram "✓  Recebi o seu oi, $($sync.TgNome)! A Pauta já respondeu por lá e fica ligada sempre que o computador estiver ligado." "ok"
                Concluir 4 "ok"; $BtnAvancar.IsEnabled = $true; $BtnPular.Visibility = "Collapsed"
            }
        }
    }
}
$BtnToken.Add_Click({ VerificarToken })

$BtnAbrir.Add_Click({
    if ($cfg.Demo) { $TxtFinal.Text = "[demo] abriria o Hermes Desktop."; return }
    if (Test-Path $cfg.AppExe) { Start-Process $cfg.AppExe }
    else {
        $hx = Join-Path $HermesHome "bin\hermes.exe"
        if (-not (Test-Path $hx)) { $hx = "hermes" }
        Start-Process powershell -ArgumentList "-NoExit", "-Command", "& '$hx' chat"
    }
})

# ---------- Relogio da janela: log, sub-etapas, codigo copiado e fim das tarefas ----------
$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(150)
$timer.Add_Tick({
    $m = $null
    while ($sync.Log.TryDequeue([ref]$m)) { $TxtLog.AppendText($m + "`r`n"); $TxtLog.ScrollToEnd() }
    while ($sync.Sub.TryDequeue([ref]$m)) { $p = $m -split '\|'; Marcar $subs[[int]$p[0]] $p[1] }

    if ($sync.ClaudeEsperando -and $script:pagina -eq 2) {
        if ($CaixaCodigo.Visibility -ne "Visible") { $CaixaCodigo.Visibility = "Visible"; Status $TxtClaude "Aguardando o código do Claude..." "" }
        try {
            if ([Windows.Clipboard]::ContainsText()) {
                $c = [Windows.Clipboard]::GetText().Trim()
                if ($c -match '^[\w-]{10,}#[\w-]{10,}$' -and $c -ne $script:ultimoCodigo) {
                    $script:ultimoCodigo = $c; $TxtCodigo.Text = $c; $sync.ClaudeCodigo = $c
                    Status $TxtClaude "Código recebido. Conferindo..." ""
                }
            }
        } catch {}
    }
    if ($script:pagina -eq 4 -and -not $sync.TgToken -and -not $script:tarefa) {
        try {
            if ([Windows.Clipboard]::ContainsText()) {
                $c = [regex]::Match([Windows.Clipboard]::GetText(), '\d{5,15}:[\w-]{30,}').Value
                if ($c -and $c -ne $script:ultimoToken) { $script:ultimoToken = $c; $TxtToken.Text = $c; VerificarToken }
            }
        } catch {}
    }

    if ($script:tarefa -and $script:tarefa.H.IsCompleted) {
        $t = $script:tarefa; $script:tarefa = $null
        try { [void]$t.PS.EndInvoke($t.H) } catch { $sync.Erro = $_.Exception.Message }
        $t.PS.Runspace.Close(); $t.PS.Dispose()
        & $t.Fim
    }
})

$win.Add_Closing({ $sync.Cancelar = $true; $timer.Stop() })
$win.Add_ContentRendered({
    # Aberto pelo Instalar-Pauta.cmd: esconde a janela preta do PowerShell.
    if ($env:UNICIVE_LAUNCHER) {
        try {
            Add-Type -Name Janela -Namespace Unicive -MemberDefinition '[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow(); [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);'
            [void][Unicive.Janela]::ShowWindow([Unicive.Janela]::GetConsoleWindow(), 0)
        } catch {}
    }
})

if ($cfg.Demo) { $win.Title += "  [demonstração]" }
IrPara 0
$timer.Start()
[void]$win.ShowDialog()

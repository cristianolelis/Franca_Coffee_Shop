# =====================================================================
#  Painel de Divulgação – Café Casa França
#  Servidor local: funciona só neste computador (localhost), sem internet
#  e sem nenhum custo. Guarda tudo na pasta "dados", ao lado desta.
#  Para usar, clique duas vezes em "Abrir Painel.bat".
# =====================================================================
$ErrorActionPreference = 'Stop'

$Painel = $PSScriptRoot
$Raiz   = Split-Path -Parent $Painel
$Dados  = Join-Path $Raiz 'dados'
$Fotos  = Join-Path $Dados 'fotos'
$Camps  = Join-Path $Dados 'campanhas'
$Cards  = Join-Path $Dados 'cardapios'
# Nada é apagado automaticamente: só o dono apaga, pelo painel ou pela pasta.

foreach ($d in $Dados, $Fotos, $Camps, $Cards) {
  if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d | Out-Null }
}

$Tipos = @{
  '.html' = 'text/html; charset=utf-8'; '.js' = 'application/javascript; charset=utf-8'
  '.css' = 'text/css; charset=utf-8'; '.json' = 'application/json; charset=utf-8'
  '.png' = 'image/png'; '.jpg' = 'image/jpeg'; '.jpeg' = 'image/jpeg'; '.webp' = 'image/webp'
  '.gif' = 'image/gif'; '.bmp' = 'image/bmp'; '.svg' = 'image/svg+xml'; '.woff2' = 'font/woff2'
  '.wasm' = 'application/wasm'; '.gz' = 'application/octet-stream'; '.txt' = 'text/plain; charset=utf-8'
  '.pdf' = 'application/pdf'; '.webmanifest' = 'application/manifest+json'
}
$Epoca = [DateTime]::new(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
function Ms([DateTime]$d) { [long]($d.ToUniversalTime() - $Epoca).TotalMilliseconds }

# Data de referência de um arquivo/pasta: quando chegou aqui ou foi usado por último
function Idade($item) { if ($item.CreationTime -gt $item.LastWriteTime) { $item.CreationTime } else { $item.LastWriteTime } }

# Nada é apagado de vez: tudo vai para a Lixeira do Windows (dá para recuperar)
# e fica anotado em painel\registro.log
Add-Type -AssemblyName Microsoft.VisualBasic
$Registro = Join-Path $Painel 'registro.log'
function Registrar([string]$msg) {
  try { Add-Content -LiteralPath $Registro -Value ('{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $msg) -Encoding UTF8 } catch { }
}
function Para-Lixeira([string]$caminho, [string]$motivo) {
  try {
    if (Test-Path -LiteralPath $caminho -PathType Container) {
      [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($caminho, 'OnlyErrorDialogs', 'SendToRecycleBin')
    } elseif (Test-Path -LiteralPath $caminho -PathType Leaf) {
      [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($caminho, 'OnlyErrorDialogs', 'SendToRecycleBin')
    } else { return }
    Registrar "$motivo -> Lixeira: $caminho"
  } catch { Registrar "ERRO ao apagar ($motivo): $caminho - $($_.Exception.Message)" }
}

# Só aceita nome de arquivo simples (sem pastas, sem "..")
function Nome-Seguro([string]$n) {
  if (-not $n) { return $null }
  if ($n -ne [IO.Path]::GetFileName($n)) { return $null }
  if ($n -match '[\\/:*?"<>|]' -or $n -eq '.' -or $n -eq '..') { return $null }
  return $n
}
# Garante que o caminho pedido fica dentro da pasta base
function Dentro([string]$base, [string]$rel) {
  $baseFull = [IO.Path]::GetFullPath($base).TrimEnd('\') + '\'
  $full = [IO.Path]::GetFullPath((Join-Path $base $rel))
  if ($full.StartsWith($baseFull, [StringComparison]::OrdinalIgnoreCase)) { return $full }
  return $null
}

function Responder($ctx, [int]$cod, [byte[]]$bytes, [string]$tipo) {
  $r = $ctx.Response
  $r.StatusCode = $cod
  $r.ContentType = $tipo
  $r.Headers.Add('Cache-Control', 'no-store')
  $r.ContentLength64 = $bytes.Length
  if ($bytes.Length) { $r.OutputStream.Write($bytes, 0, $bytes.Length) }
  $r.OutputStream.Close()
}
function Texto($ctx, [int]$cod, [string]$txt, [string]$tipo = 'application/json; charset=utf-8') {
  Responder $ctx $cod ([Text.Encoding]::UTF8.GetBytes($txt)) $tipo
}
function Esc([string]$s) { ($s -replace '\\', '\\' -replace '"', '\"') }
# A vírgula impede o PowerShell de transformar um arquivo vazio em "nada"
function Ler-Corpo($req) { $ms = New-Object IO.MemoryStream; $req.InputStream.CopyTo($ms); return , $ms.ToArray() }
function Arquivo($ctx, [string]$caminho) {
  if ($caminho -and (Test-Path -LiteralPath $caminho -PathType Leaf)) {
    $t = $Tipos[[IO.Path]::GetExtension($caminho).ToLower()]
    if (-not $t) { $t = 'application/octet-stream' }
    Responder $ctx 200 ([IO.File]::ReadAllBytes($caminho)) $t
  } else { Texto $ctx 404 'nao encontrado' 'text/plain; charset=utf-8' }
}

function Atender($ctx) {
  $req = $ctx.Request
  $met = $req.HttpMethod
  $rota = [Uri]::UnescapeDataString($req.Url.AbsolutePath)
  $q = $req.QueryString

  switch -Regex ($rota) {
    '^/api/status$' {
      Texto $ctx 200 '{"ok":true,"pastas":true}'; return
    }
    '^/api/fotos$' {
      if ($met -eq 'GET') {
        $itens = Get-ChildItem $Fotos -File | Where-Object { $Tipos[$_.Extension.ToLower()] -like 'image/*' } | ForEach-Object {
          '{"nome":"' + (Esc $_.Name) + '","url":"/dados/fotos/' + [Uri]::EscapeDataString($_.Name) + '","data":' + (Ms $_.CreationTime) + ',"usado":' + (Ms $_.LastWriteTime) + '}'
        }
        Texto $ctx 200 ('[' + ($itens -join ',') + ']'); return
      }
      $nome = Nome-Seguro $q['nome']
      if (-not $nome) { Texto $ctx 400 '{"erro":"nome"}'; return }
      $alvo = Join-Path $Fotos $nome
      if ($met -eq 'POST') { [IO.File]::WriteAllBytes($alvo, (Ler-Corpo $req)); Texto $ctx 200 '{"ok":true}'; return }
      if ($met -eq 'DELETE') { Para-Lixeira $alvo 'Foto apagada no painel'; Texto $ctx 200 '{"ok":true}'; return }
    }
    '^/api/fotos/usar$' {
      $nome = Nome-Seguro $q['nome']
      $alvo = if ($nome) { Join-Path $Fotos $nome }
      if ($alvo -and (Test-Path -LiteralPath $alvo)) { (Get-Item -LiteralPath $alvo).LastWriteTime = Get-Date }
      Texto $ctx 200 '{"ok":true}'; return
    }
    '^/api/campanhas$' {
      if ($met -eq 'GET') {
        $itens = Get-ChildItem $Camps -Directory | ForEach-Object {
          $j = Join-Path $_.FullName 'campanha.json'
          if (Test-Path -LiteralPath $j) {
            '{"pasta":"' + (Esc $_.Name) + '","dados":' + [IO.File]::ReadAllText($j, [Text.Encoding]::UTF8) + '}'
          }
        }
        Texto $ctx 200 ('[' + ($itens -join ',') + ']'); return
      }
      $pasta = Nome-Seguro $q['id']
      if (-not $pasta) { Texto $ctx 400 '{"erro":"id"}'; return }
      $dir = Join-Path $Camps $pasta
      if ($met -eq 'POST') {
        $arq = Nome-Seguro $q['arquivo']
        if (-not $arq) { Texto $ctx 400 '{"erro":"arquivo"}'; return }
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
        [IO.File]::WriteAllBytes((Join-Path $dir $arq), (Ler-Corpo $req))
        Texto $ctx 200 '{"ok":true}'; return
      }
      if ($met -eq 'DELETE') { Para-Lixeira $dir 'Campanha apagada no painel'; Texto $ctx 200 '{"ok":true}'; return }
    }
    '^/api/cardapios$' {
      $nome = Nome-Seguro $q['nome']
      if ($met -eq 'POST' -and $nome) { [IO.File]::WriteAllBytes((Join-Path $Cards $nome), (Ler-Corpo $req)); Texto $ctx 200 '{"ok":true}'; return }
      Texto $ctx 400 '{"erro":"nome"}'; return
    }
    '^/dados/' {
      Arquivo $ctx (Dentro $Dados ($rota.Substring(7) -replace '/', '\')); return
    }
    default {
      $rel = if ($rota -eq '/') { 'index.html' } else { $rota.TrimStart('/') -replace '/', '\' }
      Arquivo $ctx (Dentro $Painel $rel); return
    }
  }
  Texto $ctx 405 '{"erro":"metodo"}'
}

# Abre na primeira porta livre
$escuta = $null
foreach ($p in 8765..8785) {
  try {
    $l = New-Object System.Net.HttpListener
    $l.Prefixes.Add("http://localhost:$p/")
    $l.Start()
    $escuta = $l; $Porta = $p; break
  } catch { }
}
if (-not $escuta) {
  Write-Host 'Nao foi possivel abrir o painel. Feche outras janelas do painel e tente de novo.' -ForegroundColor Red
  Read-Host 'Aperte Enter para fechar'
  exit 1
}

$endereco = "http://localhost:$Porta/"
Write-Host ''
Write-Host '  Cafe Casa Franca - Painel de Divulgacao' -ForegroundColor Yellow
Write-Host "  Aberto em: $endereco"
Write-Host '  Fotos e campanhas ficam na pasta "dados".'
Write-Host ''
Write-Host '  >> Deixe esta janela aberta enquanto usa o painel.' -ForegroundColor Cyan
Write-Host '  >> Para encerrar, e so fechar esta janela.' -ForegroundColor Cyan
Write-Host ''
if (-not $env:PAINEL_SEM_NAVEGADOR) { Start-Process $endereco }

try {
  while ($escuta.IsListening) {
    $ctx = $escuta.GetContext()
    try { Atender $ctx }
    catch {
      try { Texto $ctx 500 ('{"erro":"' + (Esc $_.Exception.Message) + '"}') } catch { }
    }
  }
} finally { $escuta.Stop() }

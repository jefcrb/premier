$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

$ports = @(8000, 8001, 8080, 8888)
$listener = $null
$port = $null
foreach ($p in $ports) {
  $l = $null
  try {
    $l = New-Object System.Net.HttpListener
    $l.Prefixes.Add("http://localhost:$p/")
    $l.Prefixes.Add("http://127.0.0.1:$p/")
    $l.Start()
    $listener = $l
    $port = $p
    break
  } catch {
    if ($l) { try { $l.Close() } catch {} }
  }
}

if (-not $listener) {
  Write-Host ''
  Write-Host '  ERROR: Could not start the server.' -ForegroundColor Red
  Write-Host '  Ports 8000, 8001, 8080, 8888 are all in use.' -ForegroundColor Red
  Write-Host '  Close other apps that may be using these ports and try again.' -ForegroundColor Red
  Write-Host ''
  Read-Host 'Press Enter to close'
  exit 1
}

Clear-Host
Write-Host ''
Write-Host ''
Write-Host "  Server is running on port $port" -ForegroundColor Green
Write-Host ''
Write-Host '  Paste this URL into your OBS Browser Source:' -ForegroundColor White
Write-Host ''
Write-Host "    http://localhost:$port/startingsoon.html" -ForegroundColor Yellow
Write-Host ''
Write-Host '  Open the control panel in your browser to pick teams:' -ForegroundColor White
Write-Host ''
Write-Host "    http://localhost:$port/control.html" -ForegroundColor Yellow
Write-Host ''
Write-Host '  To stop the server: close this window' -ForegroundColor Gray
Write-Host ''
Write-Host '  ---------------------------------------------------' -ForegroundColor DarkGray
Write-Host ''

$mime = @{
  '.html'  = 'text/html; charset=utf-8'
  '.htm'   = 'text/html; charset=utf-8'
  '.css'   = 'text/css; charset=utf-8'
  '.js'    = 'application/javascript; charset=utf-8'
  '.json'  = 'application/json; charset=utf-8'
  '.png'   = 'image/png'
  '.jpg'   = 'image/jpeg'
  '.jpeg'  = 'image/jpeg'
  '.gif'   = 'image/gif'
  '.svg'   = 'image/svg+xml'
  '.webp'  = 'image/webp'
  '.ico'   = 'image/x-icon'
  '.ttf'   = 'font/ttf'
  '.otf'   = 'font/otf'
  '.woff'  = 'font/woff'
  '.woff2' = 'font/woff2'
  '.mp4'   = 'video/mp4'
  '.txt'   = 'text/plain; charset=utf-8'
}

$rootFull = [System.IO.Path]::GetFullPath($root)

$stateFile = Join-Path $root '.state.json'
$state = @{ team1 = ''; team2 = '' }
if (Test-Path -LiteralPath $stateFile) {
  try {
    $loaded = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
    if ($loaded.team1) { $state.team1 = [string]$loaded.team1 }
    if ($loaded.team2) { $state.team2 = [string]$loaded.team2 }
  } catch {}
}

function Save-State($s) {
  try {
    ($s | ConvertTo-Json) | Set-Content -LiteralPath $stateFile -Encoding utf8
  } catch {}
}

function Write-Json($res, $obj, [int]$status = 200) {
  $json = ConvertTo-Json -InputObject $obj -Compress -Depth 10
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
  $res.StatusCode = $status
  $res.ContentType = 'application/json; charset=utf-8'
  $res.ContentLength64 = $bytes.Length
  $res.Headers.Add('Cache-Control', 'no-store')
  $res.OutputStream.Write($bytes, 0, $bytes.Length)
}

try {
  while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $req = $ctx.Request
    $res = $ctx.Response
    try {
      $absPath = $req.Url.AbsolutePath

      if ($absPath -eq '/state') {
        if ($req.HttpMethod -eq 'GET') {
          Write-Json $res $state
        } elseif ($req.HttpMethod -eq 'POST') {
          $reader = New-Object System.IO.StreamReader($req.InputStream, $req.ContentEncoding)
          $body = $reader.ReadToEnd()
          $reader.Close()
          try {
            $parsed = $body | ConvertFrom-Json
            if ($null -ne $parsed.team1) { $state.team1 = [string]$parsed.team1 }
            if ($null -ne $parsed.team2) { $state.team2 = [string]$parsed.team2 }
            Save-State $state
            Write-Json $res $state
            Write-Host ("  SET  team1=$($state.team1)  team2=$($state.team2)") -ForegroundColor Cyan
          } catch {
            Write-Json $res @{ error = 'invalid json' } 400
          }
        } else {
          $res.StatusCode = 405
        }
        continue
      }

      if ($absPath -eq '/teams' -and $req.HttpMethod -eq 'GET') {
        $teamsDir = Join-Path $root 'Teams'
        $names = @()
        if (Test-Path -LiteralPath $teamsDir) {
          $files = Get-ChildItem -LiteralPath $teamsDir -Filter '*.json' -File
          foreach ($f in $files) {
            try {
              $obj = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json
              if ($obj.Name) { $names += [string]$obj.Name }
            } catch {}
          }
          $names = $names | Sort-Object
        }
        Write-Json $res $names
        continue
      }

      $rel = [Uri]::UnescapeDataString($absPath.TrimStart('/'))
      if ([string]::IsNullOrEmpty($rel) -or $rel.EndsWith('/')) {
        $rel = (Join-Path $rel 'startingsoon.html')
      }
      $rel = $rel -replace '/', '\'
      $path = Join-Path $root $rel
      $full = $null
      try { $full = [System.IO.Path]::GetFullPath($path) } catch {}

      if (-not $full -or -not $full.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        $res.StatusCode = 403
      } elseif (Test-Path -LiteralPath $full -PathType Leaf) {
        $bytes = [System.IO.File]::ReadAllBytes($full)
        $ext = [System.IO.Path]::GetExtension($full).ToLower()
        $type = if ($mime.ContainsKey($ext)) { $mime[$ext] } else { 'application/octet-stream' }
        $res.ContentType = $type
        $res.ContentLength64 = $bytes.Length
        $res.Headers.Add('Cache-Control', 'no-store, no-cache, must-revalidate')
        $res.OutputStream.Write($bytes, 0, $bytes.Length)
        Write-Host ("  {0,3}  {1}" -f 200, $rel) -ForegroundColor DarkGray
      } else {
        $res.StatusCode = 404
        $msg = [System.Text.Encoding]::UTF8.GetBytes("404 not found: $rel")
        $res.ContentLength64 = $msg.Length
        $res.OutputStream.Write($msg, 0, $msg.Length)
        Write-Host ("  {0,3}  {1}" -f 404, $rel) -ForegroundColor DarkYellow
      }
    } catch {
      try { $res.StatusCode = 500 } catch {}
    } finally {
      try { $res.OutputStream.Close() } catch {}
      try { $res.Close() } catch {}
    }
  }
} finally {
  try { $listener.Stop() } catch {}
  try { $listener.Close() } catch {}
}

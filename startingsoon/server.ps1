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
Write-Host "    http://localhost:$port/startingsoon.html?team1=GoLoko&team2=BEE" -ForegroundColor Yellow
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

try {
  while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $req = $ctx.Request
    $res = $ctx.Response
    try {
      $rel = [Uri]::UnescapeDataString($req.Url.AbsolutePath.TrimStart('/'))
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

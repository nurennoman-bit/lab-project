# FoodGo local server (Windows PowerShell - kisu install korte hoy na)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$mime = @{
  '.html'='text/html; charset=utf-8'; '.js'='text/javascript; charset=utf-8'; '.json'='application/json';
  '.svg'='image/svg+xml'; '.css'='text/css; charset=utf-8'; '.sql'='text/plain; charset=utf-8';
  '.png'='image/png'; '.ico'='image/x-icon'; '.txt'='text/plain; charset=utf-8'
}
$listener = $null; $port = 0
foreach ($p in 8080..8090) {
  try {
    $l = New-Object System.Net.HttpListener
    $l.Prefixes.Add("http://localhost:$p/")
    $l.Start()
    $listener = $l; $port = $p; break
  } catch { }
}
if (-not $listener) { exit 9 }
Write-Host ""
Write-Host "  FoodGo cholche:  http://localhost:$port"
Write-Host "  Browser nije khulbe. Bondho korte ei window ta close koro."
Write-Host ""
Start-Process "http://localhost:$port"
while ($listener.IsListening) {
  $ctx = $listener.GetContext()
  try {
    $path = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath)
    if ($path -eq '/') { $path = '/index.html' }
    $file = [IO.Path]::GetFullPath((Join-Path $root $path.TrimStart('/')))
    if ($file.StartsWith($root) -and (Test-Path -LiteralPath $file -PathType Leaf)) {
      $ct = $mime[[IO.Path]::GetExtension($file).ToLower()]
      if (-not $ct) { $ct = 'application/octet-stream' }
      $bytes = [IO.File]::ReadAllBytes($file)
      $ctx.Response.ContentType = $ct
      $ctx.Response.Headers.Add('Cache-Control', 'no-cache')
      $ctx.Response.ContentLength64 = $bytes.Length
      $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    } else {
      $ctx.Response.StatusCode = 404
    }
  } catch {
    try { $ctx.Response.StatusCode = 500 } catch { }
  } finally {
    try { $ctx.Response.Close() } catch { }
  }
}

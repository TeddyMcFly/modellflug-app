param(
  [int]$Port = 52733,
  [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$DartExe = "C:\Users\teddr\OneDrive\Dokumente\Flutter\flutter\bin\cache\dart-sdk\bin\dart.exe"
$PreviewUrl = "http://localhost:$Port/"
$StdOutLog = Join-Path $ProjectRoot "preview_server_stdout.log"
$StdErrLog = Join-Path $ProjectRoot "preview_server_stderr.log"

$PortOwner = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
  Select-Object -First 1 -ExpandProperty OwningProcess
if ($PortOwner) {
  Stop-Process -Id $PortOwner -Force
}

Get-Process dart, dartvm -ErrorAction SilentlyContinue |
  Where-Object {
    try {
      $_.Path -like '*\flutter\bin\cache\dart-sdk\bin\dart*'
    } catch {
      $false
    }
  } |
  Stop-Process -Force

Write-Host "Starte Vorschau auf $PreviewUrl"

Start-Process `
  -FilePath $DartExe `
  -ArgumentList @("tools\static_preview_server.dart", "--port", "$Port", "--root", "build\web") `
  -WorkingDirectory $ProjectRoot `
  -WindowStyle Hidden `
  -RedirectStandardOutput $StdOutLog `
  -RedirectStandardError $StdErrLog

Start-Sleep -Seconds 2

$PortOwner = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
  Select-Object -First 1 -ExpandProperty OwningProcess

if (-not $PortOwner) {
  Write-Host "Vorschau konnte nicht gestartet werden."
  if (Test-Path $StdErrLog) {
    Get-Content $StdErrLog
  }
  exit 1
}

Write-Host "Vorschau laeuft: $PreviewUrl"

if (-not $NoBrowser) {
  Start-Process $PreviewUrl
}

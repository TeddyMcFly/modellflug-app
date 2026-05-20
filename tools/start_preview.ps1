param(
  [int]$Port = 52733
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$DartExe = "C:\Users\teddr\OneDrive\Dokumente\Flutter\flutter\bin\cache\dart-sdk\bin\dart.exe"

Get-Process dart -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host "Starte Vorschau auf http://localhost:$Port"
Write-Host "Dieses Fenster offen lassen, solange die Vorschau laufen soll."

Set-Location $ProjectRoot
& $DartExe .\tools\static_preview_server.dart --port $Port --root .\build\web

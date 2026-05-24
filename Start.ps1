param(
  [int]$Port = 52800,
  [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSCommandPath
$HomepageRoot = Join-Path $ProjectRoot 'homepage'
$ServerScript = Join-Path $ProjectRoot 'tools\static_preview_server.dart'
$Url = "http://localhost:$Port/"
$StdOutLog = Join-Path $ProjectRoot "homepage_preview_$Port`_stdout.log"
$StdErrLog = Join-Path $ProjectRoot "homepage_preview_$Port`_stderr.log"

function Find-Dart {
  $command = Get-Command dart -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Source
  }

  $candidates = @(
    (Join-Path $env:USERPROFILE 'OneDrive\Dokumente\Flutter\flutter\bin\cache\dart-sdk\bin\dart.exe'),
    (Join-Path $env:USERPROFILE 'OneDrive\Dokumente\Flutter\flutter\bin\dart.bat'),
    (Join-Path $env:USERPROFILE 'Documents\Flutter\flutter\bin\cache\dart-sdk\bin\dart.exe'),
    (Join-Path $env:USERPROFILE 'Documents\Flutter\flutter\bin\dart.bat')
  )

  foreach ($candidate in $candidates) {
    if (Test-Path $candidate) {
      return $candidate
    }
  }

  return $null
}

function Test-Homepage {
  try {
    $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 2
    return ($response.StatusCode -eq 200 -and $response.Content.Contains('Modellflug-Heaven'))
  } catch {
    return $false
  }
}

if (-not (Test-Path $HomepageRoot)) {
  Write-Host "Der Ordner 'homepage' wurde nicht gefunden."
  exit 1
}

if (-not (Test-Path $ServerScript)) {
  Write-Host "Der kleine Vorschau-Server wurde nicht gefunden: $ServerScript"
  exit 1
}

if (Test-Homepage) {
  Write-Host "Homepage laeuft bereits:"
  Write-Host $Url
  if (-not $NoBrowser) {
    Start-Process $Url
  }
  exit 0
}

$portOwner = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
  Select-Object -First 1 -ExpandProperty OwningProcess

if ($portOwner) {
  Write-Host "Port $Port ist schon belegt. Bitte diesen Prozess pruefen: $portOwner"
  Write-Host "Adresse waere: $Url"
  exit 1
}

$DartExe = Find-Dart
if (-not $DartExe) {
  Write-Host "Dart wurde nicht gefunden. Bitte Flutter/Dart starten oder installieren."
  exit 1
}

Write-Host "Starte Homepage-Vorschau..."

Start-Process `
  -FilePath $DartExe `
  -ArgumentList @($ServerScript, "--port", "$Port", "--root", $HomepageRoot) `
  -WorkingDirectory $ProjectRoot `
  -WindowStyle Hidden `
  -RedirectStandardOutput $StdOutLog `
  -RedirectStandardError $StdErrLog

for ($i = 0; $i -lt 20; $i++) {
  Start-Sleep -Milliseconds 500
  if (Test-Homepage) {
    Write-Host "Homepage laeuft:"
    Write-Host $Url
    if (-not $NoBrowser) {
      Start-Process $Url
    }
    exit 0
  }
}

Write-Host "Homepage konnte nicht gestartet werden."
if (Test-Path $StdErrLog) {
  Get-Content $StdErrLog
}
exit 1

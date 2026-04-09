$ErrorActionPreference = 'Stop'
$utf8Encoding = [System.Text.UTF8Encoding]::new($false)
[Console]::InputEncoding = $utf8Encoding
[Console]::OutputEncoding = $utf8Encoding
$OutputEncoding = $utf8Encoding
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
$PSDefaultParameterValues['Set-Content:Encoding'] = 'utf8'
$PSDefaultParameterValues['Add-Content:Encoding'] = 'utf8'
& "$env:SystemRoot\System32\chcp.com" 65001 > $null

$repoRoot = Split-Path -Parent $PSScriptRoot
$flutter = Join-Path $repoRoot 'tools\flutter\bin\flutter.bat'
$frontend = Join-Path $repoRoot 'frontend'
$distRoot = Join-Path $repoRoot 'dist'
$portableRoot = Join-Path $distRoot 'AEMT-windows-portable'
$portableBin = Join-Path $portableRoot 'bin'
$zipPath = Join-Path $distRoot 'AEMT-windows-portable.zip'
$releaseRoot = Join-Path $frontend 'build\windows\x64\runner\Release'
$repoBin = Join-Path $repoRoot 'bin'
$repoFfmpeg = Join-Path $repoRoot 'ffmpeg'

function Resolve-ExecutablePath {
  param(
    [Parameter(Mandatory = $true)][string]$ExecutableName,
    [string]$EnvironmentVariable,
    [string[]]$SearchDirectories = @(),
    [string[]]$PathFallbacks = @()
  )

  if ($EnvironmentVariable) {
    $envDir = [Environment]::GetEnvironmentVariable($EnvironmentVariable)
    if ($envDir) {
      $candidate = Join-Path $envDir $ExecutableName
      if (Test-Path $candidate) {
        return $candidate
      }
    }
  }

  foreach ($dir in $SearchDirectories) {
    if (-not $dir) {
      continue
    }
    $candidate = Join-Path $dir $ExecutableName
    if (Test-Path $candidate) {
      return $candidate
    }
  }

  foreach ($fallback in ($PathFallbacks + @($ExecutableName))) {
    try {
      $command = Get-Command $fallback -ErrorAction Stop | Select-Object -First 1
      if ($command.Source) {
        return $command.Source
      }
    }
    catch {
    }
  }

  return $null
}

function Copy-ToolDirectory {
  param(
    [Parameter(Mandatory = $true)][string]$ExecutablePath,
    [Parameter(Mandatory = $true)][string]$Destination
  )

  $sourceDir = Split-Path -Parent $ExecutablePath
  Copy-Item (Join-Path $sourceDir '*') $Destination -Recurse -Force
}

function Copy-MatchingFiles {
  param(
    [Parameter(Mandatory = $true)][string]$SourceDirectory,
    [Parameter(Mandatory = $true)][string]$Destination,
    [Parameter(Mandatory = $true)][string[]]$Patterns
  )

  foreach ($pattern in $Patterns) {
    Get-ChildItem -Path $SourceDirectory -Filter $pattern -File -ErrorAction SilentlyContinue |
      ForEach-Object {
        Copy-Item $_.FullName $Destination -Force
      }
  }
}

if (-not (Test-Path $flutter)) {
  throw "Embedded Flutter SDK not found: $flutter"
}

$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'

Push-Location $frontend
try {
  & $flutter build windows
}
finally {
  Pop-Location
}

if (-not (Test-Path $releaseRoot)) {
  throw "Build output directory not found: $releaseRoot"
}

if (Test-Path $portableRoot) {
  Remove-Item $portableRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $portableRoot | Out-Null
New-Item -ItemType Directory -Path $portableBin | Out-Null

Copy-Item (Join-Path $releaseRoot '*') $portableRoot -Recurse -Force

if (Test-Path $repoBin) {
  Copy-MatchingFiles -SourceDirectory $repoBin -Destination $portableBin -Patterns @('*.exe', '*.dll')
}

if (Test-Path $repoFfmpeg) {
  Copy-MatchingFiles -SourceDirectory $repoFfmpeg -Destination $portableBin -Patterns @('ffmpeg.exe', 'ffprobe.exe', '*.dll')
}

$mkvpropeditPath = Resolve-ExecutablePath `
  -ExecutableName 'mkvpropedit.exe' `
  -EnvironmentVariable 'MKVTOOLNIX_BIN_DIR' `
  -SearchDirectories @(
    'C:\Program Files\MKVToolNix',
    'C:\Program Files (x86)\MKVToolNix'
  )
if ($mkvpropeditPath) {
  $mkvtoolnixDir = Split-Path -Parent $mkvpropeditPath
  Copy-MatchingFiles -SourceDirectory $mkvtoolnixDir -Destination $portableBin -Patterns @('mkvpropedit.exe', '*.dll')
}

$sevenZipPath = Resolve-ExecutablePath `
  -ExecutableName '7z.exe' `
  -SearchDirectories @(
    'C:\Program Files\7-Zip',
    'C:\Program Files (x86)\7-Zip'
  ) `
  -PathFallbacks @('7z.exe', '7za.exe', '7zz.exe')
if ($sevenZipPath) {
  $sevenZipDir = Split-Path -Parent $sevenZipPath
  Copy-MatchingFiles -SourceDirectory $sevenZipDir -Destination $portableBin -Patterns @('7z.exe', '7za.exe', '7zz.exe', '7z.dll')
}

$runScript = @'
$ErrorActionPreference = "Stop"
$utf8Encoding = [System.Text.UTF8Encoding]::new($false)
[Console]::InputEncoding = $utf8Encoding
[Console]::OutputEncoding = $utf8Encoding
$OutputEncoding = $utf8Encoding
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
$PSDefaultParameterValues['Set-Content:Encoding'] = 'utf8'
$PSDefaultParameterValues['Add-Content:Encoding'] = 'utf8'
& "$env:SystemRoot\System32\chcp.com" 65001 > $null
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $root
try {
  & (Join-Path $root "AEMT.exe")
}
finally {
  Pop-Location
}
'@
Set-Content -Path (Join-Path $portableRoot 'run_portable.ps1') -Value $runScript -Encoding UTF8

if (Test-Path $zipPath) {
  Remove-Item $zipPath -Force
}
Compress-Archive -Path (Join-Path $portableRoot '*') -DestinationPath $zipPath

Write-Host "Portable directory: $portableRoot"
Write-Host "Portable archive: $zipPath"

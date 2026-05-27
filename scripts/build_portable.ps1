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
$frontend = Join-Path $repoRoot 'frontend'
$distRoot = Join-Path $repoRoot 'dist'
$portableRoot = Join-Path $distRoot 'AEMT-windows-portable'
$portableBin = Join-Path $portableRoot 'bin'
$portablePython = Join-Path $portableRoot 'python'
$zipPath = Join-Path $distRoot 'AEMT-windows-portable.zip'
$releaseRoot = Join-Path $frontend 'build\windows\x64\runner\Release'
$repoBin = Join-Path $repoRoot 'bin'
$repoFfmpeg = Join-Path $repoRoot 'ffmpeg'
$toolsRoot = Join-Path $repoRoot 'tools'
$cacheRoot = Join-Path $toolsRoot 'cache'
$pythonEmbedVersion = '3.13.9'
$pythonEmbedUrl = "https://www.python.org/ftp/python/$pythonEmbedVersion/python-$pythonEmbedVersion-embed-amd64.zip"
$getPipUrl = 'https://bootstrap.pypa.io/get-pip.py'
$fontToolsVersion = '4.63.0'

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

function Invoke-DownloadFile {
  param(
    [Parameter(Mandatory = $true)][string]$Uri,
    [Parameter(Mandatory = $true)][string]$Destination
  )

  if (Test-Path $Destination) {
    return
  }

  New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
  Write-Host "Downloading $Uri"
  Invoke-WebRequest -Uri $Uri -OutFile $Destination -UseBasicParsing
}

function Enable-EmbeddedPythonSite {
  param(
    [Parameter(Mandatory = $true)][string]$PythonDirectory
  )

  $pthFile = Get-ChildItem -Path $PythonDirectory -Filter 'python*._pth' -File |
    Select-Object -First 1
  if (-not $pthFile) {
    throw "Embedded Python ._pth file not found in $PythonDirectory"
  }

  $lines = Get-Content -Path $pthFile.FullName
  $updated = $lines |
    ForEach-Object {
      if ($_ -eq '#import site') {
        'import site'
      }
      else {
        $_
      }
    }
  if ($updated -notcontains 'Lib\site-packages') {
    $updated += 'Lib\site-packages'
  }
  if ($updated -notcontains 'Scripts') {
    $updated += 'Scripts'
  }

  Set-Content -Path $pthFile.FullName -Value $updated -Encoding ASCII
}

function Install-FontToolsRuntime {
  param(
    [Parameter(Mandatory = $true)][string]$Destination,
    [Parameter(Mandatory = $true)][string]$BinDirectory,
    [Parameter(Mandatory = $true)][string]$DartPath
  )

  $pythonZip = Join-Path $cacheRoot "python-$pythonEmbedVersion-embed-amd64.zip"
  $getPip = Join-Path $cacheRoot 'get-pip.py'

  Invoke-DownloadFile -Uri $pythonEmbedUrl -Destination $pythonZip
  Invoke-DownloadFile -Uri $getPipUrl -Destination $getPip

  New-Item -ItemType Directory -Path $Destination -Force | Out-Null
  Expand-Archive -Path $pythonZip -DestinationPath $Destination -Force
  Enable-EmbeddedPythonSite -PythonDirectory $Destination

  $python = Join-Path $Destination 'python.exe'
  if (-not (Test-Path $python)) {
    throw "Embedded Python executable not found: $python"
  }

  & $python $getPip --no-warn-script-location --disable-pip-version-check
  if ($LASTEXITCODE -ne 0) {
    throw "get-pip failed with exit code $LASTEXITCODE"
  }

  & $python -m pip install `
    --disable-pip-version-check `
    --no-warn-script-location `
    --no-cache-dir `
    --upgrade `
    "fonttools[woff]==$fontToolsVersion"
  if ($LASTEXITCODE -ne 0) {
    throw "FontTools install failed with exit code $LASTEXITCODE"
  }

  $fontToolsLauncherSource = Join-Path $toolsRoot 'fonttools_launcher.dart'
  $fontToolsLauncherTemp = Join-Path $cacheRoot 'fonttools_launcher.exe'
  & $DartPath compile exe $fontToolsLauncherSource -o $fontToolsLauncherTemp
  if ($LASTEXITCODE -ne 0) {
    throw "FontTools launcher compile failed with exit code $LASTEXITCODE"
  }
  Copy-Item $fontToolsLauncherTemp (Join-Path $BinDirectory 'pyftsubset.exe') -Force
  Copy-Item $fontToolsLauncherTemp (Join-Path $BinDirectory 'ttx.exe') -Force

  & (Join-Path $BinDirectory 'ttx.exe') --version
  if ($LASTEXITCODE -ne 0) {
    throw "Bundled ttx validation failed with exit code $LASTEXITCODE"
  }
  & (Join-Path $BinDirectory 'pyftsubset.exe') --help > $null
  if ($LASTEXITCODE -ne 0) {
    throw "Bundled pyftsubset validation failed with exit code $LASTEXITCODE"
  }

  Write-Host "FontTools runtime bundled: fonttools $fontToolsVersion, Python $pythonEmbedVersion"
}

function Resolve-FlutterPath {
  $searchDirectories = @()
  foreach ($envName in @('FLUTTER_BIN_DIR', 'FLUTTER_ROOT', 'FLUTTER_HOME')) {
    $envValue = [Environment]::GetEnvironmentVariable($envName)
    if (-not $envValue) {
      continue
    }
    if ($envName -eq 'FLUTTER_BIN_DIR') {
      $searchDirectories += $envValue
    }
    else {
      $searchDirectories += (Join-Path $envValue 'bin')
    }
  }

  return Resolve-ExecutablePath `
    -ExecutableName 'flutter.bat' `
    -SearchDirectories $searchDirectories `
    -PathFallbacks @('flutter.bat', 'flutter')
}

function Resolve-DartPath {
  param(
    [Parameter(Mandatory = $true)][string]$FlutterPath
  )

  $searchDirectories = @(Split-Path -Parent $FlutterPath)
  foreach ($envName in @('FLUTTER_BIN_DIR', 'FLUTTER_ROOT', 'FLUTTER_HOME')) {
    $envValue = [Environment]::GetEnvironmentVariable($envName)
    if (-not $envValue) {
      continue
    }
    if ($envName -eq 'FLUTTER_BIN_DIR') {
      $searchDirectories += $envValue
    }
    else {
      $searchDirectories += (Join-Path $envValue 'bin')
    }
  }

  return Resolve-ExecutablePath `
    -ExecutableName 'dart.bat' `
    -SearchDirectories $searchDirectories `
    -PathFallbacks @('dart.bat', 'dart.exe', 'dart')
}

$flutter = Resolve-FlutterPath
if (-not $flutter) {
  throw 'Flutter executable not found. Set FLUTTER_BIN_DIR or FLUTTER_ROOT/FLUTTER_HOME, or add flutter to PATH.'
}

$dart = Resolve-DartPath -FlutterPath $flutter
if (-not $dart) {
  throw 'Dart executable not found. It should be available next to Flutter or on PATH.'
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

Install-FontToolsRuntime -Destination $portablePython -BinDirectory $portableBin -DartPath $dart

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

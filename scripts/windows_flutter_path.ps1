function ConvertTo-AemtNormalizedWindowsPath {
  param(
    [Parameter(Mandatory = $true)][string]$Path
  )

  return [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/').Replace('/', '\')
}

function Test-AemtAsciiPath {
  param(
    [Parameter(Mandatory = $true)][string]$Path
  )

  return -not [System.Text.RegularExpressions.Regex]::IsMatch($Path, '[^\x00-\x7F]')
}

function Test-AemtJunctionTarget {
  param(
    [Parameter(Mandatory = $true)][string]$JunctionPath,
    [Parameter(Mandatory = $true)][string]$ExpectedTarget
  )

  if (-not (Test-Path -LiteralPath $JunctionPath)) {
    return $false
  }

  $item = Get-Item -LiteralPath $JunctionPath -Force
  if ($item.LinkType -ne 'Junction') {
    return $false
  }

  $normalizedExpected = ConvertTo-AemtNormalizedWindowsPath $ExpectedTarget
  foreach ($target in @($item.Target)) {
    if ((ConvertTo-AemtNormalizedWindowsPath $target) -eq $normalizedExpected) {
      return $true
    }
  }

  return $false
}

function Get-AemtStablePathToken {
  param(
    [Parameter(Mandatory = $true)][string]$Path
  )

  $sha256 = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Path.ToLowerInvariant())
    $hash = $sha256.ComputeHash($bytes)
    return ([System.BitConverter]::ToString($hash)).Replace('-', '').Substring(0, 10).ToLowerInvariant()
  }
  finally {
    $sha256.Dispose()
  }
}

function Resolve-AemtAsciiRepoRoot {
  param(
    [Parameter(Mandatory = $true)][string]$RepoRoot
  )

  $resolvedRepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
  if (Test-AemtAsciiPath $resolvedRepoRoot) {
    return $resolvedRepoRoot
  }

  $volumeRoot = [System.IO.Path]::GetPathRoot($resolvedRepoRoot)
  $repoName = Split-Path -Leaf $resolvedRepoRoot
  $asciiRepoName = [System.Text.RegularExpressions.Regex]::Replace(
    $repoName,
    '[^A-Za-z0-9._-]',
    '-'
  ).Trim('-')
  if (-not $asciiRepoName) {
    $asciiRepoName = 'aemt'
  }

  $token = Get-AemtStablePathToken $resolvedRepoRoot
  $candidates = @((Join-Path $volumeRoot $asciiRepoName))
  if ($env:PUBLIC -and (Test-AemtAsciiPath $env:PUBLIC)) {
    $candidates += Join-Path $env:PUBLIC "AEMT-build-links\aemt-$token"
  }
  $candidates += Join-Path $volumeRoot "aemt-build-$token"

  foreach ($candidate in $candidates) {
    if (Test-AemtJunctionTarget -JunctionPath $candidate -ExpectedTarget $resolvedRepoRoot) {
      Write-Host "Using ASCII build path: $candidate"
      return $candidate
    }
  }

  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate) {
      continue
    }

    try {
      $candidateParent = Split-Path -Parent $candidate
      if (-not (Test-Path -LiteralPath $candidateParent)) {
        New-Item -ItemType Directory -Path $candidateParent -Force -ErrorAction Stop | Out-Null
      }
      New-Item -ItemType Junction -Path $candidate -Target $resolvedRepoRoot -ErrorAction Stop | Out-Null
      Write-Host "Created ASCII build path: $candidate -> $resolvedRepoRoot"
      return $candidate
    }
    catch {
      Write-Verbose "Unable to create junction $candidate`: $($_.Exception.Message)"
    }
  }

  throw "The repository path contains non-ASCII characters and no ASCII junction could be created for it: $resolvedRepoRoot"
}

function Initialize-AemtFlutterWindowsBuildCache {
  param(
    [Parameter(Mandatory = $true)][string]$BuildRepoRoot
  )

  $frontend = Join-Path $BuildRepoRoot 'frontend'
  $windowsBuildParent = Join-Path $frontend 'build\windows'
  $windowsBuildRoot = Join-Path $windowsBuildParent 'x64'
  $cachePath = Join-Path $windowsBuildRoot 'CMakeCache.txt'
  if (-not (Test-Path -LiteralPath $cachePath)) {
    return
  }

  $homeEntry = Select-String `
    -LiteralPath $cachePath `
    -Pattern '^CMAKE_HOME_DIRECTORY:INTERNAL=(.+)$' |
    Select-Object -First 1
  if (-not $homeEntry) {
    return
  }

  $cachedSource = $homeEntry.Matches[0].Groups[1].Value
  $expectedSource = Join-Path $frontend 'windows'
  if ((ConvertTo-AemtNormalizedWindowsPath $cachedSource) -eq
      (ConvertTo-AemtNormalizedWindowsPath $expectedSource)) {
    return
  }

  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $backupRoot = "$windowsBuildRoot.stale-$stamp"
  $suffix = 1
  while (Test-Path -LiteralPath $backupRoot) {
    $backupRoot = "$windowsBuildRoot.stale-$stamp-$suffix"
    $suffix++
  }

  Move-Item -LiteralPath $windowsBuildRoot -Destination $backupRoot
  New-Item -ItemType Directory -Path $windowsBuildRoot -Force | Out-Null

  Get-ChildItem -LiteralPath $backupRoot -Filter '*.7z' -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Length -gt 0 } |
    ForEach-Object {
      Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $windowsBuildRoot $_.Name)
    }

  Write-Host "Preserved incompatible CMake build cache: $backupRoot"
}

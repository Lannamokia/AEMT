$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'windows_flutter_path.ps1')
$buildRepoRoot = Resolve-AemtAsciiRepoRoot -RepoRoot $repoRoot
Initialize-AemtFlutterWindowsBuildCache -BuildRepoRoot $buildRepoRoot
$frontend = Join-Path $buildRepoRoot 'frontend'

$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'

Push-Location $frontend
try {
  & flutter run -d windows
  if ($LASTEXITCODE -ne 0) {
    throw "Flutter Windows development run failed with exit code $LASTEXITCODE"
  }
}
finally {
  Pop-Location
}

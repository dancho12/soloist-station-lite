$ErrorActionPreference = 'Stop'
$required = @(
    'bin/soloist', 'bin/soloist.official.sha256',
    'lib64/ld-linux-aarch64.so.1', 'lib64/libpulse.so.0',
    'scripts/S99spotify-connect', 'scripts/stop.sh', 'scripts/status.sh',
    'install.sh', 'uninstall.sh'
)
foreach ($relativePath in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $relativePath))) {
        throw "Missing package input: $relativePath"
    }
}

$soloistPath = Join-Path $PSScriptRoot 'bin/soloist'
$actual = (Get-FileHash -LiteralPath $soloistPath -Algorithm SHA256).Hash.ToLowerInvariant()
$expected = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'bin/soloist.official.sha256') -Raw).Trim()
if ($actual -ne $expected) { throw 'Official Soloist hash mismatch.' }

$stagingParent = Join-Path $PSScriptRoot '.package-staging'
$staging = Join-Path $stagingParent 'soloist-station-lite'
$outputDir = Join-Path $PSScriptRoot 'dist'
New-Item -ItemType Directory -Path $staging, $outputDir -Force | Out-Null
try {
    $stagedBin = Join-Path $staging 'bin'
    New-Item -ItemType Directory -Path $stagedBin -Force | Out-Null
    foreach ($name in @('soloist', 'soloist.official.sha256')) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot "bin/$name") -Destination $stagedBin -Force
    }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'lib64') -Destination $staging -Recurse -Force
    $stagedScripts = Join-Path $staging 'scripts'
    New-Item -ItemType Directory -Path $stagedScripts -Force | Out-Null
    foreach ($name in @('S99spotify-connect', 'stop.sh', 'status.sh')) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot "scripts/$name") -Destination $stagedScripts -Force
    }
    foreach ($name in @('install.sh', 'uninstall.sh', 'PREP-MINI2-MINI3.md')) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $staging -Force
    }
    # Never package developer credentials, accounts, caches, or Spotify session data.
    $outputPath = Join-Path $outputDir 'soloist-station-lite-prepared.tar.gz'
    tar -czf $outputPath -C $stagingParent soloist-station-lite
    if ($LASTEXITCODE -ne 0) { throw 'Packaging failed.' }
    Write-Output "Prepared device archive: $outputPath"
    Write-Output "SHA256: $((Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash.ToLowerInvariant())"
} finally {
    Remove-Item -LiteralPath $stagingParent -Recurse -Force -ErrorAction SilentlyContinue
}

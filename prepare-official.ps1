param(
    [string]$ArchivePath
)

$ErrorActionPreference = 'Stop'
$officialUrl = 'https://soloist-builds.spotifycdn.com/soloist_release_arm64.tar.gz'
$binaryDir = Join-Path $PSScriptRoot 'bin'
$stagingDir = Join-Path $PSScriptRoot '.soloist-staging'
$downloadPath = Join-Path $stagingDir 'soloist_release_arm64.tar.gz'

New-Item -ItemType Directory -Path $binaryDir, $stagingDir -Force | Out-Null
try {
    if ($ArchivePath) {
        $sourceArchive = (Resolve-Path -LiteralPath $ArchivePath).Path
    } else {
        Invoke-WebRequest -Uri $officialUrl -OutFile $downloadPath
        $sourceArchive = $downloadPath
    }

    $entries = @(tar -tzf $sourceArchive)
    if ($LASTEXITCODE -ne 0 -or 'soloist' -notin $entries) {
        throw 'The official archive does not contain a top-level soloist binary.'
    }
    tar -xf $sourceArchive -C $stagingDir soloist
    if ($LASTEXITCODE -ne 0) { throw 'Could not extract soloist.' }

    $stagedBinary = Join-Path $stagingDir 'soloist'
    $destination = Join-Path $binaryDir 'soloist'
    Copy-Item -LiteralPath $stagedBinary -Destination $destination -Force
    $hash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
    Set-Content -LiteralPath (Join-Path $binaryDir 'soloist.official.sha256') -Value $hash -NoNewline -Encoding ascii
    Write-Output "Staged official Spotify Soloist ARM64 binary. SHA256: $hash"
    Write-Output 'Refresh it immediately before installing: Spotify Soloist builds expire after 90 days.'
} finally {
    Remove-Item -LiteralPath $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
}

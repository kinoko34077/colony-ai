param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
$configPath = Join-Path $Root "generated-integrity.json"
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    Write-Error "generated-integrity.json is missing"
    exit 1
}
$config = Get-Content -Raw -Encoding UTF8 $configPath | ConvertFrom-Json
if ([int]$config.schema_version -ne 1 -or [string]$config.algorithm -ne "SHA-256") {
    Write-Error "Unsupported generated-integrity configuration"
    exit 1
}

$failed = $false
foreach ($entry in @($config.entries)) {
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd([char[]]@("/", "\"))
    $rootPrefix = $rootPath + [IO.Path]::DirectorySeparatorChar
    $sourceRelative = [string]$entry.source
    $artifactRelative = [string]$entry.artifact
    if ([IO.Path]::IsPathRooted($sourceRelative) -or [IO.Path]::IsPathRooted($artifactRelative)) {
        Write-Error "Generated paths must be relative to the Project root"
        $failed = $true
        continue
    }
    $source = [IO.Path]::GetFullPath((Join-Path $rootPath $sourceRelative))
    $artifact = [IO.Path]::GetFullPath((Join-Path $rootPath $artifactRelative))
    if (-not $source.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Error "Generated source path is outside the Project root: $sourceRelative"
        $failed = $true
        continue
    }
    if (-not $artifact.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Error "Generated artifact path is outside the Project root: $artifactRelative"
        $failed = $true
        continue
    }
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        Write-Error "Generated source is missing: $($entry.source)"
        $failed = $true
        continue
    }
    if (-not (Test-Path -LiteralPath $artifact -PathType Leaf)) {
        Write-Error "Generated artifact is missing: $($entry.artifact)"
        $failed = $true
        continue
    }
    if ([string]$entry.source_sha256 -notmatch '^[0-9a-fA-F]{64}$') {
        Write-Error "Generated source hash is missing or invalid: $($entry.source)"
        $failed = $true
        continue
    }
    if ([string]$entry.sha256 -notmatch '^[0-9a-fA-F]{64}$') {
        Write-Error "Generated artifact hash is missing or invalid: $($entry.artifact)"
        $failed = $true
        continue
    }
    $sourceActual = (Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash.ToLowerInvariant()
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $artifact).Hash.ToLowerInvariant()
    if ($sourceActual -ne ([string]$entry.source_sha256).ToLowerInvariant()) {
        Write-Error "Generated source is stale: $($entry.source)"
        $failed = $true
    }
    if ($actual -ne ([string]$entry.sha256).ToLowerInvariant()) {
        Write-Error "Generated artifact is stale: $($entry.artifact)"
        $failed = $true
    }
}

if ($failed) { exit 1 }
Write-Output "Generated integrity: OK ($(@($config.entries).Count) artifact(s))"
exit 0

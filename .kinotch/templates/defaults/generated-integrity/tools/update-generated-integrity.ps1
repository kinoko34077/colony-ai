param(
    [Parameter(Mandatory=$true)][string]$Artifact,
    [Parameter(Mandatory=$true)][string]$Source,
    [Parameter(Mandatory=$true)][string]$Generator,
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
$configPath = Join-Path $Root "generated-integrity.json"
if ([IO.Path]::IsPathRooted($Artifact) -or [IO.Path]::IsPathRooted($Source)) {
    throw "Generated source and artifact paths must be relative to the Project root"
}
$rootPath = [IO.Path]::GetFullPath($Root).TrimEnd([char[]]@("/", "\"))
$rootPrefix = $rootPath + [IO.Path]::DirectorySeparatorChar
$artifactPath = [IO.Path]::GetFullPath((Join-Path $rootPath $Artifact))
$sourcePath = [IO.Path]::GetFullPath((Join-Path $rootPath $Source))
if (-not $artifactPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Generated artifact path is outside the Project root: $Artifact"
}
if (-not $sourcePath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Generated source path is outside the Project root: $Source"
}
if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) { throw "Generated artifact not found: $Artifact" }
if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw "Generated source not found: $Source" }
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { throw "generated-integrity.json is missing" }
$config = Get-Content -Raw -Encoding UTF8 $configPath | ConvertFrom-Json
$sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash.ToLowerInvariant()
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $artifactPath).Hash.ToLowerInvariant()
$entry = [pscustomobject]@{
    source = $Source
    source_sha256 = $sourceHash
    artifact = $Artifact
    sha256 = $hash
    generator = $Generator
}
$existing = @($config.entries | Where-Object { [string]$_.artifact -ne $Artifact })
$config.entries = @($existing + $entry)
[IO.File]::WriteAllText($configPath, (ConvertTo-Json $config -Depth 10) + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
Write-Output "Updated generated-integrity entry: $Artifact"

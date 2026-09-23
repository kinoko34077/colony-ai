param(
    [Parameter(Mandatory=$true)][ValidateSet("open", "save", "save_as")][string]$Action,
    [Parameter(Mandatory=$true)][string]$Path,
    [string]$Content,
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
if ([IO.Path]::IsPathRooted($Path)) {
    Write-Error "File path must be relative to the Project root"
    exit 1
}
$rootPath = [IO.Path]::GetFullPath($Root).TrimEnd([char[]]@("/", "\"))
$rootPrefix = $rootPath + [IO.Path]::DirectorySeparatorChar
$resolved = [IO.Path]::GetFullPath((Join-Path $rootPath $Path))
if (-not $resolved.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    Write-Error "File path is outside the Project root"
    exit 1
}

if ($Action -eq "open") {
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { Write-Error "File not found: $Path"; exit 1 }
    Get-Content -Raw -Encoding UTF8 -LiteralPath $resolved
    exit 0
}

$parent = Split-Path -Parent $resolved
New-Item -ItemType Directory -Path $parent -Force | Out-Null
[IO.File]::WriteAllText($resolved, [string]$Content, (New-Object System.Text.UTF8Encoding($false)))
Write-Output "File $Action: $Path"
exit 0

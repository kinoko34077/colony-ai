param(
    [Alias('Root')][string]$BaseRoot
)

function ConvertTo-BaseRelativePath {
    param(
        [Parameter(Mandatory=$true)][string]$Root,
        [Parameter(Mandatory=$true)][string]$AbsolutePath
    )

    $rootValue = ([string]$Root).Replace('\', '/')
    $pathValue = ([string]$AbsolutePath).Replace('\', '/')
    while ($rootValue.Length -gt 1 -and $rootValue.EndsWith('/')) {
        $rootValue = $rootValue.Substring(0, $rootValue.Length - 1)
    }

    if ($rootValue -eq '/') {
        return $pathValue.TrimStart('/')
    }
    if ($pathValue -eq $rootValue) {
        return ''
    }

    $prefix = $rootValue + '/'
    if (-not $pathValue.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside repository root: $AbsolutePath"
    }
    return $pathValue.Substring($prefix.Length).TrimStart('/')
}

function Get-BaseFileHash {
    param([Parameter(Mandatory=$true)][string]$Path)

    $content = [IO.File]::ReadAllText($Path)
    $canonical = $content.Replace("`r`n", "`n").Replace("`r", "`n")
    $encoding = New-Object System.Text.UTF8Encoding($false)
    $bytes = $encoding.GetBytes($canonical)
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        return (($sha256.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join "")
    }
    finally {
        $sha256.Dispose()
    }
}

function Get-BaseProtectedPaths {
    param([Parameter(Mandatory=$true)][string]$Root)

    $fixed = @(
        ".editorconfig",
        ".gitattributes",
        ".gitignore",
        ".github/workflows/verify.yml",
        "AGENTS.md",
        "knt.cmd"
    )
    $common = @(Get-ChildItem -LiteralPath (Join-Path $Root ".kinotch") -Recurse -File -Force | ForEach-Object {
        $relative = ConvertTo-BaseRelativePath -Root $Root -AbsolutePath $_.FullName
        if ($relative -ne ".kinotch/base-files.json") { $relative }
    })

    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($path in @($fixed + $common)) {
        if (-not $paths.Contains($path)) { [void]$paths.Add($path) }
    }
    $paths.Sort([System.StringComparer]::Ordinal)
    return $paths.ToArray()
}

function Update-BaseIndex {
    param([Parameter(Mandatory=$true)][string]$Root)

    $manifestPath = Join-Path $Root "project/project.json"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "project/project.json not found: $manifestPath"
    }
    $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $manifestPath | ConvertFrom-Json
    if ($manifest.project.type -ne "repository-base") {
        throw "base-refresh is only available for project.type repository-base"
    }

    $protectedPaths = @(Get-BaseProtectedPaths -Root $Root)
    $inventoryPath = Join-Path $Root ".kinotch/FILE_INVENTORY.txt"
    [IO.File]::WriteAllText($inventoryPath, ($protectedPaths -join [Environment]::NewLine) + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))

    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($relative in $protectedPaths) {
        $path = Join-Path $Root $relative
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Base protected file not found: $relative"
        }
        [void]$entries.Add([pscustomobject]@{
            path = $relative
            sha256 = Get-BaseFileHash -Path $path
        })
    }

    $version = (Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $Root ".kinotch/BASE_VERSION")).Trim()
    $index = [pscustomobject]@{
        schema_version = 1
        base_version = $version
        files = $entries.ToArray()
    }
    $json = ConvertTo-Json $index -Depth 10
    [IO.File]::WriteAllText((Join-Path $Root ".kinotch/base-files.json"), $json + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
}

if (-not [string]::IsNullOrWhiteSpace($BaseRoot)) {
    Update-BaseIndex -Root $BaseRoot
}

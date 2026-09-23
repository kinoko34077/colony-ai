param(
    [string]$RootOverride,
    [string]$BaseOverride,

    [Parameter(Position=0)]
    [string]$Command = "help",

    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$RemainingArgs
)

$ErrorActionPreference = "Stop"

if ($RootOverride) {
    $Root = (Resolve-Path -LiteralPath $RootOverride).Path
    if ($BaseOverride) {
        $BaseDir = (Resolve-Path -LiteralPath $BaseOverride).Path
    }
    else {
        $BaseDir = Join-Path $Root ".kinotch"
    }
}
else {
    $BaseDir = Split-Path -Parent $PSScriptRoot
    $Root = Split-Path -Parent $BaseDir
}

$ManifestPath = Join-Path $Root "project/project.json"
$BaseFilesPath = Join-Path $BaseDir "base-files.json"
$ValidationPath = Join-Path $BaseDir "scripts/knt-validation.ps1"
$BaseIndexScriptPath = Join-Path $BaseDir "scripts/update-base-index.ps1"

if (-not (Test-Path -LiteralPath $ValidationPath -PathType Leaf)) {
    throw "Validation script not found: $ValidationPath"
}
. $ValidationPath
if (-not (Test-Path -LiteralPath $BaseIndexScriptPath -PathType Leaf)) {
    throw "Base index script not found: $BaseIndexScriptPath"
}
. $BaseIndexScriptPath

function Write-Knt([string]$Message) {
    Write-Host "[knt] $Message"
}

function Assert-RepositoryWriteAllowed([string]$Operation) {
    if (-not [string]::IsNullOrWhiteSpace($BaseOverride)) {
        throw "$Operation requires repository-local .kinotch; -BaseOverride is read-only"
    }

    $localBaseDir = Join-Path $Root ".kinotch"
    if (-not (Test-Path -LiteralPath $localBaseDir -PathType Container)) {
        throw "$Operation requires a valid repository-local .kinotch/ Base"
    }
    foreach ($requiredFile in @("BASE_VERSION", "base-files.json", "scripts/knt.ps1")) {
        if (-not (Test-Path -LiteralPath (Join-Path $localBaseDir $requiredFile) -PathType Leaf)) {
            throw "$Operation requires a valid repository-local .kinotch/ Base"
        }
    }

    $localResolved = (Resolve-Path -LiteralPath $localBaseDir).Path
    $activeResolved = (Resolve-Path -LiteralPath $BaseDir).Path
    if (-not [string]::Equals($localResolved, $activeResolved, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Operation requires the repository-local .kinotch/ Base"
    }
}

function Get-Manifest {
    return Get-KntJson -Path $ManifestPath
}

function Test-DefaultCatalogSemantics($Catalog) {
    $errors = New-Object System.Collections.Generic.List[string]
    $ids = @{}
    $aliases = @{}
    foreach ($entry in @($Catalog.defaults)) {
        $id = [string]$entry.id
        if ($ids.ContainsKey($id)) {
            [void]$errors.Add("duplicate Default id '$id'")
        }
        else {
            $ids[$id] = $true
        }
        foreach ($aliasValue in @($entry.aliases)) {
            $alias = [string]$aliasValue
            if ($aliases.ContainsKey($alias)) {
                [void]$errors.Add("duplicate Default alias '$alias'")
            }
            else {
                $aliases[$alias] = $true
            }
        }
        if ([string]$entry.kind -eq "surface") {
            $profileName = Get-DefaultProfileName $entry
            $profilePath = Join-Path $BaseDir ("profiles/" + $profileName + ".json")
            if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) {
                [void]$errors.Add("Surface Default '$id' references missing profile '$profileName'")
            }
        }
    }
    foreach ($id in @($ids.Keys)) {
        if ($aliases.ContainsKey([string]$id)) {
            [void]$errors.Add("Default id/alias collision '$id'")
        }
    }
    return @($errors | Select-Object -Unique)
}

function Get-ProjectDefaultState($Manifest, [string]$DefaultId) {
    if (-not $Manifest) { return $null }
    $relative = Get-ManifestPathValue $Manifest "defaults" "defaults.json"
    $path = Join-Path (Join-Path $Root "project") $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    $defaults = Get-KntJson -Path $path
    $property = $defaults.packs.PSObject.Properties[$DefaultId]
    if (-not $property) {
        $catalog = Get-DefaultCatalog
        $entry = Find-AnyDefaultCatalogEntry -Catalog $catalog -Identifier $DefaultId
        $property = $defaults.packs.PSObject.Properties[[string]$entry.id]
    }
    if ($property) { return [string](Get-KntJsonProperty $property.Value "state") }
    return $null
}

function Test-ProjectDefaultEnabled($Manifest, [string]$DefaultId) {
    return ((Get-ProjectDefaultState -Manifest $Manifest -DefaultId $DefaultId) -eq "DEFAULT")
}

function Get-DefaultCatalog {
    $catalogPath = Join-Path $BaseDir "defaults/catalog.json"
    $schemaPath = Join-Path $BaseDir "schemas/default-catalog.schema.json"
    if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) {
        throw "Default catalog not found: $catalogPath"
    }
    if (-not (Test-Path -LiteralPath $schemaPath -PathType Leaf)) {
        throw "Default catalog schema not found: $schemaPath"
    }
    $catalog = Get-KntJson -Path $catalogPath
    $schema = Get-KntJson -Path $schemaPath
    $errors = @(Test-KntSchema -Data $catalog -Schema $schema -Path ".kinotch/defaults/catalog.json")
    if ($errors.Count -gt 0) {
        throw "Default catalog validation failed: " + ($errors -join "; ")
    }
    $semanticErrors = @(Test-DefaultCatalogSemantics -Catalog $catalog)
    if ($semanticErrors.Count -gt 0) {
        throw "Default catalog semantic validation failed: " + ($semanticErrors -join "; ")
    }
    return $catalog
}

function Get-DefaultCompatibilityError($Entry, [string[]]$SelectedSurfaces) {
    $compatible = @($Entry.compatible_surfaces)
    if ([string]$Entry.kind -ne "tool" -or $compatible.Count -eq 0) { return $null }
    $overlap = @($SelectedSurfaces | Where-Object { $_ -in $compatible })
    if ($overlap.Count -eq 0) {
        return "Default '$($Entry.id)' is not compatible with the selected Surface profile(s)"
    }
    return $null
}

function Find-DefaultCatalogEntry($Catalog, [string]$Identifier, [string]$Kind) {
    $matches = @($Catalog.defaults | Where-Object {
        ([string]$_.id -eq $Identifier) -or (@($_.aliases) -contains $Identifier)
    })
    if ($matches.Count -eq 0) {
        throw "Unknown $Kind Default '$Identifier' in Default catalog"
    }
    $entry = $matches[0]
    if ([string]$entry.kind -ne $Kind) {
        throw "Default '$Identifier' is kind '$($entry.kind)' and cannot be used as a $Kind Default"
    }
    return $entry
}

function Find-AnyDefaultCatalogEntry($Catalog, [string]$Identifier) {
    $matches = @($Catalog.defaults | Where-Object {
        ([string]$_.id -eq $Identifier) -or (@($_.aliases) -contains $Identifier)
    })
    if ($matches.Count -eq 0) {
        throw "Unknown Default Pack '$Identifier' in Default catalog"
    }
    return $matches[0]
}

function Get-DefaultProfileName($Entry) {
    if ($Entry.PSObject.Properties["profile"] -and -not [string]::IsNullOrWhiteSpace([string]$Entry.profile)) {
        return [string]$Entry.profile
    }
    return [string]$Entry.id
}

function Get-DefaultOptions([string]$CommandName) {
    $profiles = New-Object System.Collections.Generic.List[string]
    $defaults = New-Object System.Collections.Generic.List[string]
    $apply = $false
    $values = @($RemainingArgs)
    for ($index = 0; $index -lt $values.Count; $index++) {
        $value = [string]$values[$index]
        if ([string]::IsNullOrWhiteSpace($value)) { continue }
        if ($value -eq "--apply") {
            if ($CommandName -ne "migrate") { throw "Unknown $CommandName option: $value" }
            $apply = $true
            continue
        }
        if ($value -eq "--profile" -or $value -eq "--default") {
            if ($index + 1 -ge $values.Count -or [string]::IsNullOrWhiteSpace([string]$values[$index + 1])) {
                throw "$CommandName requires a value after $value"
            }
            $optionName = $value
            $value = [string]$values[++$index]
        }
        elseif ($value -like "--profile=*") {
            $optionName = "--profile"
            $value = $value.Substring("--profile=".Length)
        }
        elseif ($value -like "--default=*") {
            $optionName = "--default"
            $value = $value.Substring("--default=".Length)
        }
        else {
            throw "Unknown $CommandName option: $value"
        }

        if ($optionName -eq "--profile") {
            if ($value -notin $profiles) { [void]$profiles.Add($value) }
        }
        else {
            if ($value -notin $defaults) { [void]$defaults.Add($value) }
        }
    }
    return [pscustomobject]@{ profiles = @($profiles); defaults = @($defaults); apply = $apply }
}

function Resolve-DefaultSelections($Options, $Catalog, [bool]$RequireProfile, [string[]]$ExistingSurfaces = @()) {
    $profileEntries = @()
    foreach ($profileName in @($Options.profiles)) {
        $profileEntries += Find-DefaultCatalogEntry -Catalog $Catalog -Identifier ([string]$profileName) -Kind "surface"
    }
    if ($RequireProfile -and $profileEntries.Count -eq 0) {
        throw "init requires at least one --profile"
    }

    $toolEntries = @()
    foreach ($defaultName in @($Options.defaults)) {
        $toolEntries += Find-DefaultCatalogEntry -Catalog $Catalog -Identifier ([string]$defaultName) -Kind "tool"
    }
    $selectedSurfaces = @($profileEntries | ForEach-Object { @($_.compatible_surfaces) } | Select-Object -Unique)
    if ($ExistingSurfaces.Count -gt 0) {
        $selectedSurfaces = @($selectedSurfaces + @($ExistingSurfaces) | Select-Object -Unique)
    }
    foreach ($tool in $toolEntries) {
        $compatibilityError = Get-DefaultCompatibilityError -Entry $tool -SelectedSurfaces $selectedSurfaces
        if ($compatibilityError) { throw $compatibilityError }
    }
    return [pscustomobject]@{ profileEntries = @($profileEntries); toolEntries = @($toolEntries); options = $Options }
}

function Get-SelectedInitProfiles {
    $catalog = Get-DefaultCatalog
    $selection = Resolve-DefaultSelections -Options (Get-DefaultOptions "init") -Catalog $catalog -RequireProfile $true
    return $selection
}

function Get-DefaultStateEntry($State) {
    return [pscustomobject]@{ state = $State }
}

function Add-RepositoryShapeTool($ToolIds, $ToolStates, [string]$ToolId, [string]$State = "DEFAULT") {
    if ($ToolId -notin $ToolIds) { [void]$ToolIds.Add($ToolId) }
    if (-not $ToolStates.ContainsKey($ToolId) -or $State -eq "OVERRIDE") {
        $ToolStates[$ToolId] = $State
    }
}

function Add-RepositoryShapeSurface($SurfaceIds, $SurfaceStates, [string]$SurfaceId, [string]$State = "OVERRIDE") {
    if ($SurfaceId -notin $SurfaceIds) { [void]$SurfaceIds.Add($SurfaceId) }
    if (-not $SurfaceStates.ContainsKey($SurfaceId) -or $State -eq "OVERRIDE") {
        $SurfaceStates[$SurfaceId] = $State
    }
}

function Get-ShapeCompatibleSurfaceValues($Catalog, [string[]]$SurfaceIds) {
    $values = New-Object System.Collections.Generic.List[string]
    foreach ($surfaceId in @($SurfaceIds | Select-Object -Unique)) {
        try {
            $entry = Find-DefaultCatalogEntry -Catalog $Catalog -Identifier $surfaceId -Kind "surface"
            foreach ($value in @($entry.compatible_surfaces)) {
                if ($value -notin $values) { [void]$values.Add([string]$value) }
            }
        }
        catch {
            # Shape detection may find a non-catalog marker. It is reported as
            # a surface candidate but cannot authorize a Tool Default.
        }
    }
    return @($values)
}

function Test-IsBaseVerificationWorkflow([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $leaf = Split-Path -Leaf $Path
    if ($leaf -notin @("verify.yml", "verify.yaml")) { return $false }
    $text = Get-Content -Raw -Encoding UTF8 -LiteralPath $Path
    return $text -match "(?im)\.kinotch/scripts/knt\.ps1\s+doctor" -and
        $text -match "(?im)\.kinotch/scripts/knt\.ps1\s+setup" -and
        $text -match "(?im)\.kinotch/scripts/knt\.ps1\s+verify"
}

function Get-RepositoryShape($Catalog) {
    $surfaceIds = New-Object System.Collections.Generic.List[string]
    $surfaceStates = @{}
    $toolIds = New-Object System.Collections.Generic.List[string]
    $toolStates = @{}
    $markers = New-Object System.Collections.Generic.List[string]
    $packagePath = Join-Path $Root "package.json"
    $packageText = ""
    $package = $null
    if (Test-Path -LiteralPath $packagePath -PathType Leaf) {
        $packageText = Get-Content -Raw -Encoding UTF8 $packagePath
        try { $package = $packageText | ConvertFrom-Json } catch { }
        [void]$markers.Add("package.json")
    }
    $cargoPath = Join-Path $Root "Cargo.toml"
    $cargoText = if (Test-Path -LiteralPath $cargoPath -PathType Leaf) { Get-Content -Raw -Encoding UTF8 $cargoPath } else { "" }
    if ($cargoText) { [void]$markers.Add("Cargo.toml") }
    $pythonPaths = @((Join-Path $Root "pyproject.toml"), (Join-Path $Root "requirements.txt"))
    $pythonText = ""
    foreach ($pythonPath in $pythonPaths) {
        if (Test-Path -LiteralPath $pythonPath -PathType Leaf) {
            $pythonText += Get-Content -Raw -Encoding UTF8 $pythonPath
            [void]$markers.Add((Split-Path -Leaf $pythonPath))
        }
    }
    $workflowPath = Join-Path $Root ".github/workflows"
    if (Test-Path -LiteralPath $workflowPath -PathType Container) {
        [void]$markers.Add(".github/workflows")
        $workflowFiles = @(Get-ChildItem -LiteralPath $workflowPath -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in @(".yml", ".yaml") -and -not (Test-IsBaseVerificationWorkflow $_.FullName) })
        $workflowText = ($workflowFiles | ForEach-Object { Get-Content -Raw -Encoding UTF8 -LiteralPath $_.FullName }) -join "`n"
        if ($workflowFiles.Count -gt 0) {
            $hasVerificationGate = $workflowText -match "(?im)(npm\s+(?:run\s+)?(?:test|lint|typecheck|build)|pnpm\s+(?:test|lint|typecheck|build)|yarn\s+(?:test|lint|typecheck|build)|pytest|python\s+-m\s+(?:pytest|unittest)|cargo\s+(?:test|check|build)|knt(?:\.cmd)?\s+verify|\.kinotch/scripts/knt\.ps1\s+verify)"
            Add-RepositoryShapeTool -ToolIds $toolIds -ToolStates $toolStates -ToolId "ci-test" -State $(if ($hasVerificationGate) { "OVERRIDE" } else { "DEFAULT" })
        }
    }
    $publicPath = Join-Path $Root "public"
    $staticPath = Join-Path $Root "static"
    $hasWebAssets = (Test-Path -LiteralPath $publicPath -PathType Container) -or (Test-Path -LiteralPath $staticPath -PathType Container) -or (Test-Path -LiteralPath (Join-Path $Root "index.html") -PathType Leaf)
    $scriptsText = if ($package -and $package.scripts) { ($package.scripts | Out-String) } else { "" }
    $dependencyText = ($packageText + " " + $pythonText + " " + $cargoText).ToLowerInvariant()

    # Wrangler is also the normal Pages/static-Web toolchain. Treat it as an
    # API marker only when an application/API boundary is explicit.
    if ($dependencyText -match "(?i)\bhono\b|service\s+binding|cloudflare\s+worker") {
        Add-RepositoryShapeSurface -SurfaceIds $surfaceIds -SurfaceStates $surfaceStates -SurfaceId "api"
    }
    if ($hasWebAssets -or $dependencyText -match "vite|react|vue|svelte|astro|next") {
        Add-RepositoryShapeSurface -SurfaceIds $surfaceIds -SurfaceStates $surfaceStates -SurfaceId "web-app"
    }
    # knt verify is an L1 Hard Base command. Shape detection must not report it
    # as an optional Tool Default; CI remains the independent L2 candidate.
    $packageBin = $false
    if ($package -and $package.PSObject.Properties["bin"] -and $null -ne $package.bin) {
        $packageBin = $true
    }
    $packageCliScript = $false
    if ($package -and $package.PSObject.Properties["scripts"] -and $package.scripts) {
        $packageCliScript = @($package.scripts.PSObject.Properties.Name | Where-Object { $_ -match "(^|[-_:])(cli|command)$" }).Count -gt 0
    }
    $hasPythonScripts = $pythonText -match "(?im)^\s*\[(?:project\.scripts|tool\.poetry\.scripts)\]"
    $hasCargoBin = $cargoText -match "(?im)^\s*\[\[bin\]\]"
    if ($packageBin -or $packageCliScript -or $hasPythonScripts -or $hasCargoBin) {
        Add-RepositoryShapeSurface -SurfaceIds $surfaceIds -SurfaceStates $surfaceStates -SurfaceId "cli"
    }
    if ($cargoText -match "egui|tauri|winit|windows|gtk") { Add-RepositoryShapeSurface -SurfaceIds $surfaceIds -SurfaceStates $surfaceStates -SurfaceId "windows" }
    if ($pythonText -match "streamlit|gradio") { Add-RepositoryShapeSurface -SurfaceIds $surfaceIds -SurfaceStates $surfaceStates -SurfaceId "web-app" }
    if ($dependencyText -match "mcp") { Add-RepositoryShapeSurface -SurfaceIds $surfaceIds -SurfaceStates $surfaceStates -SurfaceId "mcp" }
    if ($Root -match "dev_agent|agent") { Add-RepositoryShapeSurface -SurfaceIds $surfaceIds -SurfaceStates $surfaceStates -SurfaceId "agent" }

    $scanDirectories = @("public", "static", "src", "app", "tools", "scripts", "backend", "frontend") | ForEach-Object { Join-Path $Root $_ } | Where-Object { Test-Path -LiteralPath $_ -PathType Container }
    $scanFiles = @()
    foreach ($scanDirectory in $scanDirectories) {
        $scanFiles += @(Get-ChildItem -LiteralPath $scanDirectory -Recurse -File -Force -ErrorAction SilentlyContinue)
    }
    $scanFiles += @(Get-ChildItem -LiteralPath $Root -File -Force -ErrorAction SilentlyContinue)
    $manifestPath = @(
        (Join-Path $Root "public/manifest.webmanifest"),
        (Join-Path $Root "public/manifest.json"),
        (Join-Path $Root "manifest.webmanifest"),
        (Join-Path $Root "manifest.json")
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    $workerFiles = @($scanFiles | Where-Object { $_.Name -match "service-worker|sw\.js$" })
    if ($manifestPath -and $workerFiles.Count -gt 0) { Add-RepositoryShapeTool -ToolIds $toolIds -ToolStates $toolStates -ToolId "pwa" -State "OVERRIDE" }
    $integrityDirectories = @("src", "app", "tools", "scripts", "backend", "frontend") |
        ForEach-Object { Join-Path $Root $_ } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Container }
    $integrityFiles = @()
    foreach ($integrityDirectory in $integrityDirectories) {
        $integrityFiles += @(Get-ChildItem -LiteralPath $integrityDirectory -Recurse -File -Force -ErrorAction SilentlyContinue)
    }
    $generatedFiles = @($integrityFiles | Where-Object { $_.Name -match "(^generated|\.generated\.|generated\.)" })
    $integrityText = $scriptsText
    foreach ($scanFile in @($integrityFiles | Where-Object { $_.Extension -in @(".ps1", ".mjs", ".js", ".py", ".rs", ".toml", ".yml", ".yaml") })) {
        $integrityText += "`n" + (Get-Content -Raw -Encoding UTF8 -LiteralPath $scanFile.FullName -ErrorAction SilentlyContinue)
    }
    $hasIntegrityEvidence = $integrityText -match "(?i)sha[-_]?256|source[_-]?fingerprint|stale|generated.*check|check.*generated|snapshot.*check"
    if ($generatedFiles.Count -gt 0 -or $hasIntegrityEvidence) {
        Add-RepositoryShapeTool -ToolIds $toolIds -ToolStates $toolStates -ToolId "generated-integrity" -State $(if ($hasIntegrityEvidence) { "OVERRIDE" } else { "DEFAULT" })
    }

    # A filename or text marker is not enough to make a Tool Default relevant
    # to the detected repository shape.  Filter candidates through the same
    # compatibility rule used by init/migrate so an Agent repository, for
    # example, is not offered generated-integrity merely because its own
    # evidence records contain the words "sha256" or "stale".
    $shapeSurfaceValues = @(Get-ShapeCompatibleSurfaceValues -Catalog $Catalog -SurfaceIds @($surfaceIds))
    $compatibleToolIds = New-Object System.Collections.Generic.List[string]
    $compatibleToolStates = @{}
    foreach ($toolId in @($toolIds | Select-Object -Unique)) {
        $entry = Find-DefaultCatalogEntry -Catalog $Catalog -Identifier $toolId -Kind "tool"
        if (-not (Get-DefaultCompatibilityError -Entry $entry -SelectedSurfaces $shapeSurfaceValues)) {
            [void]$compatibleToolIds.Add($toolId)
            $state = if ($toolStates.ContainsKey($toolId)) { [string]$toolStates[$toolId] } else { "DEFAULT" }
            $compatibleToolStates[$toolId] = $state
        }
    }

    return [pscustomobject]@{
        markers = @($markers | Select-Object -Unique)
        surfaceIds = @($surfaceIds | Select-Object -Unique)
        surfaceStates = $surfaceStates
        toolIds = @($compatibleToolIds | Select-Object -Unique)
        toolStates = $compatibleToolStates
    }
}

function Get-MigrateProfileEntries($Manifest, $Catalog, $Options, $Shape) {
    $requested = @($Options.profiles)
    if ($requested.Count -eq 0) {
        if ($Manifest -and $Manifest.PSObject.Properties["profiles"] -and @($Manifest.profiles).Count -gt 0) {
            $requested = @($Manifest.profiles | ForEach-Object { [string]$_ })
        }
        elseif ($Manifest -and -not [string]::IsNullOrWhiteSpace([string]$Manifest.profile)) {
            $requested = @([string]$Manifest.profile)
        }
        elseif ($Shape) {
            $requested = @($Shape.surfaceIds)
        }
    }
    $entries = @()
    foreach ($profileName in @($requested | Select-Object -Unique)) {
        try {
            $entries += Find-DefaultCatalogEntry -Catalog $Catalog -Identifier $profileName -Kind "surface"
        }
        catch {
            if (@($Options.profiles) -contains $profileName) { throw }
            Write-Host "[migrate] WARN profile '$profileName' is not in the Default catalog; skipped" -ForegroundColor Yellow
        }
    }
    return @($entries)
}

function Get-ManifestSurfaceIds($Manifest) {
    if (-not $Manifest -or -not $Manifest.PSObject.Properties["surfaces"]) { return @() }
    return @($Manifest.surfaces.PSObject.Properties | Where-Object { $_.Value -eq $true } | ForEach-Object { [string]$_.Name } | Select-Object -Unique)
}

function Get-MigrateToolEntries($Manifest, $Catalog, $Options, $Shape) {
    if (@($Options.defaults).Count -gt 0) {
        $existingSurfaces = if ($Manifest) { @(Get-ManifestSurfaceIds -Manifest $Manifest) } else { @() }
        return @(Resolve-DefaultSelections -Options $Options -Catalog $Catalog -RequireProfile $false -ExistingSurfaces $existingSurfaces).toolEntries
    }

    if ($Shape -and @($Shape.toolIds).Count -gt 0) {
        $entries = @()
        foreach ($candidateId in @($Shape.toolIds)) {
            $entries += Find-DefaultCatalogEntry -Catalog $Catalog -Identifier $candidateId -Kind "tool"
        }
        return @($entries)
    }

    $candidateIds = New-Object System.Collections.Generic.List[string]
    $baseVerifyWorkflow = Join-Path $Root ".github/workflows/verify.yml"
    if ((Test-Path -LiteralPath $baseVerifyWorkflow -PathType Leaf) -and -not (Test-IsBaseVerificationWorkflow $baseVerifyWorkflow)) {
        [void]$candidateIds.Add("ci-test")
    }
    $generatedCandidates = @(Get-ChildItem -LiteralPath (Join-Path $Root "project") -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match "(^generated|\.generated\.|generated\.)"
    })
    if ($generatedCandidates.Count -gt 0) { [void]$candidateIds.Add("generated-integrity") }

    $entries = @()
    foreach ($candidateId in @($candidateIds | Select-Object -Unique)) {
        $entries += Find-DefaultCatalogEntry -Catalog $Catalog -Identifier $candidateId -Kind "tool"
    }
    return @($entries)
}

function Get-MigrateRecommendedState($Entry, $Shape) {
    if ([string]$Entry.kind -eq "surface" -and $Shape -and $Shape.surfaceStates -and $Shape.surfaceStates.ContainsKey([string]$Entry.id)) {
        return [string]$Shape.surfaceStates[[string]$Entry.id]
    }
    if ([string]$Entry.kind -eq "tool" -and $Shape -and $Shape.toolStates -and $Shape.toolStates.ContainsKey([string]$Entry.id)) {
        return [string]$Shape.toolStates[[string]$Entry.id]
    }
    return "DEFAULT"
}

function Write-KntJsonFile([string]$Path, $Value) {
    $json = ConvertTo-Json $Value -Depth 20
    [IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
}

function Copy-DefaultImplementation([string]$DefaultId, [string]$ProjectRoot, [string]$Kind = "Tool", [System.Collections.Generic.List[string]]$ConflictingDefaults) {
    Assert-RepositoryWriteAllowed "Default materialization"
    $templateRoot = Join-Path $BaseDir ("templates/defaults/" + $DefaultId)
    if (-not (Test-Path -LiteralPath $templateRoot -PathType Container)) { return }
    foreach ($templateFile in @(Get-ChildItem -LiteralPath $templateRoot -Recurse -File -Force)) {
        $relative = ConvertTo-BaseRelativePath -Root $templateRoot -AbsolutePath $templateFile.FullName
        if ($relative -like ".github/*") {
            $destination = Join-Path $Root $relative
        }
        else {
            $destination = Join-Path $ProjectRoot $relative
        }
        if (Test-Path -LiteralPath $destination) {
            $sameContent = $false
            try {
                $sameContent = (Get-BaseFileHash -Path $templateFile.FullName) -eq (Get-BaseFileHash -Path $destination)
            }
            catch {
                $sameContent = $false
            }
            if ($sameContent) {
                Write-Knt "$Kind Default '$DefaultId' preserved identical path: $relative"
            }
            else {
                if ($null -ne $ConflictingDefaults -and $DefaultId -notin $ConflictingDefaults) { [void]$ConflictingDefaults.Add($DefaultId) }
                Write-Knt "$Kind Default '$DefaultId' found conflicting existing path: $relative; state OVERRIDE"
            }
            continue
        }
        $parent = Split-Path -Parent $destination
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        Copy-Item -LiteralPath $templateFile.FullName -Destination $destination -Force
        Write-Knt "$Kind Default '$DefaultId' added: $relative"
    }
}

function Invoke-GeneratedDefaultScript([string]$ScriptRelativePath, [string]$CommandLabel) {
    $projectRoot = Join-Path $Root "project"
    $scriptPath = Join-Path $projectRoot $ScriptRelativePath
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        Write-Host "[$CommandLabel] MISSING project/$ScriptRelativePath" -ForegroundColor Red
        return 1
    }
    $powerShell = (Get-Command pwsh -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    if ([string]::IsNullOrWhiteSpace($powerShell)) {
        $powerShell = (Get-Command powershell -ErrorAction Stop | Select-Object -First 1).Source
    }
    & $powerShell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Root $projectRoot
    if ($null -ne $LASTEXITCODE) { return $LASTEXITCODE }
    return 0
}

function Invoke-PwaCheck {
    return Invoke-GeneratedDefaultScript -ScriptRelativePath "tools/pwa-check.ps1" -CommandLabel "pwa-check"
}

function Invoke-GeneratedIntegrityCheck {
    return Invoke-GeneratedDefaultScript -ScriptRelativePath "tools/check-generated.ps1" -CommandLabel "generated-integrity"
}

function Invoke-Init {
    if (Test-Path -LiteralPath $ManifestPath -PathType Leaf) {
        Write-Host "[init] Repository is already initialized: project/project.json" -ForegroundColor Yellow
        return 1
    }

    Assert-RepositoryWriteAllowed "init"

    $catalog = Get-DefaultCatalog
    $selection = Get-SelectedInitProfiles
    $profileEntries = @($selection.profileEntries)
    $toolEntries = @($selection.toolEntries)
    $profiles = @($profileEntries | ForEach-Object { Get-DefaultProfileName $_ })
    $projectRoot = Join-Path $Root "project"
    if (Test-Path -LiteralPath $projectRoot -PathType Container) {
        $existing = @(Get-ChildItem -LiteralPath $projectRoot -Force)
        if ($existing.Count -gt 0) {
            Write-Host "[init] Project directory is not empty; refusing to overwrite Project files" -ForegroundColor Yellow
            return 1
        }
    }

    $templateRoot = Join-Path $BaseDir "templates/project"
    if (-not (Test-Path -LiteralPath $templateRoot -PathType Container)) {
        throw "Project template not found: $templateRoot"
    }
    New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null

    foreach ($templateEntry in @(Get-ChildItem -LiteralPath $templateRoot -Force)) {
        if ($templateEntry.Name -eq "README.md") {
            $destination = Join-Path $Root "README.md"
        }
        elseif ($templateEntry.Name -eq ".gitignore") {
            $destination = Join-Path $projectRoot ".gitignore"
        }
        else {
            $destination = Join-Path $projectRoot $templateEntry.Name
        }

        if (Test-Path -LiteralPath $destination) {
            if ($templateEntry.Name -eq "README.md") { continue }
            throw "Refusing to overwrite existing generated path: $destination"
        }
        Copy-Item -LiteralPath $templateEntry.FullName -Destination $destination -Recurse -Force
    }

    $manifest = Get-KntJson -Path $ManifestPath
    $manifest.project.name = (Split-Path -Leaf $Root.TrimEnd([char[]]@("/", "\")))
    if ([string]::IsNullOrWhiteSpace($manifest.project.name)) { $manifest.project.name = "kinotch-project" }
    $defaultIds = @($profileEntries + $toolEntries | ForEach-Object { [string]$_.id })
    $manifest.project.description = "KiNoTch. Project initialized with Default Packs: " + ($defaultIds -join ", ")
    $manifest.profile = $profiles[0]
    $manifest | Add-Member -NotePropertyName profiles -NotePropertyValue $profiles -Force
    $manifest.paths | Add-Member -NotePropertyName defaults -NotePropertyValue "defaults.json" -Force

    $surfaceNames = New-Object System.Collections.Generic.List[string]
    $defaults = [pscustomobject]@{ schema_version = 1; packs = [pscustomobject]@{} }
    $conflictingDefaults = New-Object System.Collections.Generic.List[string]
    foreach ($profileEntry in $profileEntries) {
        $profileName = Get-DefaultProfileName $profileEntry
        $profilePath = Join-Path $BaseDir ("profiles/" + $profileName + ".json")
        $profile = Get-KntJson -Path $profilePath
        foreach ($surface in @($profile.surfaces.PSObject.Properties | Where-Object { $_.Value -eq $true })) {
            if ($surface.Name -notin $surfaceNames) { [void]$surfaceNames.Add([string]$surface.Name) }
        }
        $defaults.packs | Add-Member -NotePropertyName ([string]$profileEntry.id) -NotePropertyValue (Get-DefaultStateEntry "DEFAULT") -Force
        Copy-DefaultImplementation -DefaultId ([string]$profileEntry.id) -ProjectRoot $projectRoot -Kind "Surface" -ConflictingDefaults $conflictingDefaults
    }
    foreach ($toolEntry in $toolEntries) {
        $defaults.packs | Add-Member -NotePropertyName ([string]$toolEntry.id) -NotePropertyValue (Get-DefaultStateEntry "DEFAULT") -Force
        Copy-DefaultImplementation -DefaultId ([string]$toolEntry.id) -ProjectRoot $projectRoot -ConflictingDefaults $conflictingDefaults
    }
    foreach ($conflictingDefault in @($conflictingDefaults | Select-Object -Unique)) {
        $defaults.packs.$conflictingDefault.state = "OVERRIDE"
    }
    $manifest.runtime.modules = @()
    foreach ($surface in @($manifest.surfaces.PSObject.Properties)) {
        $surface.Value = ($surface.Name -in $surfaceNames)
    }
    if ($toolEntries.id -contains "pwa") {
        $pwaManifestPath = Join-Path $projectRoot "public/manifest.webmanifest"
        if (Test-Path -LiteralPath $pwaManifestPath -PathType Leaf) {
            $pwaManifest = Get-KntJson -Path $pwaManifestPath
            $pwaManifest.name = [string]$manifest.project.name
            $pwaManifest.short_name = [string]$manifest.project.name
            Write-KntJsonFile -Path $pwaManifestPath -Value $pwaManifest
        }
    }
    Write-KntJsonFile -Path $ManifestPath -Value $manifest
    Write-KntJsonFile -Path (Join-Path $projectRoot "defaults.json") -Value $defaults
    Write-Knt "Initialized Project with Default Packs: $($defaultIds -join ', ')"
    return 0
}

function Invoke-Migrate($Manifest) {
    $options = Get-DefaultOptions "migrate"
    $catalog = Get-DefaultCatalog
    $shape = Get-RepositoryShape -Catalog $catalog
    if (-not $Manifest) {
        Write-Knt ("Detected repository markers: " + ($(if ($shape.markers.Count) { $shape.markers -join ", " } else { "(none)" })))
        Write-Knt ("Detected Surface candidates: " + ($(if ($shape.surfaceIds.Count) { $shape.surfaceIds -join ", " } else { "(none)" })))
        Write-Knt ("Detected Tool candidates: " + ($(if ($shape.toolIds.Count) { $shape.toolIds -join ", " } else { "(none)" })))
    }
    $profileEntries = @(Get-MigrateProfileEntries -Manifest $Manifest -Catalog $catalog -Options $options -Shape $shape)
    $toolEntries = @(Get-MigrateToolEntries -Manifest $Manifest -Catalog $catalog -Options $options -Shape $shape)
    $selectedSurfaceValues = @($profileEntries | ForEach-Object { @($_.compatible_surfaces) } | Select-Object -Unique)
    if ($Manifest) {
        $selectedSurfaceValues = @($selectedSurfaceValues + @(Get-ManifestSurfaceIds -Manifest $Manifest) | Select-Object -Unique)
    }
    foreach ($toolEntry in $toolEntries) {
        $compatibilityError = Get-DefaultCompatibilityError -Entry $toolEntry -SelectedSurfaces $selectedSurfaceValues
        if ($compatibilityError) { throw $compatibilityError }
    }
    $selectedEntries = @($profileEntries + $toolEntries)
    if ($selectedEntries.Count -eq 0) {
        Write-Knt "No Default candidates detected. Use --profile <surface> or --default <tool-default>."
        return 0
    }

    $projectRoot = Join-Path $Root "project"
    $defaultsRelative = Get-ManifestPathValue $Manifest "defaults" "defaults.json"
    $defaultsPath = Join-Path $projectRoot $defaultsRelative
    $defaultsSchema = Get-KntJson -Path (Join-Path $BaseDir "schemas/defaults.schema.json")
    $defaults = $null
    $createdDefaults = $false
    if (Test-Path -LiteralPath $defaultsPath -PathType Leaf) {
        $defaults = Get-KntJson -Path $defaultsPath
        $defaultErrors = @(Test-KntSchema -Data $defaults -Schema $defaultsSchema -Path $defaultsRelative)
        if ($defaultErrors.Count -gt 0) {
            throw "Default state validation failed: " + ($defaultErrors -join "; ")
        }
        foreach ($packProperty in @($defaults.packs.PSObject.Properties)) {
            [void](Find-AnyDefaultCatalogEntry -Catalog $catalog -Identifier ([string]$packProperty.Name))
        }
    }
    else {
        $defaults = [pscustomobject]@{ schema_version = 1; packs = [pscustomobject]@{} }
        $createdDefaults = $true
    }

    $changedDefaults = $false
    $conflictingDefaults = New-Object System.Collections.Generic.List[string]
    foreach ($entry in $selectedEntries) {
        $packName = [string]$entry.id
        $packProperty = $defaults.packs.PSObject.Properties[$packName]
        if ($packProperty) {
            $state = [string](Get-KntJsonProperty $packProperty.Value "state")
            Write-Knt "Candidate Default Pack '$packName': preserved state $state"
        }
        else {
            $state = Get-MigrateRecommendedState -Entry $entry -Shape $shape
            $suffix = if ($state -eq "OVERRIDE") { " (existing equivalent detected)" } else { "" }
            Write-Knt "Candidate Default Pack '$packName': state $state$suffix"
            if ($options.apply) {
                $defaults.packs | Add-Member -NotePropertyName $packName -NotePropertyValue ([pscustomobject]@{ state = $state }) -Force
                $changedDefaults = $true
            }
        }
    }

    if (-not $options.apply) {
        Write-Knt "Dry run: no files changed. Re-run with --apply to record selected Default Pack states."
        return 0
    }

    Assert-RepositoryWriteAllowed "migrate --apply"

    if (-not $Manifest) {
        throw "migrate --apply requires an existing Project Manifest; dry-run completed without changing this repository"
    }

    foreach ($entry in $selectedEntries) {
        $packProperty = $defaults.packs.PSObject.Properties[[string]$entry.id]
        $state = if ($packProperty) { [string](Get-KntJsonProperty $packProperty.Value "state") } else { "DEFAULT" }
        if ($state -eq "DEFAULT") {
            $kind = if ([string]$entry.kind -eq "surface") { "Surface" } else { "Tool" }
            Copy-DefaultImplementation -DefaultId ([string]$entry.id) -ProjectRoot $projectRoot -Kind $kind -ConflictingDefaults $conflictingDefaults
        }
    }
    foreach ($conflictingDefault in @($conflictingDefaults | Select-Object -Unique)) {
        $defaults.packs.$conflictingDefault.state = "OVERRIDE"
        $changedDefaults = $true
    }

    $changedManifest = $false
    if (-not $Manifest.paths.PSObject.Properties["defaults"]) {
        $Manifest.paths | Add-Member -NotePropertyName defaults -NotePropertyValue $defaultsRelative -Force
        $changedManifest = $true
    }
    if ($createdDefaults -or $changedDefaults) {
        Write-KntJsonFile -Path $defaultsPath -Value $defaults
        Write-Knt "Updated Default state file: project/$defaultsRelative"
    }
    if ($changedManifest) {
        Write-KntJsonFile -Path $ManifestPath -Value $Manifest
        Write-Knt "Updated Manifest path declaration: paths.defaults"
    }
    if (-not $createdDefaults -and -not $changedDefaults -and -not $changedManifest) {
        Write-Knt "No changes required; existing Default states were preserved."
    }
    return 0
}

function Test-BaseFiles {
    if (-not (Test-Path -LiteralPath $BaseFilesPath -PathType Leaf)) {
        Write-Knt "base-files.json is missing."
        return $false
    }
    $index = Get-KntJson -Path $BaseFilesPath
    $ok = $true
    $currentVersion = (Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $BaseDir "BASE_VERSION")).Trim()
    if ([string]$index.base_version -ne $currentVersion) {
        Write-Host "[base-check] VERSION  index=$($index.base_version) current=$currentVersion" -ForegroundColor Yellow
        $ok = $false
    }
    $indexedPaths = @($index.files | ForEach-Object { [string]$_.path })
    foreach ($expectedPath in @(Get-BaseProtectedPaths -Root $Root)) {
        if ($expectedPath -notin $indexedPaths) {
            Write-Host "[base-check] UNINDEXED  $expectedPath" -ForegroundColor Yellow
            $ok = $false
        }
    }
    foreach ($indexedPath in $indexedPaths) {
        if ($indexedPath -notin @(Get-BaseProtectedPaths -Root $Root)) {
            Write-Host "[base-check] ORPHANED  $indexedPath" -ForegroundColor Yellow
            $ok = $false
        }
    }
    foreach ($entry in @($index.files)) {
        $path = Join-Path $Root $entry.path
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            Write-Host "[base-check] MISSING  $($entry.path)" -ForegroundColor Red
            $ok = $false
            continue
        }
        $hash = Get-BaseFileHash -Path $path
        if ($hash -ne $entry.sha256) {
            Write-Host "[base-check] CHANGED  $($entry.path)" -ForegroundColor Yellow
            $ok = $false
        }
    }
    if ($ok) { Write-Knt "Base files: OK" }
    return $ok
}

function Resolve-Command($Manifest, [string]$Name) {
    $prop = $Manifest.commands.PSObject.Properties[$Name]
    if (-not $prop) { return $null }
    $value = $prop.Value
    if ($value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($value)) { return $null }
        return [pscustomobject]@{ mode = "legacy"; run = $value; cwd = "project" }
    }
    if ($value.PSObject.Properties["exec"]) {
        $exec = [string]$value.exec
        if ([string]::IsNullOrWhiteSpace($exec)) { return $null }
        $args = @()
        if ($value.PSObject.Properties["args"]) {
            $args = @($value.args | ForEach-Object { [string]$_ })
        }
        $forwardArgs = $false
        if ($value.PSObject.Properties["forward_args"]) {
            $forwardArgs = [bool]$value.forward_args
        }
        $cwd = if ($value.PSObject.Properties["cwd"] -and $value.cwd) { [string]$value.cwd } else { "project" }
        return [pscustomobject]@{
            mode = "structured"
            exec = $exec
            args = $args
            cwd = $cwd
            forward_args = $forwardArgs
        }
    }
    if (-not $value.run) { return $null }
    $cwd = if ($value.cwd) { [string]$value.cwd } else { "project" }
    return [pscustomobject]@{ mode = "legacy"; run = [string]$value.run; cwd = $cwd }
}

function Get-ManifestPathValue($Manifest, [string]$Name, [string]$Default) {
    $value = Get-KntJsonProperty $Manifest.paths $Name
    if ([string]::IsNullOrWhiteSpace([string]$value)) { return $Default }
    return [string]$value
}

function Invoke-ProjectCommand($Manifest, [string]$Name) {
    $spec = Resolve-Command $Manifest $Name
    if (-not $spec) {
        Write-Knt "Command '$Name' is not configured for this project."
        return 0
    }
    $cwd = Join-Path $Root $spec.cwd
    if (-not (Test-Path -LiteralPath $cwd -PathType Container)) {
        Write-Host "[doctor] MISSING command cwd: $($spec.cwd)" -ForegroundColor Red
        return 1
    }
    Push-Location $cwd
    try {
        $commandOutput = @()
        if ($spec.mode -eq "structured") {
            $forwardedArgs = @($RemainingArgs | Where-Object { $null -ne $_ })
            if ($forwardedArgs.Count -gt 0 -and -not $spec.forward_args) {
                throw "Structured command '$Name' must set forward_args=true to accept forwarded arguments"
            }
            $invokeArgs = @($spec.args)
            if ($spec.forward_args) { $invokeArgs += $forwardedArgs }
            Write-Knt "$Name -> $($spec.exec)"
            $commandOutput = @(& $spec.exec @invokeArgs 2>&1)
        }
        else {
            $forwardedArgs = @($RemainingArgs | Where-Object { $null -ne $_ })
            if ($forwardedArgs.Count -gt 0) {
                throw "Legacy command '$Name' cannot safely forward arguments; use structured exec/args with forward_args=true"
            }
            Write-Knt "$Name -> $($spec.run)"
            $commandOutput = @(Invoke-Expression $spec.run 2>&1)
        }
        $commandExitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
        foreach ($outputLine in $commandOutput) { Write-Host $outputLine }
        return $commandExitCode
    }
    finally {
        Pop-Location
    }
}

function Invoke-Verify($Manifest) {
    if (Test-ProjectDefaultEnabled -Manifest $Manifest -DefaultId "generated-integrity") {
        $integrityCode = Invoke-GeneratedIntegrityCheck
        if ($integrityCode -ne 0) { return $integrityCode }
    }
    if (Test-ProjectDefaultEnabled -Manifest $Manifest -DefaultId "pwa") {
        $pwaCode = Invoke-PwaCheck
        if ($pwaCode -ne 0) { return $pwaCode }
    }

    $direct = Resolve-Command $Manifest "verify"
    if ($direct) { return (Invoke-ProjectCommand $Manifest "verify") }
    foreach ($fallback in @("test", "build")) {
        if (Resolve-Command $Manifest $fallback) {
            $code = Invoke-ProjectCommand $Manifest $fallback
            if ($code -ne 0) { return $code }
        }
    }
    return 0
}

function Add-DoctorSchemaErrors {
    param([System.Collections.Generic.List[string]]$Errors, $Data, $Schema, [string]$Path)
    foreach ($errorText in @(Test-KntSchema -Data $Data -Schema $Schema -Path $Path)) {
        [void]$Errors.Add($errorText)
    }
}

function Test-SelectedDefaultImplementations($DefaultsData) {
    $ok = $true
    if (-not $DefaultsData) { return $true }
    $projectRoot = Join-Path $Root "project"
    foreach ($packProperty in @($DefaultsData.packs.PSObject.Properties)) {
        $state = [string](Get-KntJsonProperty $packProperty.Value "state")
        if ($state -ne "DEFAULT") { continue }
        $defaultId = [string]$packProperty.Name
        switch ($defaultId) {
            "cli" {
                if (-not (Test-Path -LiteralPath (Join-Path $projectRoot "tools/cli-default.ps1") -PathType Leaf)) {
                    Write-Host "[doctor] MISSING implementation for Surface Default 'cli'" -ForegroundColor Red
                    $ok = $false
                }
            }
            "windows" {
                if (-not (Test-Path -LiteralPath (Join-Path $projectRoot "tools/windows-shell.ps1") -PathType Leaf)) {
                    Write-Host "[doctor] MISSING implementation for Surface Default 'windows'" -ForegroundColor Red
                    $ok = $false
                }
            }
            "mcp" {
                if (-not (Test-Path -LiteralPath (Join-Path $projectRoot "contracts/mcp-tools.json") -PathType Leaf)) {
                    Write-Host "[doctor] MISSING implementation for Surface Default 'mcp'" -ForegroundColor Red
                    $ok = $false
                }
            }
            "api" {
                if (-not (Test-Path -LiteralPath (Join-Path $projectRoot "contracts/api-error-envelope.json") -PathType Leaf)) {
                    Write-Host "[doctor] MISSING implementation for Surface Default 'api'" -ForegroundColor Red
                    $ok = $false
                }
            }
            "ci-test" {
                if (-not (Test-Path -LiteralPath (Join-Path $Root ".github/workflows/kinotch-default.yml") -PathType Leaf)) {
                    Write-Host "[doctor] MISSING implementation for Default 'ci-test'" -ForegroundColor Red
                    $ok = $false
                }
            }
            "pwa" {
                foreach ($relative in @("public/manifest.webmanifest", "public/service-worker.js", "src/pwa/register.js", "tools/pwa-check.ps1")) {
                    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot $relative) -PathType Leaf)) {
                        Write-Host "[doctor] MISSING implementation for Default 'pwa': project/$relative" -ForegroundColor Red
                        $ok = $false
                    }
                }
            }
            "generated-integrity" {
                foreach ($relative in @("generated-integrity.json", "tools/check-generated.ps1", "tools/update-generated-integrity.ps1")) {
                    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot $relative) -PathType Leaf)) {
                        Write-Host "[doctor] MISSING implementation for Default 'generated-integrity': project/$relative" -ForegroundColor Red
                        $ok = $false
                    }
                }
            }
            "file-io" {
                foreach ($relative in @("contracts/file-io.json", "tools/file-io.ps1")) {
                    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot $relative) -PathType Leaf)) {
                        Write-Host "[doctor] MISSING implementation for Default 'file-io': project/$relative" -ForegroundColor Red
                        $ok = $false
                    }
                }
            }
        }
    }
    return $ok
}

function Invoke-Doctor($Manifest) {
    $ok = $true
    Write-Knt "Repository root: $Root"
    Write-Knt "Project: $($Manifest.project.name) [$($Manifest.project.type)]"
    $selectedProfiles = @([string]$Manifest.profile)
    $profilesProperty = $Manifest.PSObject.Properties["profiles"]
    if ($profilesProperty -and @($Manifest.profiles).Count -gt 0) {
        $selectedProfiles = @($Manifest.profiles | ForEach-Object { [string]$_ })
    }
    Write-Knt "Profile: $($Manifest.profile)$(if ($selectedProfiles.Count -gt 1) { ' [' + ($selectedProfiles -join ', ') + ']' } else { '' })"
    $baseVersion = (Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $BaseDir "BASE_VERSION")).Trim()
    Write-Knt "Base version: $baseVersion"

    if (-not $RootOverride -and -not (Test-BaseFiles)) { $ok = $false }

    $required = @(
        "project/docs/INDEX.md",
        "project/docs/CURRENT_STATE.md",
        "project/contracts/actions.json",
        "project/contracts/surfaces.json"
    )
    foreach ($requiredPath in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $Root $requiredPath) -PathType Leaf)) {
            Write-Host "[doctor] MISSING $requiredPath" -ForegroundColor Red
            $ok = $false
        }
    }

    $schemaErrors = New-Object System.Collections.Generic.List[string]
    $manifestSchema = Get-KntJson -Path (Join-Path $BaseDir "schemas/project.schema.json")
    $actionSchema = Get-KntJson -Path (Join-Path $BaseDir "schemas/action.schema.json")
    $surfaceSchema = Get-KntJson -Path (Join-Path $BaseDir "schemas/surface.schema.json")
    $defaultsSchema = Get-KntJson -Path (Join-Path $BaseDir "schemas/defaults.schema.json")
    $catalog = Get-DefaultCatalog
    Add-DoctorSchemaErrors $schemaErrors $Manifest $manifestSchema "project/project.json"

    $projectRoot = Join-Path $Root "project"
    $actionRelative = Get-ManifestPathValue $Manifest "actions" "contracts/actions.json"
    $surfaceRelative = Get-ManifestPathValue $Manifest "surfaces" "contracts/surfaces.json"
    $actionPath = Join-Path $projectRoot $actionRelative
    $surfacePath = Join-Path $projectRoot $surfaceRelative
    if (Test-Path -LiteralPath $actionPath -PathType Leaf) {
        Add-DoctorSchemaErrors $schemaErrors (Get-KntJson -Path $actionPath) $actionSchema $actionRelative
    }
    if (Test-Path -LiteralPath $surfacePath -PathType Leaf) {
        Add-DoctorSchemaErrors $schemaErrors (Get-KntJson -Path $surfacePath) $surfaceSchema $surfaceRelative
    }
    $defaultsRelative = Get-ManifestPathValue $Manifest "defaults" ""
    $defaultsDataForImplementation = $null
    if (-not [string]::IsNullOrWhiteSpace($defaultsRelative)) {
        $defaultsPath = Join-Path $projectRoot $defaultsRelative
        if (Test-Path -LiteralPath $defaultsPath -PathType Leaf) {
            $defaultsData = Get-KntJson -Path $defaultsPath
            $defaultsDataForImplementation = $defaultsData
            Add-DoctorSchemaErrors $schemaErrors $defaultsData $defaultsSchema $defaultsRelative
            foreach ($packProperty in @($defaultsData.packs.PSObject.Properties)) {
                try {
                    [void](Find-AnyDefaultCatalogEntry -Catalog $catalog -Identifier ([string]$packProperty.Name))
                }
                catch {
                    [void]$schemaErrors.Add("$defaultsRelative.packs.$($packProperty.Name) references an unknown Default catalog id")
                }
            }
        }
    }

    $catalogErrors = @(Test-KntSchema -Data $catalog -Schema (Get-KntJson -Path (Join-Path $BaseDir "schemas/default-catalog.schema.json")) -Path ".kinotch/defaults/catalog.json")
    foreach ($catalogError in $catalogErrors) { [void]$schemaErrors.Add($catalogError) }

    if ($schemaErrors.Count -gt 0) {
        Write-Host "[doctor] Schema validation failed" -ForegroundColor Red
        foreach ($errorText in $schemaErrors) {
            Write-Host "[doctor] $errorText" -ForegroundColor Red
        }
        $ok = $false
    }
    if (-not (Test-SelectedDefaultImplementations -DefaultsData $defaultsDataForImplementation)) { $ok = $false }
    if ($defaultsDataForImplementation) {
        $manifestSurfaces = @(Get-ManifestSurfaceIds -Manifest $Manifest)
        foreach ($packProperty in @($defaultsDataForImplementation.packs.PSObject.Properties)) {
            $state = [string](Get-KntJsonProperty $packProperty.Value "state")
            if ($state -ne "DEFAULT") { continue }
            try {
                $entry = Find-AnyDefaultCatalogEntry -Catalog $catalog -Identifier ([string]$packProperty.Name)
                $compatibilityError = Get-DefaultCompatibilityError -Entry $entry -SelectedSurfaces $manifestSurfaces
                if ($compatibilityError) {
                    Write-Host "[doctor] $compatibilityError" -ForegroundColor Red
                    $ok = $false
                }
            }
            catch {
                # Unknown catalog IDs are already reported as schema errors above.
            }
        }
    }

    $profiles = New-Object System.Collections.Generic.List[object]
    foreach ($selectedProfile in $selectedProfiles) {
        $profileFileName = $selectedProfile
        try {
            $profileEntry = Find-DefaultCatalogEntry -Catalog $catalog -Identifier $selectedProfile -Kind "surface"
            $profileFileName = Get-DefaultProfileName $profileEntry
        }
        catch {
            # Existing custom profile names remain diagnosable by their profile file.
        }
        $profilePath = Join-Path $BaseDir ("profiles/" + $profileFileName + ".json")
        if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) {
            Write-Host "[doctor] MISSING profile: $selectedProfile" -ForegroundColor Red
            $ok = $false
        }
        else {
            [void]$profiles.Add((Get-KntJson -Path $profilePath))
        }
    }

    $modules = @($Manifest.runtime.modules)
    Write-Knt ("Runtime modules: " + ($(if ($modules.Count) { $modules -join ", " } else { "(none)" })))
    $enabled = @($Manifest.surfaces.PSObject.Properties | Where-Object { $_.Value -eq $true } | ForEach-Object { $_.Name })
    Write-Knt ("Surfaces: " + ($(if ($enabled.Count) { $enabled -join ", " } else { "(none)" })))

    if ($profiles.Count -gt 0) {
        $recommendedSurfaces = @($profiles | ForEach-Object {
            $profileSurfaces = Get-KntJsonProperty $_ "surfaces"
            @($profileSurfaces.PSObject.Properties | Where-Object { $_.Value -eq $true } | ForEach-Object { $_.Name })
        } | Select-Object -Unique)
        foreach ($profileSurface in $recommendedSurfaces) {
            $manifestValue = Get-KntJsonProperty $Manifest.surfaces $profileSurface
            if ($manifestValue -ne $true) {
                Write-Host "[doctor] CONTRADICTION profile surface '$profileSurface' is not enabled in manifest." -ForegroundColor Red
                $ok = $false
            }
        }
        foreach ($manifestSurface in @($Manifest.surfaces.PSObject.Properties | Where-Object { $_.Value -eq $true })) {
            if ($manifestSurface.Name -notin $recommendedSurfaces) {
                Write-Host "[doctor] WARN manifest surface '$($manifestSurface.Name)' is not recommended by selected profile(s)." -ForegroundColor Yellow
            }
        }
    }

    foreach ($pathProperty in @($Manifest.paths.PSObject.Properties)) {
        if ([string]::IsNullOrWhiteSpace([string]$pathProperty.Value)) { continue }
        $candidate = Join-Path $projectRoot ([string]$pathProperty.Value)
        if (-not (Test-Path -LiteralPath $candidate)) {
            Write-Host "[doctor] MISSING path: $($pathProperty.Value) ($($pathProperty.Name))" -ForegroundColor Red
            $ok = $false
        }
    }

    foreach ($commandProperty in @($Manifest.commands.PSObject.Properties)) {
        $spec = Resolve-Command $Manifest $commandProperty.Name
        if ($spec -and -not (Test-Path -LiteralPath (Join-Path $Root $spec.cwd) -PathType Container)) {
            Write-Host "[doctor] MISSING command cwd: $($spec.cwd) ($($commandProperty.Name))" -ForegroundColor Red
            $ok = $false
        }
    }

    $configured = @($Manifest.commands.PSObject.Properties | Where-Object { $null -ne (Resolve-Command $Manifest $_.Name) } | ForEach-Object { $_.Name })
    Write-Knt ("Commands: " + ($(if ($configured.Count) { $configured -join ", " } else { "(none configured yet)" })))

    if ($ok) {
        Write-Host "[doctor] OK" -ForegroundColor Green
        return 0
    }
    Write-Host "[doctor] FAILED" -ForegroundColor Red
    return 1
}

function Show-Help {
    @"
KiNoTch. repository command router

Usage:
  knt.cmd <command>
  .kinotch/scripts/knt.ps1 <command>

Common commands:
  doctor      Base/project structure and schema diagnostics
  init        Create a Project from catalog Surface/Tool Defaults
              --profile minimal|web-app|cli|windows-gui|mcp|api|agent|library
              --default ci-test|generated-integrity|file-io|pwa
  migrate     Show or explicitly record catalog Default candidates
  base-check  Detect modifications in common Base files
  base-refresh Regenerate Base file hashes (repository-base only)
  setup       Project setup command
  dev         Project development command
  test        Project tests
  build       Project build
  verify      L1 Project verify command; falls back to test + build
  generated-integrity  Check selected generated artifacts against SHA-256 metadata
  pwa-check   Check selected PWA manifest, service worker, and registration helper
  smoke       Project smoke / real-entry check
  help        This help
"@ | Write-Host
}

try {
    if ($Command -eq "help" -or $Command -eq "--help" -or $Command -eq "-h") {
        Show-Help
        exit 0
    }
    if ($Command -eq "base-check") {
        if (Test-BaseFiles) { exit 0 } else { exit 1 }
    }
    if ($Command -eq "base-refresh") {
        Assert-RepositoryWriteAllowed "base-refresh"
        $refreshManifest = Get-Manifest
        if ($refreshManifest.project.type -ne "repository-base") {
            throw "base-refresh is only available for project.type repository-base"
        }
        Update-BaseIndex -Root $Root
        Write-Knt "Base index refreshed"
        exit 0
    }
    if ($Command -eq "init") {
        exit (Invoke-Init)
    }

    if ($Command -eq "migrate") {
        $migrationManifest = if (Test-Path -LiteralPath $ManifestPath -PathType Leaf) { Get-Manifest } else { $null }
        exit (Invoke-Migrate $migrationManifest)
    }

    $manifest = Get-Manifest
    if ($Command -eq "doctor") { exit (Invoke-Doctor $manifest) }
    if ($Command -eq "generated-integrity") { exit (Invoke-GeneratedIntegrityCheck) }
    if ($Command -eq "pwa-check") { exit (Invoke-PwaCheck) }

    if ($Command -eq "verify") {
        exit (Invoke-Verify $manifest)
    }

    if ($Command -in @("setup","dev","test","build","smoke","deploy")) {
        exit (Invoke-ProjectCommand $manifest $Command)
    }

    Write-Host "Unknown command: $Command" -ForegroundColor Red
    Show-Help
    exit 2
}
catch {
    Write-Host "[knt] ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}

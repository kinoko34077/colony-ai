$ErrorActionPreference = "Stop"

$TestDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent (Split-Path -Parent $TestDir)
$FixtureRoot = Join-Path $RepoRoot ".kinotch/tests/fixtures"
$PowerShellExecutable = (Get-Command pwsh -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if ([string]::IsNullOrWhiteSpace($PowerShellExecutable)) {
    $PowerShellExecutable = (Get-Command powershell -ErrorAction Stop | Select-Object -First 1).Source
}
. (Join-Path $RepoRoot ".kinotch/scripts/update-base-index.ps1")
. (Join-Path $RepoRoot ".kinotch/scripts/knt-validation.ps1")
$Passed = 0
$Failed = 0

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Assert-Equal($Expected, $Actual, [string]$Message) {
    if ($Expected -ne $Actual) {
        throw "$Message expected=[$Expected] actual=[$Actual]"
    }
}

function Get-SchemaKeywordNames {
    param($Schema)

    $names = New-Object System.Collections.Generic.List[string]
    if ((Get-KntJsonType $Schema) -ne "object") { return @() }
    foreach ($property in $Schema.PSObject.Properties) {
        [void]$names.Add([string]$property.Name)
        switch ([string]$property.Name) {
            "properties" {
                foreach ($child in @($property.Value.PSObject.Properties)) {
                    foreach ($name in @(Get-SchemaKeywordNames $child.Value)) { [void]$names.Add($name) }
                }
            }
            "additionalProperties" {
                if ((Get-KntJsonType $property.Value) -eq "object") {
                    foreach ($name in @(Get-SchemaKeywordNames $property.Value)) { [void]$names.Add($name) }
                }
            }
            "oneOf" {
                foreach ($candidate in @($property.Value)) {
                    foreach ($name in @(Get-SchemaKeywordNames $candidate)) { [void]$names.Add($name) }
                }
            }
            "items" {
                foreach ($name in @(Get-SchemaKeywordNames $property.Value)) { [void]$names.Add($name) }
            }
        }
    }
    return @($names | Select-Object -Unique)
}

function Get-FixtureProtectedPaths([string]$Root) {
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
    return @($fixed + $common | Sort-Object)
}

function Set-FixtureBaseIndex([string]$Root) {
    $entries = @(Get-FixtureProtectedPaths $Root | ForEach-Object {
        [pscustomobject]@{
            path = $_
            sha256 = Get-BaseFileHash -Path (Join-Path $Root $_)
        }
    })
    $index = [pscustomobject]@{
        schema_version = 1
        base_version = (Get-Content -Raw -LiteralPath (Join-Path $Root ".kinotch/BASE_VERSION")).Trim()
        files = $entries
    }
    $json = ConvertTo-Json $index -Depth 10
    [IO.File]::WriteAllText((Join-Path $Root ".kinotch/base-files.json"), $json + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
}

function Set-FixtureAsBase([string]$Root) {
    $manifestPath = Join-Path $Root "project/project.json"
    $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    $manifest.project.type = "repository-base"
    [IO.File]::WriteAllText($manifestPath, (ConvertTo-Json $manifest -Depth 20) + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
}

function Invoke-KntFixture {
    param(
        [string]$Name,
        [string]$Command,
        [int]$ExpectedExit = 0,
        [scriptblock]$AssertOutput,
        [scriptblock]$Prepare,
        [string[]]$Arguments
    )
    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("kinotch-base-test-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    try {
        Get-ChildItem -Force $RepoRoot | Where-Object {
            $_.Name -notin @(".git", ".superpowers")
        } | Copy-Item -Destination $tempRoot -Recurse -Force
        Remove-Item -LiteralPath (Join-Path $tempRoot "project") -Recurse -Force
        Copy-Item -LiteralPath (Join-Path $FixtureRoot $Name) -Destination (Join-Path $tempRoot "project") -Recurse -Force
        if ($Prepare) { & $Prepare $tempRoot }
        $router = Join-Path $tempRoot ".kinotch/scripts/knt.ps1"
        $invokeArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $router, "-RootOverride", $tempRoot, $Command) + @($Arguments)
        $outputLines = @(& $PowerShellExecutable @invokeArgs 2>&1)
        $exitCode = $LASTEXITCODE
        $output = $outputLines -join [Environment]::NewLine
        Assert-Equal $ExpectedExit $exitCode "$Name $Command exit code"
        if ($AssertOutput) { & $AssertOutput $tempRoot $output }
    }
    finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-KntInitFixture {
    param(
        [string[]]$Profiles,
        [string[]]$Defaults,
        [int]$ExpectedExit = 0,
        [switch]$RemoveExistingCi,
        [scriptblock]$AssertOutput
    )
    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("kinotch-init-test-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    try {
        Get-ChildItem -Force $RepoRoot | Where-Object {
            $_.Name -notin @(".git", ".superpowers")
        } | Copy-Item -Destination $tempRoot -Recurse -Force
        Remove-Item -LiteralPath (Join-Path $tempRoot "project") -Recurse -Force
        if ($RemoveExistingCi) {
            Remove-Item -LiteralPath (Join-Path $tempRoot ".github/workflows/verify.yml") -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath (Join-Path $tempRoot ".github/workflows/kinotch-default.yml") -Force -ErrorAction SilentlyContinue
        }
        $router = Join-Path $tempRoot ".kinotch/scripts/knt.ps1"
        $invokeArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $router, "-RootOverride", $tempRoot, "init")
        foreach ($profile in $Profiles) { $invokeArgs += @("--profile", $profile) }
        if ($Defaults) {
            foreach ($default in $Defaults) { $invokeArgs += @("--default", $default) }
        }
        $initOutput = @(& $PowerShellExecutable @invokeArgs 2>&1)
        $initExit = $LASTEXITCODE
        Assert-Equal $ExpectedExit $initExit "init exit code"
        if ($ExpectedExit -ne 0) {
            if ($AssertOutput) { & $AssertOutput $tempRoot ($initOutput -join [Environment]::NewLine) }
            return
        }

        $doctorOutput = @(& $PowerShellExecutable -NoProfile -ExecutionPolicy Bypass -File $router -RootOverride $tempRoot doctor 2>&1)
        $doctorExit = $LASTEXITCODE
        Assert-Equal 0 $doctorExit "generated project doctor exit code"
        if ($AssertOutput) { & $AssertOutput $tempRoot (($initOutput + $doctorOutput) -join [Environment]::NewLine) }
    }
    finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-KntShapeMigrateFixture {
    param(
        [scriptblock]$AssertOutput,
        [string]$WorkflowText = "name: Verify`nrun: npm test",
        [string]$PackageJson = '{"scripts":{"test":"node --test","build":"vite build"},"devDependencies":{"vite":"latest"}}',
        [switch]$GeneratedFile,
        [switch]$IntegrityEvidence,
        [switch]$UseBaseWorkflow,
        [switch]$VendorIntegrityEvidence,
        [switch]$NoWebAssets,
        [switch]$AgentRoot
    )
    $tempPrefix = if ($AgentRoot) { "kinotch-agent-shape-test-" } else { "kinotch-shape-test-" }
    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ($tempPrefix + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    try {
        Get-ChildItem -Force $RepoRoot | Where-Object {
            $_.Name -notin @(".git", ".superpowers", "project")
        } | Copy-Item -Destination $tempRoot -Recurse -Force
        New-Item -ItemType Directory -Path (Join-Path $tempRoot ".github/workflows") -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $tempRoot "package.json") -Value $PackageJson -NoNewline
        if (-not $UseBaseWorkflow) {
            Set-Content -LiteralPath (Join-Path $tempRoot ".github/workflows/verify.yml") -Value $WorkflowText -NoNewline
        }
        if (-not $NoWebAssets) {
            New-Item -ItemType Directory -Path (Join-Path $tempRoot "public") -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $tempRoot "public/manifest.json") -Value '{"name":"Shape","start_url":"/"}' -NoNewline
            Set-Content -LiteralPath (Join-Path $tempRoot "service-worker.js") -Value "self.addEventListener('fetch', () => {});" -NoNewline
        }
        if ($GeneratedFile) {
            New-Item -ItemType Directory -Path (Join-Path $tempRoot "src") -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $tempRoot "src/generated-output.js") -Value "export default 'generated';" -NoNewline
        }
        if ($IntegrityEvidence) {
            New-Item -ItemType Directory -Path (Join-Path $tempRoot "scripts") -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $tempRoot "scripts/integrity-check.ps1") -Value "Get-FileHash -Algorithm SHA256; stale check" -NoNewline
        }
        if ($VendorIntegrityEvidence) {
            New-Item -ItemType Directory -Path (Join-Path $tempRoot "public/pdfjs/src/core") -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $tempRoot "public/pdfjs/src/core/calculate_sha256.js") -Value "function calculateSHA256() {}; stale reference" -NoNewline
        }
        $router = Join-Path $tempRoot ".kinotch/scripts/knt.ps1"
        $baseSource = Join-Path $RepoRoot ".kinotch"
        $invokeArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $router, "-RootOverride", $tempRoot, "-BaseOverride", $baseSource, "migrate")
        $outputLines = @(& $PowerShellExecutable @invokeArgs 2>&1)
        $exitCode = $LASTEXITCODE
        Assert-Equal 0 $exitCode "shape migrate exit code"
        if ($AssertOutput) { & $AssertOutput $tempRoot ($outputLines -join [Environment]::NewLine) }
    }
    finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-KntExternalBaseFixture {
    param(
        [string]$Command,
        [string[]]$Arguments,
        [string]$FixtureName,
        [int]$ExpectedExit = 0,
        [scriptblock]$Prepare,
        [scriptblock]$AssertOutput
    )
    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("kinotch-external-base-test-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    try {
        if ($FixtureName) {
            Copy-Item -LiteralPath (Join-Path $FixtureRoot $FixtureName) -Destination (Join-Path $tempRoot "project") -Recurse -Force
        }
        if ($Prepare) { & $Prepare $tempRoot }
        $router = Join-Path $RepoRoot ".kinotch/scripts/knt.ps1"
        $baseSource = Join-Path $RepoRoot ".kinotch"
        $invokeArgs = @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $router,
            "-RootOverride", $tempRoot, "-BaseOverride", $baseSource, $Command
        ) + @($Arguments)
        $outputLines = @(& $PowerShellExecutable @invokeArgs 2>&1)
        $exitCode = $LASTEXITCODE
        $output = $outputLines -join [Environment]::NewLine
        Assert-Equal $ExpectedExit $exitCode "external Base $Command exit code"
        if ($AssertOutput) { & $AssertOutput $tempRoot $output }
    }
    finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-TestCase([string]$Name, [scriptblock]$Body) {
    try {
        & $Body
        $script:Passed++
        Write-Host "[PASS] $Name" -ForegroundColor Green
    }
    catch {
        $script:Failed++
        Write-Host "[FAIL] $Name :: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Invoke-TestCase "Windows-style repository path is canonicalized" {
    $actual = ConvertTo-BaseRelativePath -Root "C:\repo" -AbsolutePath "C:\repo\.kinotch\README_BASE.md"
    Assert-Equal ".kinotch/README_BASE.md" $actual "Windows-style relative path"
}

Invoke-TestCase "Unix-style repository path is canonicalized" {
    $actual = ConvertTo-BaseRelativePath -Root "/home/user/repo" -AbsolutePath "/home/user/repo/.kinotch/README_BASE.md"
    Assert-Equal ".kinotch/README_BASE.md" $actual "Unix-style relative path"
}

Invoke-TestCase "Protected paths never begin with a separator" {
    $paths = @(Get-BaseProtectedPaths -Root $RepoRoot)
    Assert-True (@($paths | Where-Object { $_ -match "^[\\/]" }).Count -eq 0) "protected path has a leading separator"
}

Invoke-TestCase "Protected paths include hidden Base files" {
    $paths = @(Get-BaseProtectedPaths -Root $RepoRoot)
    Assert-True ($paths -contains ".kinotch/templates/project/.gitignore") "hidden template file is not protected"
}

Invoke-TestCase "Base file hash is line-ending stable" {
    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("kinotch-hash-test-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    try {
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        $crlfPath = Join-Path $tempRoot "crlf.txt"
        $lfPath = Join-Path $tempRoot "lf.txt"
        [IO.File]::WriteAllText($crlfPath, "alpha`r`nbeta`r`n", $utf8)
        [IO.File]::WriteAllText($lfPath, "alpha`nbeta`n", $utf8)
        Assert-Equal (Get-BaseFileHash $lfPath) (Get-BaseFileHash $crlfPath) "line-ending stable Base hash"
    }
    finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-TestCase "Protected paths and Base index use canonical separators" {
    $paths = @(Get-BaseProtectedPaths -Root $RepoRoot)
    Assert-True (@($paths | Where-Object { $_ -match "\\" }).Count -eq 0) "protected path contains a Windows separator"
    $index = Get-Content -Raw -Encoding UTF8 (Join-Path $RepoRoot ".kinotch/base-files.json") | ConvertFrom-Json
    $indexedPaths = @($index.files | ForEach-Object { [string]$_.path })
    Assert-True (@($indexedPaths | Where-Object { $_ -match "^[\\/]" }).Count -eq 0) "index path has a leading separator"
    Assert-True (@($indexedPaths | Where-Object { $_ -match "\\" }).Count -eq 0) "index path contains a Windows separator"
}

Invoke-TestCase "valid minimal project passes doctor" {
    Invoke-KntFixture -Name "valid-minimal" -Command "doctor" -ExpectedExit 0
}
Invoke-TestCase "valid command string remains accepted" {
    Invoke-KntFixture -Name "valid-minimal" -Command "doctor" -ExpectedExit 0
}
Invoke-TestCase "valid command object remains accepted" {
    Invoke-KntFixture -Name "valid-minimal" -Command "doctor" -ExpectedExit 0 -Prepare {
        param($root)
        $manifestPath = Join-Path $root "project/project.json"
        $manifest = Get-Content -Raw -Encoding UTF8 $manifestPath | ConvertFrom-Json
        $manifest.commands.test = [pscustomobject]@{ run = "Write-Output valid"; cwd = "." }
        [IO.File]::WriteAllText($manifestPath, (ConvertTo-Json $manifest -Depth 20) + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
    }
}
Invoke-TestCase "valid structured command object remains accepted" {
    Invoke-KntFixture -Name "valid-minimal" -Command "doctor" -ExpectedExit 0 -Prepare {
        param($root)
        $manifestPath = Join-Path $root "project/project.json"
        $manifest = Get-Content -Raw -Encoding UTF8 $manifestPath | ConvertFrom-Json
        $manifest.commands.test = [pscustomobject]@{
            exec = "pwsh"
            args = @("-NoProfile", "-Command", "Write-Output valid")
            cwd = "."
            forward_args = $false
        }
        [IO.File]::WriteAllText($manifestPath, (ConvertTo-Json $manifest -Depth 20) + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
    }
}
Invoke-TestCase "schema-valued additional command property is validated" {
    Invoke-KntFixture -Name "valid-minimal" -Command "doctor" -ExpectedExit 1 -Prepare {
        param($root)
        $manifestPath = Join-Path $root "project/project.json"
        $manifest = Get-Content -Raw -Encoding UTF8 $manifestPath | ConvertFrom-Json
        $manifest.commands.test = 123
        [IO.File]::WriteAllText($manifestPath, (ConvertTo-Json $manifest -Depth 20) + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
    } -AssertOutput {
        param($root, $output)
        Assert-True ($output -match "project/project.json.commands.test") "command schema path was not reported"
        Assert-True ($output -match "commands.test has type integer") "command type error was not reported"
    }
}
Invoke-TestCase "schema-valued additional path property is validated" {
    Invoke-KntFixture -Name "valid-minimal" -Command "doctor" -ExpectedExit 1 -Prepare {
        param($root)
        $manifestPath = Join-Path $root "project/project.json"
        $manifest = Get-Content -Raw -Encoding UTF8 $manifestPath | ConvertFrom-Json
        $manifest.paths.docs = 123
        [IO.File]::WriteAllText($manifestPath, (ConvertTo-Json $manifest -Depth 20) + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
    } -AssertOutput {
        param($root, $output)
        Assert-True ($output -match "project/project.json.paths.docs") "path schema path was not reported"
    }
}
Invoke-TestCase "invalid Default state is rejected by doctor" {
    Invoke-KntFixture -Name "valid-minimal" -Command "doctor" -ExpectedExit 1 -Prepare {
        param($root)
        $manifestPath = Join-Path $root "project/project.json"
        $manifest = Get-Content -Raw -Encoding UTF8 $manifestPath | ConvertFrom-Json
        $manifest.paths | Add-Member -NotePropertyName defaults -NotePropertyValue "defaults.json" -Force
        [IO.File]::WriteAllText($manifestPath, (ConvertTo-Json $manifest -Depth 20) + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
        $defaults = [pscustomobject]@{
            schema_version = 1
            packs = [pscustomobject]@{ cli = [pscustomobject]@{ state = "MAYBE" } }
        }
        [IO.File]::WriteAllText((Join-Path $root "project/defaults.json"), (ConvertTo-Json $defaults -Depth 10) + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
    } -AssertOutput {
        param($root, $output)
        Assert-True ($output -match "defaults.*state|state.*DEFAULT") "invalid Default state was not reported"
    }
}
Invoke-TestCase "doctor rejects a selected Default without its implementation" {
    Invoke-KntFixture -Name "valid-minimal" -Command "doctor" -ExpectedExit 1 -Prepare {
        param($root)
        $manifestPath = Join-Path $root "project/project.json"
        $manifest = Get-Content -Raw -Encoding UTF8 $manifestPath | ConvertFrom-Json
        $manifest.paths | Add-Member -NotePropertyName defaults -NotePropertyValue "defaults.json" -Force
        [IO.File]::WriteAllText($manifestPath, (ConvertTo-Json $manifest -Depth 20) + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
        $defaults = [pscustomobject]@{
            schema_version = 1
            packs = [pscustomobject]@{ pwa = [pscustomobject]@{ state = "DEFAULT" } }
        }
        [IO.File]::WriteAllText((Join-Path $root "project/defaults.json"), (ConvertTo-Json $defaults -Depth 10) + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
    } -AssertOutput {
        param($root, $output)
        Assert-True ($output -match "MISSING implementation.*pwa") "missing Default implementation was not reported"
    }
}
Invoke-TestCase "init creates a doctor-valid multi-profile Project" {
    Invoke-KntInitFixture -Profiles @("cli", "mcp") -AssertOutput {
        param($root, $output)
        $manifest = Get-Content -Raw -Encoding UTF8 (Join-Path $root "project/project.json") | ConvertFrom-Json
        Assert-Equal "cli" $manifest.profile "primary profile"
        Assert-Equal 2 @($manifest.profiles).Count "selected profile count"
        Assert-True (@($manifest.profiles) -contains "mcp") "mcp profile was not recorded"
        Assert-True ($manifest.surfaces.cli -eq $true -and $manifest.surfaces.mcp -eq $true) "selected surfaces were not enabled"
        $defaults = Get-Content -Raw -Encoding UTF8 (Join-Path $root "project/defaults.json") | ConvertFrom-Json
        Assert-Equal "DEFAULT" $defaults.packs.cli.state "cli Default state"
        Assert-Equal "DEFAULT" $defaults.packs.mcp.state "mcp Default state"
        Assert-True (Test-Path (Join-Path $root "README.md")) "root README was not generated"
        Assert-True (Test-Path (Join-Path $root "project/src/README.md")) "project source placeholder was not generated"
        Assert-True (Test-Path (Join-Path $root "project/tests/README.md")) "project test placeholder was not generated"
    }
}
Invoke-TestCase "Tool Defaults require a compatible selected Surface" {
    Invoke-KntInitFixture -Profiles @("minimal") -Defaults @("pwa") -ExpectedExit 2 -AssertOutput {
        param($root, $output)
        Assert-True ($output -match "not compatible|requires.*Surface") "minimal + pwa was accepted"
    }
    Invoke-KntInitFixture -Profiles @("cli") -Defaults @("pwa") -ExpectedExit 2 -AssertOutput {
        param($root, $output)
        Assert-True ($output -match "not compatible|requires.*Surface") "cli + pwa was accepted"
    }
    Invoke-KntInitFixture -Profiles @("web-app") -Defaults @("pwa") -AssertOutput {
        param($root, $output)
        $defaults = Get-Content -Raw -Encoding UTF8 (Join-Path $root "project/defaults.json") | ConvertFrom-Json
        Assert-Equal "DEFAULT" $defaults.packs.pwa.state "web-app + pwa state"
    }
}
Invoke-TestCase "init accepts all catalog surface profiles without Runtime injection" {
    Invoke-KntInitFixture -Profiles @("minimal", "web-app", "cli", "windows-gui", "mcp", "api", "agent", "library") -AssertOutput {
        param($root, $output)
        $manifest = Get-Content -Raw -Encoding UTF8 (Join-Path $root "project/project.json") | ConvertFrom-Json
        Assert-Equal 8 @($manifest.profiles).Count "all selected profile count"
        Assert-Equal 0 @($manifest.runtime.modules).Count "Runtime modules were injected by profile selection"
        Assert-True ($manifest.profiles -contains "web-app") "web-app profile was not recorded"
        Assert-True ($manifest.surfaces.web -eq $true) "web surface was not enabled"
        $defaults = Get-Content -Raw -Encoding UTF8 (Join-Path $root "project/defaults.json") | ConvertFrom-Json
        Assert-Equal "DEFAULT" $defaults.packs.PSObject.Properties["web-app"].Value.state "web-app Default state"
        Assert-Equal "DEFAULT" $defaults.packs.windows.state "windows Default state"
    }
}
Invoke-TestCase "surface Defaults materialize safe CLI, Windows, MCP, and API helpers" {
    Invoke-KntInitFixture -Profiles @("cli", "windows-gui", "mcp", "api") -AssertOutput {
        param($root, $output)
        foreach ($relative in @(
            "project/tools/cli-default.ps1",
            "project/tools/windows-shell.ps1",
            "project/contracts/mcp-tools.json",
            "project/contracts/api-error-envelope.json"
        )) {
            Assert-True (Test-Path -LiteralPath (Join-Path $root $relative) -PathType Leaf) "missing surface Default implementation: $relative"
        }
        Assert-True ($output -match "Surface Default 'cli' added") "CLI surface Default was not materialized"
        Assert-True ($output -match "Surface Default 'api' added") "API surface Default was not materialized"
    }
}
Invoke-TestCase "init records selected Tool Defaults from the catalog" {
    Invoke-KntInitFixture -Profiles @("web-app") -Defaults @("pwa") -AssertOutput {
        param($root, $output)
        $defaults = Get-Content -Raw -Encoding UTF8 (Join-Path $root "project/defaults.json") | ConvertFrom-Json
        Assert-Equal "DEFAULT" $defaults.packs.pwa.state "pwa Default state"
        $manifest = Get-Content -Raw -Encoding UTF8 (Join-Path $root "project/project.json") | ConvertFrom-Json
        Assert-Equal 0 @($manifest.runtime.modules).Count "Tool Default injected Runtime modules"
    }
}
Invoke-TestCase "init materializes safe Default implementations" {
    Invoke-KntInitFixture -Profiles @("web-app") -Defaults @("ci-test", "pwa", "generated-integrity", "file-io") -RemoveExistingCi -AssertOutput {
        param($root, $output)
        $ciPath = Join-Path $root ".github/workflows/kinotch-default.yml"
        Assert-True (Test-Path $ciPath) "ci-test workflow was not generated"
        Assert-True ((Get-Content -Raw -Encoding UTF8 $ciPath) -match "knt\.ps1 setup") "ci-test workflow has no setup step"
        $pwaManifestPath = Join-Path $root "project/public/manifest.webmanifest"
        Assert-True (Test-Path $pwaManifestPath) "PWA manifest was not generated"
        $pwaManifest = Get-Content -Raw -Encoding UTF8 $pwaManifestPath | ConvertFrom-Json
        Assert-Equal "." $pwaManifest.start_url "PWA manifest must use a relative start_url"
        Assert-True (Test-Path (Join-Path $root "project/public/service-worker.js")) "service worker was not generated"
        Assert-True (Test-Path (Join-Path $root "project/src/pwa/register.js")) "PWA registration helper was not generated"
        Assert-True (Test-Path (Join-Path $root "project/generated-integrity.json")) "generated-integrity config was not generated"
        Assert-True (Test-Path (Join-Path $root "project/tools/check-generated.ps1")) "generated-integrity checker was not generated"
        Assert-True (Test-Path (Join-Path $root "project/tools/update-generated-integrity.ps1")) "generated-integrity updater was not generated"
        $fileIo = Get-Content -Raw -Encoding UTF8 (Join-Path $root "project/contracts/file-io.json") | ConvertFrom-Json
        Assert-Equal "UTF-8 text helper only; binary Projects provide their own byte/path callback." $fileIo.helper_scope "file-io helper scope"
        $router = Join-Path $root ".kinotch/scripts/knt.ps1"
        @(& $PowerShellExecutable -NoProfile -ExecutionPolicy Bypass -File $router -RootOverride $root pwa-check 2>&1) | Out-Null
        Assert-Equal 0 $LASTEXITCODE "pwa-check exit code"
        @(& $PowerShellExecutable -NoProfile -ExecutionPolicy Bypass -File $router -RootOverride $root generated-integrity 2>&1) | Out-Null
        Assert-Equal 0 $LASTEXITCODE "generated-integrity exit code"
        @(& $PowerShellExecutable -NoProfile -ExecutionPolicy Bypass -File $router -RootOverride $root verify 2>&1) | Out-Null
        Assert-Equal 0 $LASTEXITCODE "verify Default integration exit code"
        Set-Content -LiteralPath (Join-Path $root "project/source.txt") -Value "source-v1" -NoNewline
        Set-Content -LiteralPath (Join-Path $root "project/generated.txt") -Value "generated-v1" -NoNewline
        $updater = Join-Path $root "project/tools/update-generated-integrity.ps1"
        @(& $PowerShellExecutable -NoProfile -ExecutionPolicy Bypass -File $updater -Root (Join-Path $root "project") -Source source.txt -Artifact generated.txt -Generator project-owned 2>&1) | Out-Null
        Assert-Equal 0 $LASTEXITCODE "generated-integrity updater exit code"
        $integrityConfig = Get-Content -Raw -Encoding UTF8 (Join-Path $root "project/generated-integrity.json") | ConvertFrom-Json
        Assert-True ($integrityConfig.entries[0].source_sha256 -match "^[0-9a-f]{64}$") "source hash was not recorded"
        @(& $PowerShellExecutable -NoProfile -ExecutionPolicy Bypass -File $router generated-integrity 2>&1) | Out-Null
        Assert-Equal 0 $LASTEXITCODE "generated-integrity fresh source exit code"
        Set-Content -LiteralPath (Join-Path $root "project/source.txt") -Value "source-v2" -NoNewline
        @(& $PowerShellExecutable -NoProfile -ExecutionPolicy Bypass -File $router -RootOverride $root generated-integrity 2>&1) | Out-Null
        Assert-Equal 1 $LASTEXITCODE "generated-integrity source-stale exit code"
    }
}
Invoke-TestCase "file and generated-integrity Defaults reject paths outside Project root" {
    Invoke-KntInitFixture -Profiles @("web-app") -Defaults @("file-io", "generated-integrity") -AssertOutput {
        param($root, $output)
        $projectRoot = Join-Path $root "project"
        $outsideRoot = Join-Path (Split-Path -Parent $root) ((Split-Path -Leaf $root) + "-other")
        New-Item -ItemType Directory -Path $outsideRoot -Force | Out-Null
        $outsidePath = Join-Path $outsideRoot "outside.txt"
        Set-Content -LiteralPath $outsidePath -Value "outside" -NoNewline
        $updater = Join-Path $projectRoot "tools/update-generated-integrity.ps1"
        @(& $PowerShellExecutable -NoProfile -ExecutionPolicy Bypass -File $updater -Root $projectRoot -Source "..\outside.txt" -Artifact "generated.txt" -Generator test 2>&1) | Out-Null
        Assert-True ($LASTEXITCODE -ne 0) "generated-integrity updater accepted a parent path"
        $fileIo = Join-Path $projectRoot "tools/file-io.ps1"
        @(& $PowerShellExecutable -NoProfile -ExecutionPolicy Bypass -File $fileIo -Action save -Path "..\outside.txt" -Content "changed" -Root $projectRoot 2>&1) | Out-Null
        Assert-True ($LASTEXITCODE -ne 0) "file-io accepted a parent path"
        $absolutePath = Join-Path $outsideRoot "absolute.txt"
        @(& $PowerShellExecutable -NoProfile -ExecutionPolicy Bypass -File $fileIo -Action save -Path $absolutePath -Content "changed" -Root $projectRoot 2>&1) | Out-Null
        Assert-True ($LASTEXITCODE -ne 0) "file-io accepted an absolute path"
        Assert-Equal "outside" (Get-Content -Raw -Encoding UTF8 $outsidePath) "outside file was modified"
        Remove-Item -LiteralPath $outsideRoot -Recurse -Force
    }
}
Invoke-TestCase "unknown catalog Default is rejected" {
    Invoke-KntInitFixture -Profiles @("web-app") -Defaults @("not-a-default") -ExpectedExit 2 -AssertOutput {
        param($root, $output)
        Assert-True ($output -match "Unknown.*Default|catalog") "unknown Default was not reported"
    }
}
Invoke-TestCase "init refuses to overwrite an existing Project" {
    $router = Join-Path $RepoRoot ".kinotch/scripts/knt.ps1"
    $output = @(& $PowerShellExecutable -NoProfile -ExecutionPolicy Bypass -File $router init --profile cli 2>&1)
    $exitCode = $LASTEXITCODE
    Assert-Equal 1 $exitCode "init refusal exit code"
    Assert-True (($output -join [Environment]::NewLine) -match "already initialized|project/project.json") "init refusal was not reported"
}
Invoke-TestCase "migrate dry-run reports candidates without writing" {
    Invoke-KntFixture -Name "valid-minimal" -Command "migrate" -Arguments @("--profile", "cli") -ExpectedExit 0 -AssertOutput {
        param($root, $output)
        Assert-True ($output -match "Candidate Default Pack.*cli") "migrate candidate was not reported"
        Assert-True ($output -match "no files changed|--apply") "migrate dry-run warning was not reported"
        Assert-True (-not (Test-Path (Join-Path $root "project/defaults.json"))) "migrate dry-run wrote a file"
    }
}
Invoke-TestCase "migrate rejects removed Tool Default aliases" {
    Invoke-KntFixture -Name "valid-minimal" -Command "migrate" -Arguments @("--default", "verify") -ExpectedExit 2 -AssertOutput {
        param($root, $output)
        Assert-True ($output -match "Unknown.*Default|catalog") "removed verify alias was accepted"
        Assert-True (-not (Test-Path (Join-Path $root "project/defaults.json"))) "Tool Default dry-run wrote a file"
    }
}
Invoke-TestCase "migrate detects Web, PWA, and CI shape without a Base Manifest" {
    Invoke-KntShapeMigrateFixture -AssertOutput {
        param($root, $output)
        Assert-True ($output -match "web-app") "web-app shape was not detected"
        Assert-True ($output -match "ci-test") "ci-test shape was not detected"
        Assert-True ($output -match "pwa") "pwa shape was not detected"
        Assert-True ($output -match "Candidate Default Pack 'ci-test': state OVERRIDE") "existing CI implementation was not classified as OVERRIDE"
        Assert-True ($output -match "Candidate Default Pack 'pwa': state OVERRIDE") "existing PWA implementation was not classified as OVERRIDE"
        Assert-True ($output -match "Candidate Default Pack 'web-app': state OVERRIDE") "existing Web implementation was not classified as OVERRIDE"
        Assert-True ($output -notmatch "Detected Surface candidates:.*cli") "test/build scripts were misclassified as CLI"
        Assert-True ($output -notmatch "Detected Tool candidates:.*verify") "L1 verify was misreported as a Tool Default"
        Assert-True ($output -match "Dry run") "shape migrate was not dry-run"
    }
}
Invoke-TestCase "shape probe distinguishes deploy-only and verification CI" {
    Invoke-KntShapeMigrateFixture -WorkflowText "name: Deploy`nrun: wrangler deploy" -AssertOutput {
        param($root, $output)
        Assert-True ($output -match "Candidate Default Pack 'ci-test': state DEFAULT") "deploy-only workflow was marked OVERRIDE"
    }
    Invoke-KntShapeMigrateFixture -WorkflowText "name: Verify`nrun: npm test" -AssertOutput {
        param($root, $output)
        Assert-True ($output -match "Candidate Default Pack 'ci-test': state OVERRIDE") "verification workflow was not marked OVERRIDE"
    }
}
Invoke-TestCase "shape probe ignores the Base common verification workflow" {
    Invoke-KntShapeMigrateFixture -UseBaseWorkflow -AssertOutput {
        param($root, $output)
        Assert-True ($output -notmatch "Candidate Default Pack 'ci-test'") "Base common workflow was misclassified as an L2 ci-test Default"
    }
}
Invoke-TestCase "shape probe distinguishes generated files from integrity checks" {
    Invoke-KntShapeMigrateFixture -GeneratedFile -AssertOutput {
        param($root, $output)
        Assert-True ($output -match "Candidate Default Pack 'generated-integrity': state DEFAULT") "generated file was incorrectly marked OVERRIDE"
    }
    Invoke-KntShapeMigrateFixture -GeneratedFile -IntegrityEvidence -AssertOutput {
        param($root, $output)
        Assert-True ($output -match "Candidate Default Pack 'generated-integrity': state OVERRIDE") "integrity evidence was not marked OVERRIDE"
    }
}
Invoke-TestCase "shape probe ignores vendored public integrity text" {
    Invoke-KntShapeMigrateFixture -VendorIntegrityEvidence -AssertOutput {
        param($root, $output)
        Assert-True ($output -notmatch "Candidate Default Pack 'generated-integrity'") "vendored public integrity text was misclassified as Project generated-integrity"
    }
}
Invoke-TestCase "shape probe filters incompatible Tool evidence" {
    Invoke-KntShapeMigrateFixture -AgentRoot -NoWebAssets -UseBaseWorkflow -IntegrityEvidence -PackageJson '{"scripts":{"test":"python -m unittest"}}' -AssertOutput {
        param($root, $output)
        Assert-True ($output -match "Detected Surface candidates:.*agent") "Agent shape was not detected"
        Assert-True ($output -notmatch "Candidate Default Pack 'generated-integrity'") "incompatible generated-integrity evidence was offered to Agent shape"
    }
}
Invoke-TestCase "shape probe does not treat Wrangler-only Web as API" {
    Invoke-KntShapeMigrateFixture -PackageJson '{"scripts":{"test":"node --test","build":"npm run build"},"devDependencies":{"wrangler":"latest"}}' -AssertOutput {
        param($root, $output)
        Assert-True ($output -match "Detected Surface candidates:.*web-app") "Wrangler-only Web surface was not detected"
        Assert-True ($output -notmatch "Detected Surface candidates:.*api") "Wrangler-only Web project was misclassified as API"
    }
}
Invoke-TestCase "shape probe still detects Hono API" {
    Invoke-KntShapeMigrateFixture -PackageJson '{"dependencies":{"hono":"latest"}}' -AssertOutput {
        param($root, $output)
        Assert-True ($output -match "Detected Surface candidates:.*api") "Hono API surface was not detected"
    }
}
Invoke-TestCase "migrate apply preserves Project override and adds missing pack" {
    Invoke-KntFixture -Name "valid-minimal" -Command "migrate" -Arguments @("--apply", "--profile", "cli", "--profile", "mcp") -ExpectedExit 0 -Prepare {
        param($root)
        $manifestPath = Join-Path $root "project/project.json"
        $manifest = Get-Content -Raw -Encoding UTF8 $manifestPath | ConvertFrom-Json
        $manifest.paths | Add-Member -NotePropertyName defaults -NotePropertyValue "defaults.json" -Force
        [IO.File]::WriteAllText($manifestPath, (ConvertTo-Json $manifest -Depth 20) + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
        $defaults = [pscustomobject]@{
            schema_version = 1
            packs = [pscustomobject]@{
                cli = [pscustomobject]@{ state = "OVERRIDE"; notes = "Project-owned CLI" }
                mcp = [pscustomobject]@{ state = "DISABLED"; notes = "Project does not expose MCP" }
            }
        }
        [IO.File]::WriteAllText((Join-Path $root "project/defaults.json"), (ConvertTo-Json $defaults -Depth 10) + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
    } -AssertOutput {
        param($root, $output)
        $defaults = Get-Content -Raw -Encoding UTF8 (Join-Path $root "project/defaults.json") | ConvertFrom-Json
        Assert-Equal "OVERRIDE" $defaults.packs.cli.state "existing override state"
        Assert-Equal "DISABLED" $defaults.packs.mcp.state "existing disabled state"
        Assert-True ($output -match "preserved.*OVERRIDE") "override preservation was not reported"
    }
}
Invoke-TestCase "migrate apply materializes missing safe Tool Default files" {
    Invoke-KntFixture -Name "valid-minimal" -Command "migrate" -Arguments @("--apply", "--default", "pwa") -ExpectedExit 0 -Prepare {
        param($root)
        $manifestPath = Join-Path $root "project/project.json"
        $manifest = Get-Content -Raw -Encoding UTF8 $manifestPath | ConvertFrom-Json
        $manifest.surfaces.web = $true
        [IO.File]::WriteAllText($manifestPath, (ConvertTo-Json $manifest -Depth 20) + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
    } -AssertOutput {
        param($root, $output)
        Assert-True (Test-Path -LiteralPath (Join-Path $root "project/public/manifest.webmanifest") -PathType Leaf) "migrate apply did not materialize PWA manifest"
        Assert-True (Test-Path -LiteralPath (Join-Path $root "project/tools/pwa-check.ps1") -PathType Leaf) "migrate apply did not materialize PWA checker"
        $defaults = Get-Content -Raw -Encoding UTF8 (Join-Path $root "project/defaults.json") | ConvertFrom-Json
        Assert-Equal "DEFAULT" $defaults.packs.pwa.state "migrate applied Tool Default state"
        Assert-True ($output -match "Tool Default 'pwa' added") "migrate apply did not report materialized PWA files"
    }
}
Invoke-TestCase "migrate apply records conflicting Default files as OVERRIDE" {
    Invoke-KntFixture -Name "valid-minimal" -Command "migrate" -Arguments @("--apply", "--default", "pwa") -ExpectedExit 0 -Prepare {
        param($root)
        $manifestPath = Join-Path $root "project/project.json"
        $manifest = Get-Content -Raw -Encoding UTF8 $manifestPath | ConvertFrom-Json
        $manifest.surfaces.web = $true
        [IO.File]::WriteAllText($manifestPath, (ConvertTo-Json $manifest -Depth 20) + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
        $manifestPath = Join-Path $root "project/public/manifest.webmanifest"
        New-Item -ItemType Directory -Path (Split-Path -Parent $manifestPath) -Force | Out-Null
        Set-Content -LiteralPath $manifestPath -Value '{"name":"Project-owned","start_url":"/custom"}' -NoNewline
    } -AssertOutput {
        param($root, $output)
        $defaults = Get-Content -Raw -Encoding UTF8 (Join-Path $root "project/defaults.json") | ConvertFrom-Json
        Assert-Equal "OVERRIDE" $defaults.packs.pwa.state "conflicting PWA Default state"
        $manifest = Get-Content -Raw -Encoding UTF8 (Join-Path $root "project/public/manifest.webmanifest") | ConvertFrom-Json
        Assert-Equal "/custom" $manifest.start_url "existing PWA file was overwritten"
        Assert-True ($output -match "conflict|OVERRIDE") "materialization conflict was not reported"
    }
}
Invoke-TestCase "migrate rejects an incompatible Tool Default from existing Manifest surfaces" {
    Invoke-KntFixture -Name "valid-minimal" -Command "migrate" -Arguments @("--apply", "--default", "pwa") -ExpectedExit 2 -Prepare {
        param($root)
        $manifestPath = Join-Path $root "project/project.json"
        $manifest = Get-Content -Raw -Encoding UTF8 $manifestPath | ConvertFrom-Json
        $manifest.surfaces.cli = $true
        [IO.File]::WriteAllText($manifestPath, (ConvertTo-Json $manifest -Depth 20) + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
    } -AssertOutput {
        param($root, $output)
        Assert-True ($output -match "not compatible") "migrate accepted an incompatible Tool Default"
        Assert-True (-not (Test-Path (Join-Path $root "project/defaults.json"))) "incompatible migrate wrote Default state"
    }
}
Invoke-TestCase "doctor rejects a hand-edited incompatible DEFAULT Tool" {
    Invoke-KntFixture -Name "valid-minimal" -Command "doctor" -ExpectedExit 1 -Prepare {
        param($root)
        $manifestPath = Join-Path $root "project/project.json"
        $manifest = Get-Content -Raw -Encoding UTF8 $manifestPath | ConvertFrom-Json
        $manifest.paths | Add-Member -NotePropertyName defaults -NotePropertyValue "defaults.json" -Force
        [IO.File]::WriteAllText($manifestPath, (ConvertTo-Json $manifest -Depth 20) + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
        $defaults = [pscustomobject]@{
            schema_version = 1
            packs = [pscustomobject]@{ pwa = [pscustomobject]@{ state = "DEFAULT" } }
        }
        [IO.File]::WriteAllText((Join-Path $root "project/defaults.json"), (ConvertTo-Json $defaults -Depth 10) + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
    } -AssertOutput {
        param($root, $output)
        Assert-True ($output -match "not compatible|incompatible.*Surface") "doctor accepted an incompatible DEFAULT Tool"
    }
}
Invoke-TestCase "external BaseOverride rejects init and migrate writes" {
    Invoke-KntExternalBaseFixture -Command "init" -Arguments @("--profile", "web-app") -ExpectedExit 2 -AssertOutput {
        param($root, $output)
        Assert-True ($output -match "repository-local.*\.kinotch|read-only") "external Base init write was not rejected"
        Assert-True (-not (Test-Path (Join-Path $root "project"))) "external Base init created Project files"
    }
    Invoke-KntExternalBaseFixture -FixtureName "valid-minimal" -Command "migrate" -Arguments @("--apply", "--default", "ci-test") -ExpectedExit 2 -Prepare {
        param($root)
        $manifestPath = Join-Path $root "project/project.json"
        $manifest = Get-Content -Raw -Encoding UTF8 $manifestPath | ConvertFrom-Json
        $manifest.surfaces.web = $true
        [IO.File]::WriteAllText($manifestPath, (ConvertTo-Json $manifest -Depth 20) + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
    } -AssertOutput {
        param($root, $output)
        Assert-True ($output -match "repository-local.*\.kinotch|read-only") "external Base migrate write was not rejected"
        Assert-True (-not (Test-Path (Join-Path $root "project/defaults.json"))) "external Base migrate wrote Default state"
    }
}
Invoke-TestCase "manifest-less migrate apply is rejected before writing" {
    Invoke-KntExternalBaseFixture -Command "migrate" -Arguments @("--apply", "--profile", "web-app") -ExpectedExit 2 -AssertOutput {
        param($root, $output)
        Assert-True ($output -match "existing Project Manifest|repository-local.*\.kinotch|read-only") "manifest-less apply rejection was not reported"
        Assert-True (-not (Test-Path (Join-Path $root "project/defaults.json"))) "manifest-less apply wrote Default state"
    }
}
Invoke-TestCase "doctor rejects an unknown Default catalog id" {
    Invoke-KntFixture -Name "valid-minimal" -Command "doctor" -ExpectedExit 1 -Prepare {
        param($root)
        $manifestPath = Join-Path $root "project/project.json"
        $manifest = Get-Content -Raw -Encoding UTF8 $manifestPath | ConvertFrom-Json
        $manifest.paths | Add-Member -NotePropertyName defaults -NotePropertyValue "defaults.json" -Force
        [IO.File]::WriteAllText($manifestPath, (ConvertTo-Json $manifest -Depth 20) + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
        $defaults = [pscustomobject]@{
            schema_version = 1
            packs = [pscustomobject]@{ not_a_default = [pscustomobject]@{ state = "DEFAULT" } }
        }
        [IO.File]::WriteAllText((Join-Path $root "project/defaults.json"), (ConvertTo-Json $defaults -Depth 10) + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
    } -AssertOutput {
        param($root, $output)
        Assert-True ($output -match "Unknown.*Default|catalog") "unknown catalog Default was not reported by doctor"
    }
}
Invoke-TestCase "doctor rejects duplicate Default catalog identifiers and aliases" {
    Invoke-KntFixture -Name "valid-minimal" -Command "doctor" -ExpectedExit 2 -Prepare {
        param($root)
        $catalogPath = Join-Path $root ".kinotch/defaults/catalog.json"
        $catalog = Get-Content -Raw -Encoding UTF8 $catalogPath | ConvertFrom-Json
        $catalog.defaults[1].aliases = @("cli")
        [IO.File]::WriteAllText($catalogPath, (ConvertTo-Json $catalog -Depth 20) + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
    } -AssertOutput {
        param($root, $output)
        Assert-True ($output -match "semantic|alias|duplicate|collision") "catalog alias collision was not rejected"
    }
}
Invoke-TestCase "removed candidate Defaults are rejected" {
    foreach ($removed in @("pages", "secrets", "local-app", "verify-binding")) {
        Invoke-KntFixture -Name "valid-minimal" -Command "migrate" -Arguments @("--default", $removed) -ExpectedExit 2 -AssertOutput {
            param($root, $output)
            Assert-True ($output -match "Unknown.*Default|catalog") "removed Default was accepted"
        }
    }
}
Invoke-TestCase "Windows helper uses a Windows PowerShell 5.1-compatible host check" {
    $helper = Get-Content -Raw -Encoding UTF8 (Join-Path $RepoRoot ".kinotch/templates/defaults/windows/tools/windows-shell.ps1")
    Assert-True ($helper -match '\$env:OS\s*-eq\s*"Windows_NT"') "Windows helper does not use the Windows_NT environment marker"
    Assert-True ($helper -notmatch '\$IsWindows') "Windows helper relies on the PowerShell Core-only IsWindows variable"
}
Invoke-TestCase "API Default envelope remains a permissive boundary descriptor" {
    $schema = Get-Content -Raw -Encoding UTF8 (Join-Path $RepoRoot ".kinotch/templates/defaults/api/contracts/api-error-envelope.json") | ConvertFrom-Json
    Assert-True (@($schema.required) -notcontains "details") "API Default made details mandatory"
    Assert-True ($schema.additionalProperties -eq $true) "API Default rejects Project-owned extensions"
}
Invoke-TestCase "oneOf requires exactly one matching schema" {
    $schema = [pscustomobject]@{
        oneOf = @(
            [pscustomobject]@{ type = "string" },
            [pscustomobject]@{ type = "string"; minLength = 1 }
        )
    }
    $multipleMatches = @(Test-KntSchema -Data "abc" -Schema $schema -Path "fixture.value")
    Assert-Equal 1 $multipleMatches.Count "overlapping oneOf schema count"
    Assert-True ($multipleMatches[0] -match "exactly one.*matched 2") "multiple oneOf matches were not rejected"

    $zeroMatches = @(Test-KntSchema -Data 123 -Schema $schema -Path "fixture.value")
    Assert-Equal 1 $zeroMatches.Count "zero-match oneOf schema count"
    Assert-True ($zeroMatches[0] -match "exactly one.*matched 0") "zero oneOf matches were not rejected"
}
Invoke-TestCase "Base schemas use the declared validator keyword subset" {
    $supported = @(
        "type", "required", "properties", "additionalProperties", "items", "oneOf",
        "enum", "const", "pattern", "minLength", "uniqueItems", '$schema', '$id', "title"
    )
    $explicitlyExcluded = @('$ref')
    $unsupported = New-Object System.Collections.Generic.List[string]
    foreach ($schemaFile in Get-ChildItem (Join-Path $RepoRoot ".kinotch/schemas") -Filter "*.json" -File) {
        $schema = Get-Content -Raw -Encoding UTF8 $schemaFile.FullName | ConvertFrom-Json
        foreach ($keyword in @(Get-SchemaKeywordNames $schema)) {
            if ($keyword -notin $supported -and $keyword -notin $explicitlyExcluded) {
                [void]$unsupported.Add("$($schemaFile.Name):$keyword")
            }
        }
    }
    Assert-Equal 0 $unsupported.Count ("unsupported schema keywords: " + ($unsupported -join ", "))
}
Invoke-TestCase "invalid manifest is rejected by schema" {
    Invoke-KntFixture -Name "invalid-manifest" -Command "doctor" -ExpectedExit 1 -AssertOutput {
        param($root, $output)
        Assert-True ($output -match "Schema validation failed") "schema error was not reported"
    }
}
Invoke-TestCase "invalid action registry is rejected by schema" {
    Invoke-KntFixture -Name "invalid-actions" -Command "doctor" -ExpectedExit 1 -AssertOutput {
        param($root, $output)
        Assert-True ($output -match "Schema validation failed") "action schema heading was not reported"
        Assert-True ($output -match "actions") "action schema path was not reported"
    }
}
Invoke-TestCase "invalid surface registry is rejected by schema" {
    Invoke-KntFixture -Name "invalid-surfaces" -Command "doctor" -ExpectedExit 1 -AssertOutput {
        param($root, $output)
        Assert-True ($output -match "Schema validation failed") "surface schema heading was not reported"
        Assert-True ($output -match "surfaces") "surface schema path was not reported"
    }
}
Invoke-TestCase "invalid JSON returns parse exit code" {
    Invoke-KntFixture -Name "invalid-json" -Command "doctor" -ExpectedExit 2 -AssertOutput {
        param($root, $output)
        Assert-True ($output -match "JSON parse error") "JSON parse error was not reported"
    }
}
Invoke-TestCase "missing required path is rejected" {
    Invoke-KntFixture -Name "missing-files" -Command "doctor" -ExpectedExit 1 -AssertOutput {
        param($root, $output)
        Assert-True ($output -match "MISSING path.*docs|docs.*MISSING path") "missing path was not reported"
    }
}
Invoke-TestCase "unknown command returns two" {
    Invoke-KntFixture -Name "valid-minimal" -Command "unknown-command" -ExpectedExit 2 -AssertOutput {
        param($root, $output)
        Assert-True ($output -match "Unknown command") "unknown command was not reported"
    }
}
Invoke-TestCase "project command exit code propagates" {
    Invoke-KntFixture -Name "command-failure" -Command "test" -ExpectedExit 7
}
Invoke-TestCase "structured command forwards metacharacters without injection" {
    $malicious = "; Set-Content injected.txt pwned; `$(Get-Date) | & echo escaped"
    Invoke-KntFixture -Name "valid-minimal" -Command "test" -Arguments @($malicious) -ExpectedExit 0 -Prepare {
        param($root)
        $recordScript = @'
param()
[IO.File]::WriteAllText("received-argument.txt", [string]$args[0], (New-Object System.Text.UTF8Encoding($false)))
'@
        [IO.File]::WriteAllText((Join-Path $root "project/record-argument.ps1"), $recordScript, (New-Object System.Text.UTF8Encoding($false)))
        $manifestPath = Join-Path $root "project/project.json"
        $manifest = Get-Content -Raw -Encoding UTF8 $manifestPath | ConvertFrom-Json
        $manifest.commands.test = [pscustomobject]@{
            exec = $PowerShellExecutable
            args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "record-argument.ps1")
            cwd = "project"
            forward_args = $true
        }
        [IO.File]::WriteAllText($manifestPath, (ConvertTo-Json $manifest -Depth 20) + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
    } -AssertOutput {
        param($root, $output)
        $receivedPath = Join-Path $root "project/received-argument.txt"
        Assert-Equal $malicious (Get-Content -Raw -Encoding UTF8 $receivedPath) "structured command argument"
        Assert-True (-not (Test-Path (Join-Path $root "project/injected.txt"))) "structured command executed injected text"
    }
}
Invoke-TestCase "legacy command rejects forwarded arguments explicitly" {
    Invoke-KntFixture -Name "command-cwd" -Command "test" -Arguments @("unsafe-argument") -ExpectedExit 2 -AssertOutput {
        param($root, $output)
        Assert-True ($output -match "structured.*forward|forward.*structured|legacy") "legacy forwarded argument rejection was not reported"
    }
}
Invoke-TestCase "verify fallback runs test then build" {
    Invoke-KntFixture -Name "verify-fallback" -Command "verify" -ExpectedExit 0 -AssertOutput {
        param($root, $output)
        $marker = Join-Path $root "project/command-order.txt"
        Assert-True (Test-Path $marker) "verify marker was not created"
        Assert-Equal ("test" + [Environment]::NewLine + "build") ((Get-Content -Raw $marker).Trim()) "verify order"
    }
}
Invoke-TestCase "verify fallback propagates a failing project command" {
    Invoke-KntFixture -Name "verify-fallback" -Command "verify" -ExpectedExit 9 -Prepare {
        param($root)
        $manifestPath = Join-Path $root "project/project.json"
        $manifest = Get-Content -Raw -Encoding UTF8 $manifestPath | ConvertFrom-Json
        $manifest.commands.build.run = if (Get-Command pwsh -ErrorAction SilentlyContinue) {
            "& pwsh -NoProfile -Command 'exit 9'"
        } else {
            "& powershell -NoProfile -Command 'exit 9'"
        }
        [IO.File]::WriteAllText($manifestPath, (ConvertTo-Json $manifest -Depth 20) + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
    }
}
Invoke-TestCase "command runs in declared cwd" {
    Invoke-KntFixture -Name "command-cwd" -Command "test" -ExpectedExit 0 -AssertOutput {
        param($root, $output)
        $marker = Join-Path $root "project/command-cwd.marker"
        Assert-True (Test-Path $marker) "cwd marker was not created"
        $actual = (Get-Content -Raw $marker).Trim()
        $expected = (Resolve-Path (Join-Path $root "project")).Path
        Assert-Equal $expected $actual "command cwd"
    }
}

Invoke-TestCase "changed Base file fails base-check" {
    Invoke-KntFixture -Name "valid-minimal" -Command "base-check" -ExpectedExit 1 -Prepare {
        param($root)
        Set-FixtureBaseIndex $root
        Add-Content -LiteralPath (Join-Path $root ".kinotch/README_BASE.md") -Value "changed for test"
    }
}

Invoke-TestCase "base-refresh indexes new common file" {
    Invoke-KntFixture -Name "valid-minimal" -Command "base-refresh" -ExpectedExit 0 -Prepare {
        param($root)
        Set-FixtureAsBase $root
        Set-FixtureBaseIndex $root
        Set-Content -LiteralPath (Join-Path $root ".kinotch/new-common.txt") -Value "new common file" -NoNewline
        $router = Join-Path $root ".kinotch/scripts/knt.ps1"
        $before = @(& $PowerShellExecutable -NoProfile -ExecutionPolicy Bypass -File $router -RootOverride $root base-check 2>&1)
        if ($LASTEXITCODE -eq 0) { throw "unindexed Base file was not rejected: $($before -join ' ')" }
    } -AssertOutput {
        param($root, $output)
        $router = Join-Path $root ".kinotch/scripts/knt.ps1"
        @(& $PowerShellExecutable -NoProfile -ExecutionPolicy Bypass -File $router -RootOverride $root base-check 2>&1) | Out-Null
        Assert-Equal 0 $LASTEXITCODE "base-check after refresh"
    }
}

Invoke-TestCase "Base documentation and profile status are finalized" {
    $spec = Get-Content -Raw (Join-Path $RepoRoot "project/docs/SPEC.md")
    $state = Get-Content -Raw (Join-Path $RepoRoot "project/docs/CURRENT_STATE.md")
    $runtime = Get-Content -Raw (Join-Path $RepoRoot ".kinotch/RUNTIME_INTEGRATION.md")
    $workflow = Get-Content -Raw (Join-Path $RepoRoot ".github/workflows/verify.yml")
    $surfaceRegistry = Get-Content -Raw (Join-Path $RepoRoot "project/contracts/surfaces.json") | ConvertFrom-Json
    $catalog = Get-Content -Raw (Join-Path $RepoRoot ".kinotch/defaults/catalog.json") | ConvertFrom-Json
    $baseVersion = (Get-Content -Raw (Join-Path $RepoRoot ".kinotch/BASE_VERSION")).Trim()
    Assert-True (([regex]::Matches($spec, "(?m)^\d+\. ")).Count -ge 10) "SPEC acceptance criteria are incomplete"
    Assert-True ($state -notmatch "Project-specific definition has not been filled") "CURRENT_STATE still contains a template placeholder"
    Assert-True ($state -match "Project Manifest / Action Registry / Surface Registry runtime schema validation") "CURRENT_STATE runtime validation wording is stale"
    Assert-True ($state -match "Error / Result / Progress / Resource / Artifact schema definitions") "CURRENT_STATE schema-definition wording is missing"
    Assert-True ($runtime -match "Action Result") "Runtime defined-contract content is missing"
    Assert-True ($runtime -match "ActionRequest") "Runtime candidate-contract content is missing"
    Assert-True ($workflow -match "knt\.ps1 setup") "Base CI setup step is missing"
    Assert-Equal 0 @($surfaceRegistry.surfaces.PSObject.Properties).Count "Base Surface Registry should be empty"
    Assert-Equal "0.3.8" $baseVersion "Base version"
    Assert-True (@($catalog.defaults | Where-Object { $_.kind -eq "surface" }).Count -ge 8) "Surface Default catalog entries are incomplete"
    Assert-Equal 4 @($catalog.defaults | Where-Object { $_.kind -eq "tool" }).Count "Active Tool Default catalog count"
    foreach ($profileFile in Get-ChildItem (Join-Path $RepoRoot ".kinotch/profiles") -File) {
        $profile = Get-Content -Raw -Encoding UTF8 $profileFile.FullName | ConvertFrom-Json
        Assert-Equal "planned" $profile.status "$($profileFile.Name) profile status"
    }
}

Invoke-TestCase "profile surface contradiction fails doctor" {
    Invoke-KntFixture -Name "valid-minimal" -Command "doctor" -ExpectedExit 1 -Prepare {
        param($root)
        $manifestPath = Join-Path $root "project/project.json"
        $manifest = Get-Content -Raw -Encoding UTF8 $manifestPath | ConvertFrom-Json
        $manifest.profile = "cli"
        [IO.File]::WriteAllText($manifestPath, (ConvertTo-Json $manifest -Depth 20) + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
    } -AssertOutput {
        param($root, $output)
        Assert-True ($output -match "CONTRADICTION") "profile surface contradiction was not reported"
    }
}

Invoke-TestCase "base-refresh is restricted to repository-base" {
    Invoke-KntFixture -Name "valid-minimal" -Command "base-refresh" -ExpectedExit 2 -AssertOutput {
        param($root, $output)
        Assert-True ($output -match "only available.*repository-base") "base-refresh restriction was not reported"
    }
}

Write-Host "Self-test summary: passed=$Passed failed=$Failed"
if ($Failed -gt 0) { exit 1 }
exit 0

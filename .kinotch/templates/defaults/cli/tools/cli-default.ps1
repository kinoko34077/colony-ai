[CmdletBinding()]
param()

function Write-CliJson {
    param(
        [Parameter(Mandatory=$true)]$Value,
        [int]$Depth = 20
    )

    [Console]::Out.WriteLine((ConvertTo-Json $Value -Depth $Depth -Compress))
}

function Write-CliError {
    param(
        [Parameter(Mandatory=$true)][string]$Code,
        [Parameter(Mandatory=$true)][string]$Message,
        [hashtable]$Details = @{}
    )

    $envelope = [ordered]@{
        error = $Code
        message = $Message
        details = $Details
    }
    [Console]::Error.WriteLine((ConvertTo-Json $envelope -Depth 20 -Compress))
}

function Exit-Cli {
    param([int]$Code = 0)
    exit $Code
}

function Show-CliHelp {
    param([string]$Usage = "Usage: <project command> [options]")
    [Console]::Out.WriteLine($Usage)
    [Console]::Out.WriteLine("  --help       Show help")
    [Console]::Out.WriteLine("  --version    Show version")
    [Console]::Out.WriteLine("  --json       Use machine-readable output")
    [Console]::Out.WriteLine("  --quiet      Reduce human-readable output")
    [Console]::Out.WriteLine("  --verbose    Enable diagnostic output")
    [Console]::Out.WriteLine("  --dry-run    Do not apply changes")
    [Console]::Out.WriteLine("  --yes        Confirm non-interactive operation")
}

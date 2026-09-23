[CmdletBinding()]
param()

function Test-WindowsShellHost {
    return ($env:OS -eq "Windows_NT")
}

function Reveal-WindowsPath {
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not (Test-WindowsShellHost)) {
        throw "Windows shell Default is only available on Windows."
    }
    $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    Start-Process -FilePath "explorer.exe" -ArgumentList "/select,`"$resolved`""
}

function Copy-WindowsClipboardText {
    param([Parameter(Mandatory=$true)][string]$Text)

    if (-not (Test-WindowsShellHost)) {
        throw "Windows shell Default is only available on Windows."
    }
    Set-Clipboard -Value $Text
}

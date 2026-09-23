Set-Content -LiteralPath (Join-Path (Get-Location) "command-cwd.marker") -Value (Get-Location).Path -NoNewline
exit 0

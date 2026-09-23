param([string]$Name)
Add-Content -LiteralPath (Join-Path (Get-Location) "command-order.txt") -Value $Name
exit 0

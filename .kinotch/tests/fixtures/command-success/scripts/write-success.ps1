Set-Content -LiteralPath (Join-Path (Get-Location) "success.marker") -Value "success" -NoNewline
exit 0

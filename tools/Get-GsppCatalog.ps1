#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Commit = '160c177db6c84d3c621fff614559943b1de8c600',
    [string]$ExpectedSha256 = '7c3acebd0867724e8fc2e6ce73f942642fcd37e533600e0952699f130a8bca90',
    [string]$OutFile = (Join-Path (Get-Location).Path '.cache/Grundschutz++-resolved_catalog.json')
)

$ErrorActionPreference = 'Stop'
if ($ExpectedSha256 -notmatch '^[0-9A-Fa-f]{64}$') {
    throw 'ExpectedSha256 must be a SHA-256 hexadecimal digest.'
}
$directory = Split-Path -Parent $OutFile
if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) {
    New-Item -ItemType Directory -Path $directory | Out-Null
}
$url = 'https://raw.githubusercontent.com/BSI-Bund/Stand-der-Technik-Bibliothek/' + $Commit + '/control_layer/Grundschutz%2B%2B/Grundschutz%2B%2B-resolved_catalog.json'
Invoke-WebRequest -Uri $url -OutFile $OutFile -UseBasicParsing
$hash = (Get-FileHash -LiteralPath $OutFile -Algorithm SHA256).Hash.ToLowerInvariant()
if ($hash -ne $ExpectedSha256.ToLowerInvariant()) {
    throw "SHA-256 mismatch for $OutFile. Expected $ExpectedSha256, got $hash."
}

$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'GrundschutzCheck.psd1'
Import-Module $modulePath -Force
$catalog = Import-GsppCatalog -Path $OutFile -ExpectedSha256 $ExpectedSha256
Write-Host ('Downloaded: ' + $OutFile)
Write-Host ('SHA-256: ' + $catalog.Sha256)
Write-Host ('Controls: ' + $catalog.ControlCount)
Write-Host ('Practices: ' + @($catalog.Practices).Count)

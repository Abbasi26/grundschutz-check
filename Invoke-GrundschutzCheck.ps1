#Requires -Version 5.1
<#
.SYNOPSIS
    Runs GrundschutzCheck and writes HTML, Markdown, JSON, and CSV reports.
.DESCRIPTION
    Read-only. -Demo renders bundled fictional results and does not read the local system.
    Exit 0: every check passed. Exit 1: at least one check failed. Exit 2: at least one check errored.
#>
[CmdletBinding()]
param(
    [switch]$Demo,
    [string]$CatalogPath,
    [string]$EvidencePath,
    [string]$OutputDirectory,
    [ValidateSet('All', 'Html', 'Markdown', 'Json', 'Csv')]
    [string[]]$Format = @('All'),
    [string]$Timestamp,
    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $here 'GrundschutzCheck.psd1') -Force

$params = @{ Format = $Format }
if ($Demo) { $params.Demo = $true }
if ($PSBoundParameters.ContainsKey('CatalogPath')) { $params.CatalogPath = $CatalogPath }
if ($PSBoundParameters.ContainsKey('EvidencePath')) { $params.EvidencePath = $EvidencePath }
if ($PSBoundParameters.ContainsKey('OutputDirectory')) { $params.OutputDirectory = $OutputDirectory }
if ($PSBoundParameters.ContainsKey('Timestamp')) { $params.Timestamp = $Timestamp }

$result = Invoke-GrundschutzCheck @params
$summary = $result.summary
$mode = [string]$result.evidence.mode
Write-Host ('GrundschutzCheck ' + $result.tool.version + ' (' + $mode + ')')
Write-Host ('pass=' + $summary.pass + ' fail=' + $summary.fail + ' error=' + $summary.error + ' not_applicable=' + $summary.not_applicable + ' total=' + $summary.total)
foreach ($name in @($result.outputs.PSObject.Properties.Name)) {
    Write-Host ($name + ': ' + $result.outputs.$name)
}

if ($PassThru) {
    $result
}

if ($summary.error -gt 0) { exit 2 }
if ($summary.fail -gt 0) { exit 1 }
exit 0

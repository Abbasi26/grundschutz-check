#Requires -Version 5.1
<#
.SYNOPSIS
    Runs GrundschutzCheck and writes HTML, Markdown, JSON, and CSV reports.
.DESCRIPTION
    Read-only. -Demo renders bundled fictional results and does not read the local system.
    Exit 0: every check passed (accepted risks count as passed for the exit code).
    Exit 1: at least one check failed. Exit 2: at least one check errored.
    With -BaselinePath and -FailOnRegression, exit 1 only when a check newly fails compared with the baseline.
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
    [string]$ExceptionPath,
    [string]$BaselinePath,
    [string]$GsppCatalogPath,
    [switch]$FailOnRegression,
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
if ($PSBoundParameters.ContainsKey('ExceptionPath')) { $params.ExceptionPath = $ExceptionPath }
if ($PSBoundParameters.ContainsKey('BaselinePath')) { $params.BaselinePath = $BaselinePath }
if ($PSBoundParameters.ContainsKey('GsppCatalogPath')) { $params.GsppCatalogPath = $GsppCatalogPath }
if ($FailOnRegression -and -not $PSBoundParameters.ContainsKey('BaselinePath')) {
    throw '-FailOnRegression needs -BaselinePath.'
}

$result = Invoke-GrundschutzCheck @params
$summary = $result.summary
$mode = [string]$result.evidence.mode
Write-Host ('GrundschutzCheck ' + $result.tool.version + ' (' + $mode + ')')
Write-Host ('pass=' + $summary.pass + ' fail=' + $summary.fail + ' error=' + $summary.error + ' not_applicable=' + $summary.not_applicable + ' accepted=' + $summary.accepted + ' total=' + $summary.total)
$comparison = $result.PSObject.Properties['comparison']
if ($null -ne $comparison) {
    $cmp = $comparison.Value
    Write-Host ('baseline: newly_failing=' + @($cmp.newly_failing).Count + ' fixed=' + @($cmp.fixed).Count + ' still_failing=' + @($cmp.still_failing).Count)
}
foreach ($name in @($result.outputs.PSObject.Properties.Name)) {
    Write-Host ($name + ': ' + $result.outputs.$name)
}

if ($PassThru) {
    $result
}

if ($summary.error -gt 0) { exit 2 }
if ($FailOnRegression) {
    if (@($result.comparison.newly_failing).Count -gt 0) { exit 1 }
    exit 0
}
if ($summary.fail -gt 0) { exit 1 }
exit 0

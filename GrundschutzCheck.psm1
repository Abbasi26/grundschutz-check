Set-StrictMode -Version 1.0

$script:GsModuleRoot = $PSScriptRoot
$script:GsToolName = 'GrundschutzCheck'
$script:GsToolVersion = '0.1.0'

. (Join-Path $PSScriptRoot 'src/Catalog.ps1')
. (Join-Path $PSScriptRoot 'src/Evaluate.ps1')
. (Join-Path $PSScriptRoot 'src/Collect.ps1')
. (Join-Path $PSScriptRoot 'src/Report.ps1')
. (Join-Path $PSScriptRoot 'src/Exceptions.ps1')
. (Join-Path $PSScriptRoot 'src/Compare.ps1')

function Invoke-GrundschutzCheck {
    <#
    .SYNOPSIS
        Runs the Windows 11 GrundschutzCheck catalog and writes an evidence report.
    .DESCRIPTION
        Read-only. Remediation text in the catalog is not applied.
        Use -Demo to render the bundled fictional evidence on any platform.
        -ExceptionPath marks failing checks with a current, documented risk acceptance as 'accepted'.
        -BaselinePath compares this run with an earlier grundschutzcheck-report.json.
    #>
    [CmdletBinding()]
    param(
        [switch]$Demo,
        [string]$CatalogPath,
        [string]$EvidencePath,
        [string]$OutputDirectory = (Join-Path (Get-Location).Path 'grundschutzcheck-out'),
        [ValidateSet('All', 'Html', 'Markdown', 'Json', 'Csv')]
        [string[]]$Format = @('All'),
        [string]$Timestamp,
        [string]$ExceptionPath,
        [string]$BaselinePath
    )

    $catalog = Get-GsCatalog -Path $CatalogPath
    $problems = @(Test-GsCatalog -Catalog $catalog)
    if ($problems.Count -gt 0) {
        throw ('Catalog is not valid: ' + ($problems -join ' '))
    }

    $exceptions = $null
    if (-not [string]::IsNullOrWhiteSpace($ExceptionPath)) {
        $exceptions = Read-GsExceptionFile -Path $ExceptionPath -Catalog $catalog
    }
    $baseline = $null
    if (-not [string]::IsNullOrWhiteSpace($BaselinePath)) {
        $baseline = Read-GsJsonFile -Path $BaselinePath
    }

    if ($Demo) {
        $evidence = Get-GsDemoEvidence -Path $EvidencePath
        $mode = 'demo'
    }
    else {
        if (-not (Test-GsWindows)) {
            throw 'Local checks run on Windows only. Use -Demo on this platform.'
        }
        $evidence = Get-GsLocalEvidence -Catalog $catalog
        $mode = 'local'
    }

    if ([string]::IsNullOrWhiteSpace($Timestamp)) {
        $Timestamp = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss') + 'Z'
    }

    $pairs = @()
    foreach ($check in (ConvertTo-GsArray (Get-GsProperty $catalog 'checks'))) {
        $evaluation = Invoke-GsEvaluation -Evaluation (Get-GsProperty $check 'evaluation') -Evidence $evidence
        $pairs += [pscustomobject]@{
            Check      = $check
            Evaluation = $evaluation
        }
    }

    $exceptionNotes = @(Set-GsExceptionStatus -Pairs $pairs -Exceptions $exceptions -Timestamp $Timestamp)

    $document = New-GsReportDocument -Catalog $catalog -Evidence $evidence -Evaluations $pairs -Timestamp $Timestamp -Mode $mode
    if ($exceptionNotes.Count -gt 0) {
        $document.evidence.notes = @($document.evidence.notes) + $exceptionNotes
    }
    if ($null -ne $baseline) {
        Add-Member -InputObject $document -NotePropertyName comparison -NotePropertyValue (Compare-GsReport -Baseline $baseline -Document $document) -Force
    }
    $files = Write-GsReportFiles -Document $document -Directory $OutputDirectory -Formats $Format
    Add-Member -InputObject $document -NotePropertyName outputs -NotePropertyValue $files -Force
    return $document
}

Export-ModuleMember -Function Invoke-GrundschutzCheck, Get-GsCatalog

Set-StrictMode -Version 1.0

$script:GsModuleRoot = $PSScriptRoot
$script:GsToolName = 'GrundschutzCheck'
$script:GsToolVersion = '0.1.0'

. (Join-Path $PSScriptRoot 'src/Catalog.ps1')
. (Join-Path $PSScriptRoot 'src/Evaluate.ps1')
. (Join-Path $PSScriptRoot 'src/Collect.ps1')
. (Join-Path $PSScriptRoot 'src/Report.ps1')

function Invoke-GrundschutzCheck {
    <#
    .SYNOPSIS
        Runs the Windows 11 GrundschutzCheck catalog and writes an evidence report.
    .DESCRIPTION
        Read-only. Remediation text in the catalog is not applied.
        Use -Demo to render the bundled fictional evidence on any platform.
    #>
    [CmdletBinding()]
    param(
        [switch]$Demo,
        [string]$CatalogPath,
        [string]$EvidencePath,
        [string]$OutputDirectory = (Join-Path (Get-Location).Path 'grundschutzcheck-out'),
        [ValidateSet('All', 'Html', 'Markdown', 'Json', 'Csv')]
        [string[]]$Format = @('All'),
        [string]$Timestamp
    )

    $catalog = Get-GsCatalog -Path $CatalogPath
    $problems = @(Test-GsCatalog -Catalog $catalog)
    if ($problems.Count -gt 0) {
        throw ('Catalog is not valid: ' + ($problems -join ' '))
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

    $document = New-GsReportDocument -Catalog $catalog -Evidence $evidence -Evaluations $pairs -Timestamp $Timestamp -Mode $mode
    $files = Write-GsReportFiles -Document $document -Directory $OutputDirectory -Formats $Format
    Add-Member -InputObject $document -NotePropertyName outputs -NotePropertyValue $files -Force
    return $document
}

Export-ModuleMember -Function Invoke-GrundschutzCheck, Get-GsCatalog

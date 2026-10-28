Set-StrictMode -Version 1.0

# Compares this run with an earlier grundschutzcheck-report.json. A check counts
# as failing when its status is fail or error. 'accepted' is not failing.

function Get-GsFailingStatus {
    param([string]$Status)
    return ($Status -eq 'fail' -or $Status -eq 'error')
}

function Format-GsTimestampText {
    param($Value)
    if ($Value -is [DateTime]) { return $Value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss') + 'Z' }
    return [string]$Value
}

function Compare-GsReport {
    param(
        [Parameter(Mandatory = $true)]$Baseline,
        [Parameter(Mandatory = $true)]$Document
    )
    $before = @{}
    foreach ($row in (ConvertTo-GsArray (Get-GsProperty $Baseline 'results'))) {
        $before[[string](Get-GsProperty $row 'id')] = [string](Get-GsProperty $row 'status')
    }
    if ($before.Count -eq 0) {
        throw 'Baseline report has no results. Use a grundschutzcheck-report.json from an earlier run.'
    }
    $newlyFailing = @(); $fixed = @(); $stillFailing = @(); $added = @(); $changed = @()
    $seen = @{}
    foreach ($row in @($Document.results)) {
        $id = [string]$row.id
        $seen[$id] = $true
        $now = [string]$row.status
        if (-not $before.ContainsKey($id)) {
            $added += [pscustomobject][ordered]@{ id = $id; title = [string]$row.title; status = $now }
            continue
        }
        $was = [string]$before[$id]
        $entry = [pscustomobject][ordered]@{ id = $id; title = [string]$row.title; severity = [string]$row.severity; before = $was; after = $now }
        $wasFailing = Get-GsFailingStatus $was
        $isFailing = Get-GsFailingStatus $now
        if ($isFailing -and -not $wasFailing) { $newlyFailing += $entry }
        elseif ($wasFailing -and -not $isFailing) { $fixed += $entry }
        elseif ($isFailing -and $wasFailing) { $stillFailing += $entry }
        elseif ($was -ne $now) { $changed += $entry }
    }
    $removed = @()
    foreach ($id in ($before.Keys | Sort-Object)) {
        if (-not $seen.ContainsKey($id)) { $removed += $id }
    }
    $baseEvidence = Get-GsProperty $Baseline 'evidence'
    $baseCatalog = Get-GsProperty $Baseline 'catalog'
    $sameHost = $null
    $baseHost = [string](Get-GsProperty $baseEvidence 'host_fingerprint_sha256')
    if (-not [string]::IsNullOrWhiteSpace($baseHost)) {
        $sameHost = ($baseHost -eq [string]$Document.evidence.host_fingerprint_sha256)
    }
    return [pscustomobject][ordered]@{
        baseline_generated_at      = (Format-GsTimestampText (Get-GsProperty $baseEvidence 'generated_at'))
        baseline_catalog_version   = [string](Get-GsProperty $baseCatalog 'version')
        same_host                  = $sameHost
        newly_failing              = $newlyFailing
        fixed                      = $fixed
        still_failing              = $stillFailing
        other_changes              = $changed
        new_checks                 = $added
        removed_checks             = $removed
    }
}

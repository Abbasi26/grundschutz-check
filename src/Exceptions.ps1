Set-StrictMode -Version 1.0

# Documented risk acceptances ("exceptions"). A failing check with a current
# exception is reported as 'accepted' instead of 'fail'. Every exception needs a
# reason, an owner, and an expiry date, so an acceptance cannot become permanent
# by accident. Errors are never hidden by an exception.

function ConvertTo-GsDateOnly {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [DateTime]) { return $Value.Date }
    $text = ([string]$Value).Trim()
    $parsed = [DateTime]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
    if ([DateTime]::TryParseExact($text, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed)) {
        return $parsed.Date
    }
    return $null
}

function Read-GsExceptionFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        $Catalog
    )
    $doc = Read-GsJsonFile -Path $Path
    $known = @{}
    foreach ($check in (ConvertTo-GsArray (Get-GsProperty $Catalog 'checks'))) {
        $known[[string](Get-GsProperty $check 'id')] = $true
    }
    $problems = New-Object System.Collections.Generic.List[string]
    $items = Get-GsProperty $doc 'exceptions'
    if ($null -eq $items) {
        throw "Exception file $Path needs an 'exceptions' array."
    }
    $byId = @{}
    $index = 0
    foreach ($item in (ConvertTo-GsArray $items)) {
        $where = "exceptions[$index]"
        $id = [string](Get-GsProperty $item 'check_id')
        $reason = [string](Get-GsProperty $item 'reason')
        $owner = [string](Get-GsProperty $item 'owner')
        $expiresRaw = Get-GsProperty $item 'expires'
        $expires = ConvertTo-GsDateOnly $expiresRaw
        if ([string]::IsNullOrWhiteSpace($id)) {
            $problems.Add("$where has no check_id.")
        }
        elseif (-not $known.ContainsKey($id)) {
            $problems.Add("$where names unknown check $id.")
        }
        elseif ($byId.ContainsKey($id)) {
            $problems.Add("$where repeats check $id.")
        }
        if ([string]::IsNullOrWhiteSpace($reason)) { $problems.Add("$where ($id) has no reason.") }
        if ([string]::IsNullOrWhiteSpace($owner)) { $problems.Add("$where ($id) has no owner.") }
        if ($null -eq $expires) { $problems.Add("$where ($id) needs expires as yyyy-MM-dd.") }
        if (-not [string]::IsNullOrWhiteSpace($id) -and -not $byId.ContainsKey($id)) {
            $byId[$id] = [pscustomobject][ordered]@{
                check_id = $id
                reason   = $reason
                owner    = $owner
                expires  = $(if ($null -ne $expires) { $expires.ToString('yyyy-MM-dd') } else { '' })
                ticket   = [string](Get-GsProperty $item 'ticket')
            }
        }
        $index += 1
    }
    if ($problems.Count -gt 0) {
        throw ('Exception file is not valid: ' + ($problems -join ' '))
    }
    return $byId
}

function Set-GsExceptionStatus {
    <#
        Applies exceptions to evaluation pairs in place. Returns notes for the report.
    #>
    param($Pairs, $Exceptions, [string]$Timestamp)
    $notes = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Exceptions -or $Exceptions.Count -eq 0) { return $notes.ToArray() }
    $runDate = (ConvertTo-GsDateOnly ($Timestamp.Substring(0, [Math]::Min(10, $Timestamp.Length))))
    if ($null -eq $runDate) { $runDate = [DateTime]::UtcNow.Date }
    foreach ($pair in $Pairs) {
        $id = [string](Get-GsProperty $pair.Check 'id')
        if (-not $Exceptions.ContainsKey($id)) { continue }
        $exception = $Exceptions[$id]
        $expires = ConvertTo-GsDateOnly $exception.expires
        $current = $expires -ge $runDate
        $evaluation = $pair.Evaluation
        $state = 'unused'
        switch ([string]$evaluation.Status) {
            'fail' {
                if ($current) {
                    $evaluation.Status = 'accepted'
                    $evaluation.Message = ('Accepted risk until ' + $exception.expires + ' (owner: ' + $exception.owner + '): ' + $exception.reason + ' Observed result: ' + $evaluation.Message)
                    $state = 'applied'
                }
                else {
                    $evaluation.Message = ($evaluation.Message + ' The exception for this check expired on ' + $exception.expires + '.')
                    $state = 'expired'
                    $notes.Add("Exception for $id expired on $($exception.expires). The check is reported as fail.")
                }
            }
            'pass' {
                $state = 'not_needed'
                $notes.Add("Exception for $id is no longer needed: the check passes. Consider removing it.")
            }
            'error' {
                $state = 'not_applied_error'
                $notes.Add("Exception for $id was not applied because the check could not be evaluated.")
            }
            default { $state = 'not_needed' }
        }
        $record = [pscustomobject][ordered]@{
            reason  = $exception.reason
            owner   = $exception.owner
            expires = $exception.expires
            ticket  = $exception.ticket
            state   = $state
        }
        Add-Member -InputObject $evaluation -NotePropertyName Exception -NotePropertyValue $record -Force
    }
    return $notes.ToArray()
}

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

function Read-GsCsvExceptionFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "File not found: $Path"
    }
    $utf8 = New-Object System.Text.UTF8Encoding $false
    $raw = [System.IO.File]::ReadAllText($Path, $utf8)
    if ($raw.Length -gt 0 -and [int][char]$raw[0] -eq 0xFEFF) {
        $raw = $raw.Substring(1)
    }
    if ($raw.Trim().Length -eq 0) {
        throw "Exception file $Path is empty or has no header."
    }
    $records = @($raw | ConvertFrom-Csv -Delimiter ',')
    $required = @('check_id', 'reason', 'owner', 'expires', 'ticket')
    $headerNames = @()
    if ($records.Count -gt 0) {
        $headerNames = @($records[0].PSObject.Properties.Name)
    }
    else {
        $firstLine = (($raw -split "\r?\n") | Where-Object { $null -ne $_ } | Select-Object -First 1)
        if ($null -eq $firstLine -or $firstLine.Trim().Length -eq 0) {
            throw "Exception file $Path is empty or has no header."
        }
        $headerNames = @($firstLine.Split(',') | ForEach-Object { $_.Trim().Trim('"') })
    }
    foreach ($col in $required) {
        if ($headerNames -notcontains $col) {
            throw "Exception file $Path is missing required CSV column '$col'."
        }
    }
    $items = New-Object System.Collections.Generic.List[object]
    $row = 1
    foreach ($record in $records) {
        $items.Add([pscustomobject][ordered]@{
            where    = "CSV row $row"
            check_id = [string](Get-GsProperty $record 'check_id')
            reason   = [string](Get-GsProperty $record 'reason')
            owner    = [string](Get-GsProperty $record 'owner')
            expires  = [string](Get-GsProperty $record 'expires')
            ticket   = [string](Get-GsProperty $record 'ticket')
        }) | Out-Null
        $row += 1
    }
    return $items.ToArray()
}

function Read-GsExceptionFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        $Catalog
    )
    $known = @{}
    foreach ($check in (ConvertTo-GsArray (Get-GsProperty $Catalog 'checks'))) {
        $known[[string](Get-GsProperty $check 'id')] = $true
    }
    $problems = New-Object System.Collections.Generic.List[string]
    $items = @()
    if ([System.IO.Path]::GetExtension($Path) -ieq '.csv') {
        $items = @(Read-GsCsvExceptionFile -Path $Path)
    }
    else {
        $doc = Read-GsJsonFile -Path $Path
        $rawItems = Get-GsProperty $doc 'exceptions'
        if ($null -eq $rawItems) {
            throw "Exception file $Path needs an 'exceptions' array."
        }
        $index = 0
        foreach ($item in (ConvertTo-GsArray $rawItems)) {
            $items += [pscustomobject][ordered]@{
                where    = "exceptions[$index]"
                check_id = [string](Get-GsProperty $item 'check_id')
                reason   = [string](Get-GsProperty $item 'reason')
                owner    = [string](Get-GsProperty $item 'owner')
                expires  = Get-GsProperty $item 'expires'
                ticket   = [string](Get-GsProperty $item 'ticket')
            }
            $index += 1
        }
    }
    $byId = @{}
    foreach ($item in $items) {
        $where = [string]$item.where
        $id = [string]$item.check_id
        $reason = [string]$item.reason
        $owner = [string]$item.owner
        $expiresRaw = $item.expires
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
                ticket   = [string]$item.ticket
            }
        }
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

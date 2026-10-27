Set-StrictMode -Version 1.0

function Format-GsValue {
    param($Value)
    if ($null -eq $Value) {
        return '(not set)'
    }
    if ($Value -is [bool]) {
        if ($Value) { return 'true' }
        return 'false'
    }
    if ($Value -is [System.Array]) {
        $parts = @()
        foreach ($item in @($Value)) {
            $parts += (Format-GsValue $item)
        }
        return ($parts -join ', ')
    }
    return [string]$Value
}

function Test-GsNumericValue {
    param($Value)
    if ($null -eq $Value) { return $false }
    if ($Value -is [bool]) { return $false }
    $text = ([string]$Value).Trim()
    return $text -match '^[+-]?[0-9]+$'
}

function ConvertTo-GsLong {
    param($Value)
    return [long](([string]$Value).Trim())
}

function ConvertTo-GsBool {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [bool]) { return $Value }
    $text = ([string]$Value).Trim()
    switch ($text) {
        '1' { return $true }
        '0' { return $false }
        'true' { return $true }
        'True' { return $true }
        'false' { return $false }
        'False' { return $false }
        default { return $null }
    }
}

function Get-GsGermanNoAuditing {
    # "Keine Ueberwachung" with U+00DC, kept out of the source file as a literal.
    return ('Keine {0}berwachung' -f [string]([char]0x00DC))
}

function ConvertTo-GsAuditSetting {
    param([string]$Setting)
    if ([string]::IsNullOrWhiteSpace($Setting)) {
        return ''
    }
    $text = $Setting.Trim()
    $noAudit = Get-GsGermanNoAuditing
    if ($text -eq 'Success and Failure' -or $text -eq 'Erfolg und Fehler') {
        return 'Success and Failure'
    }
    if ($text -eq 'No Auditing' -or $text -eq $noAudit) {
        return 'No Auditing'
    }
    if ($text -eq 'Success' -or $text -eq 'Erfolg') {
        return 'Success'
    }
    if ($text -eq 'Failure' -or $text -eq 'Fehler') {
        return 'Failure'
    }
    return $text
}

function ConvertTo-GsAuditGuid {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ''
    }
    $text = $Value.Trim().Trim('"').Trim('{}').ToLowerInvariant()
    if ($text -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
        return ''
    }
    return ('{' + $text + '}')
}

function Get-GsAuditSubcategoryTable {
    # GUIDs are the subcategory identifiers from MS-GPAC 2.2.1.2.
    # German aliases are de-DE advanced-audit display names. Umlauts are built
    # from code points so this file stays ASCII.
    $ue = [string]([char]0x00FC)
    $Ue = [string]([char]0x00DC)
    $credentialDe = ('Anmeldeinformationen {0}berpr{0}fen' -f $ue)
    $credentialDeAlt = ('{0}berpr{1}fung der Anmeldeinformationen' -f $Ue, $ue)
    return @(
        [pscustomobject]@{ Name = 'Logon'; Guid = '{0cce9215-69ae-11d9-bed3-505054503030}'; Aliases = @('Anmelden') }
        [pscustomobject]@{ Name = 'Logoff'; Guid = '{0cce9216-69ae-11d9-bed3-505054503030}'; Aliases = @('Abmelden') }
        [pscustomobject]@{ Name = 'Account Lockout'; Guid = '{0cce9217-69ae-11d9-bed3-505054503030}'; Aliases = @('Kontosperrung') }
        [pscustomobject]@{ Name = 'Special Logon'; Guid = '{0cce921b-69ae-11d9-bed3-505054503030}'; Aliases = @('Spezielle Anmeldung') }
        [pscustomobject]@{ Name = 'Process Creation'; Guid = '{0cce922b-69ae-11d9-bed3-505054503030}'; Aliases = @('Prozesserstellung') }
        [pscustomobject]@{ Name = 'User Account Management'; Guid = '{0cce9235-69ae-11d9-bed3-505054503030}'; Aliases = @('Benutzerkontenverwaltung') }
        [pscustomobject]@{ Name = 'Security Group Management'; Guid = '{0cce9237-69ae-11d9-bed3-505054503030}'; Aliases = @('Sicherheitsgruppenverwaltung') }
        [pscustomobject]@{ Name = 'Credential Validation'; Guid = '{0cce923f-69ae-11d9-bed3-505054503030}'; Aliases = @($credentialDe, $credentialDeAlt) }
    )
}

function Resolve-GsAuditSubcategory {
    param([string]$Name, [string]$Guid)
    $table = Get-GsAuditSubcategoryTable
    $normGuid = ConvertTo-GsAuditGuid -Value $Guid
    $trimmed = ''
    if (-not [string]::IsNullOrWhiteSpace($Name)) {
        $trimmed = $Name.Trim()
    }
    if (-not [string]::IsNullOrWhiteSpace($normGuid)) {
        foreach ($row in $table) {
            if ($row.Guid -eq $normGuid) {
                return [pscustomobject]@{ Name = [string]$row.Name; Guid = [string]$row.Guid; MatchedBy = 'guid' }
            }
        }
        return [pscustomobject]@{ Name = $trimmed; Guid = $normGuid; MatchedBy = 'guid-unknown' }
    }
    foreach ($row in $table) {
        if ([string]::Equals([string]$row.Name, $trimmed, [System.StringComparison]::OrdinalIgnoreCase)) {
            return [pscustomobject]@{ Name = [string]$row.Name; Guid = [string]$row.Guid; MatchedBy = 'name' }
        }
        foreach ($alias in @($row.Aliases)) {
            if ([string]::Equals([string]$alias, $trimmed, [System.StringComparison]::OrdinalIgnoreCase)) {
                return [pscustomobject]@{ Name = [string]$row.Name; Guid = [string]$row.Guid; MatchedBy = 'alias' }
            }
        }
    }
    return [pscustomobject]@{ Name = $trimmed; Guid = ''; MatchedBy = 'raw' }
}

function New-GsEvalResult {
    param(
        [string]$Status,
        $Expected,
        $Actual,
        [string]$Message
    )
    return [pscustomobject]@{
        Status   = $Status
        Expected = $Expected
        Actual   = $Actual
        Message  = $Message
    }
}

function Test-GsExpectation {
    param(
        [string]$OperatorName,
        $Expected,
        $Actual
    )
    if ($OperatorName -eq 'equals' -or $OperatorName -eq 'not_equals') {
        $equal = $false
        $leftBool = ConvertTo-GsBool $Expected
        $rightBool = ConvertTo-GsBool $Actual
        if (($Expected -is [bool] -or $Actual -is [bool]) -and $null -ne $leftBool -and $null -ne $rightBool) {
            $equal = ($leftBool -eq $rightBool)
        }
        elseif ((Test-GsNumericValue $Expected) -and (Test-GsNumericValue $Actual)) {
            $equal = ((ConvertTo-GsLong $Expected) -eq (ConvertTo-GsLong $Actual))
        }
        else {
            $equal = ([string]$Expected).Trim() -eq ([string]$Actual).Trim()
        }
        if ($OperatorName -eq 'equals') { return $equal }
        return -not $equal
    }
    if ($OperatorName -eq 'greater_or_equal' -or $OperatorName -eq 'less_or_equal' -or $OperatorName -eq 'in_range' -or $OperatorName -eq 'bits_set') {
        if (-not (Test-GsNumericValue $Actual)) {
            return $false
        }
        $current = ConvertTo-GsLong $Actual
        if ($OperatorName -eq 'greater_or_equal') {
            return $current -ge (ConvertTo-GsLong $Expected)
        }
        if ($OperatorName -eq 'less_or_equal') {
            return $current -le (ConvertTo-GsLong $Expected)
        }
        if ($OperatorName -eq 'bits_set') {
            $mask = ConvertTo-GsLong $Expected
            return (($current -band $mask) -eq $mask)
        }
        $bounds = ConvertTo-GsArray $Expected
        if ($bounds.Count -lt 2) { return $false }
        $min = ConvertTo-GsLong $bounds[0]
        $max = ConvertTo-GsLong $bounds[1]
        return ($current -ge $min -and $current -le $max)
    }
    if ($OperatorName -eq 'one_of') {
        foreach ($candidate in (ConvertTo-GsArray $Expected)) {
            if (Test-GsExpectation -OperatorName 'equals' -Expected $candidate -Actual $Actual) {
                return $true
            }
        }
        return $false
    }
    throw "Unsupported operator $OperatorName"
}

function Format-GsExpected {
    param($Evaluation)
    $operatorName = [string](Get-GsProperty $Evaluation 'operator')
    $expected = Get-GsProperty $Evaluation 'expected'
    if ($operatorName -eq 'in_range') {
        $bounds = ConvertTo-GsArray $expected
        return ('{0}..{1}' -f $bounds[0], $bounds[1])
    }
    if ($operatorName -eq 'one_of') {
        return ('one of: {0}' -f (Format-GsValue $expected))
    }
    if ($operatorName -eq 'bits_set') {
        return ('bits 0x{0:X}' -f (ConvertTo-GsLong $expected))
    }
    if ($operatorName -eq 'greater_or_equal') {
        return ('>= {0}' -f (Format-GsValue $expected))
    }
    if ($operatorName -eq 'less_or_equal') {
        return ('<= {0}' -f (Format-GsValue $expected))
    }
    if ($operatorName -eq 'not_equals') {
        return ('not {0}' -f (Format-GsValue $expected))
    }
    return (Format-GsValue $expected)
}

function Get-GsAbsentDisposition {
    param($Evaluation)
    $when = [string](Get-GsProperty $Evaluation 'when_absent')
    if ([string]::IsNullOrWhiteSpace($when)) {
        return 'fail'
    }
    return $when
}

function New-GsAbsentResult {
    param($Evaluation)
    $expectedText = Format-GsExpected $Evaluation
    switch (Get-GsAbsentDisposition $Evaluation) {
        'pass' {
            return New-GsEvalResult -Status 'pass' -Expected $expectedText -Actual '(not set)' -Message 'Value is not set. Absence is accepted for this check.'
        }
        'not_applicable' {
            return New-GsEvalResult -Status 'not_applicable' -Expected $expectedText -Actual '(not set)' -Message 'Value is not set. This check is not applicable.'
        }
        default {
            return New-GsEvalResult -Status 'fail' -Expected $expectedText -Actual '(not set)' -Message 'Value is not set.'
        }
    }
}

function Find-GsRow {
    param($Rows, [scriptblock]$Predicate)
    foreach ($row in (ConvertTo-GsArray $Rows)) {
        if (& $Predicate $row) {
            return $row
        }
    }
    return $null
}

function Invoke-GsCompare {
    param($Evaluation, $Actual)
    $operatorName = [string](Get-GsProperty $Evaluation 'operator')
    $expected = Get-GsProperty $Evaluation 'expected'
    $expectedText = Format-GsExpected $Evaluation
    $actualText = Format-GsValue $Actual
    $ok = Test-GsExpectation -OperatorName $operatorName -Expected $expected -Actual $Actual
    if ($ok) {
        return New-GsEvalResult -Status 'pass' -Expected $expectedText -Actual $actualText -Message 'Observed value matches the catalog.'
    }
    return New-GsEvalResult -Status 'fail' -Expected $expectedText -Actual $actualText -Message 'Observed value does not match the catalog.'
}

function Invoke-GsEvaluation {
    param($Evaluation, $Evidence)
    $method = [string](Get-GsProperty $Evaluation 'method')
    if ($method -eq 'all_of' -or $method -eq 'any_of') {
        return Invoke-GsCompositeEvaluation -Evaluation $Evaluation -Evidence $Evidence
    }
    switch ($method) {
        'registry' { return Invoke-GsRegistryEvaluation -Evaluation $Evaluation -Evidence $Evidence }
        'secedit' { return Invoke-GsSeceditEvaluation -Evaluation $Evaluation -Evidence $Evidence }
        'service' { return Invoke-GsServiceEvaluation -Evaluation $Evaluation -Evidence $Evidence }
        'defender' { return Invoke-GsDefenderEvaluation -Evaluation $Evaluation -Evidence $Evidence }
        'feature' { return Invoke-GsFeatureEvaluation -Evaluation $Evaluation -Evidence $Evidence }
        'secureboot' { return Invoke-GsSecureBootEvaluation -Evaluation $Evaluation -Evidence $Evidence }
        'bitlocker' { return Invoke-GsBitLockerEvaluation -Evaluation $Evaluation -Evidence $Evidence }
        'auditpol' { return Invoke-GsAuditpolEvaluation -Evaluation $Evaluation -Evidence $Evidence }
        default {
            return New-GsEvalResult -Status 'error' -Expected '' -Actual '' -Message "Unknown evaluation method $method."
        }
    }
}

function Invoke-GsCompositeEvaluation {
    param($Evaluation, $Evidence)
    $method = [string](Get-GsProperty $Evaluation 'method')
    $children = ConvertTo-GsArray (Get-GsProperty $Evaluation 'evaluations')
    if ($children.Count -eq 0) {
        return New-GsEvalResult -Status 'error' -Expected '' -Actual '' -Message "$method has no child evaluations."
    }
    $results = @()
    foreach ($child in $children) {
        $results += @(Invoke-GsEvaluation -Evaluation $child -Evidence $Evidence)
    }
    $pass = 0
    $fail = 0
    $errorCount = 0
    $na = 0
    $messages = @()
    $expectedParts = @()
    $actualParts = @()
    foreach ($result in $results) {
        $expectedParts += [string]$result.Expected
        $actualParts += [string]$result.Actual
        $messages += [string]$result.Message
        switch ($result.Status) {
            'pass' { $pass += 1 }
            'fail' { $fail += 1 }
            'error' { $errorCount += 1 }
            'not_applicable' { $na += 1 }
        }
    }
    $expectedText = ($expectedParts -join ' AND ')
    if ($method -eq 'any_of') {
        $expectedText = ($expectedParts -join ' OR ')
    }
    $actualText = ($actualParts -join ' | ')
    $detail = ($messages -join ' ')
    if ($method -eq 'any_of') {
        if ($pass -gt 0) {
            return New-GsEvalResult -Status 'pass' -Expected $expectedText -Actual $actualText -Message 'At least one alternative matched. '
        }
        if ($fail -gt 0) {
            return New-GsEvalResult -Status 'fail' -Expected $expectedText -Actual $actualText -Message $detail
        }
        if ($errorCount -gt 0) {
            return New-GsEvalResult -Status 'error' -Expected $expectedText -Actual $actualText -Message $detail
        }
        return New-GsEvalResult -Status 'not_applicable' -Expected $expectedText -Actual $actualText -Message $detail
    }
    if ($fail -gt 0) {
        return New-GsEvalResult -Status 'fail' -Expected $expectedText -Actual $actualText -Message $detail
    }
    if ($errorCount -gt 0) {
        return New-GsEvalResult -Status 'error' -Expected $expectedText -Actual $actualText -Message $detail
    }
    if ($na -eq $results.Count) {
        return New-GsEvalResult -Status 'not_applicable' -Expected $expectedText -Actual $actualText -Message $detail
    }
    return New-GsEvalResult -Status 'pass' -Expected $expectedText -Actual $actualText -Message 'All parts matched.'
}

function Invoke-GsRegistryEvaluation {
    param($Evaluation, $Evidence)
    if (Test-GsHasProperty $Evidence 'registry_error') {
        return New-GsEvalResult -Status 'error' -Expected (Format-GsExpected $Evaluation) -Actual '' -Message ([string](Get-GsProperty $Evidence 'registry_error'))
    }
    if (-not (Test-GsHasProperty $Evidence 'registry')) {
        return New-GsEvalResult -Status 'error' -Expected (Format-GsExpected $Evaluation) -Actual '' -Message 'Registry evidence was not collected.'
    }
    $hive = [string](Get-GsProperty $Evaluation 'hive')
    $path = [string](Get-GsProperty $Evaluation 'path')
    $name = [string](Get-GsProperty $Evaluation 'name')
    $found = $null
    foreach ($row in (ConvertTo-GsArray (Get-GsProperty $Evidence 'registry'))) {
        $rowHive = [string](Get-GsProperty $row 'hive')
        $rowPath = [string](Get-GsProperty $row 'path')
        $rowName = [string](Get-GsProperty $row 'name')
        if ([string]::Equals($rowHive, $hive, [System.StringComparison]::OrdinalIgnoreCase) -and
            [string]::Equals($rowPath, $path, [System.StringComparison]::OrdinalIgnoreCase) -and
            [string]::Equals($rowName, $name, [System.StringComparison]::OrdinalIgnoreCase)) {
            $found = $row
            break
        }
    }
    if ($null -eq $found) {
        return New-GsAbsentResult $Evaluation
    }
    return Invoke-GsCompare -Evaluation $Evaluation -Actual (Get-GsProperty $found 'value')
}

function Invoke-GsSeceditEvaluation {
    param($Evaluation, $Evidence)
    if (Test-GsHasProperty $Evidence 'secedit_error') {
        return New-GsEvalResult -Status 'error' -Expected (Format-GsExpected $Evaluation) -Actual '' -Message ([string](Get-GsProperty $Evidence 'secedit_error'))
    }
    if (-not (Test-GsHasProperty $Evidence 'secedit')) {
        return New-GsEvalResult -Status 'error' -Expected (Format-GsExpected $Evaluation) -Actual '' -Message 'Security policy evidence was not collected.'
    }
    $section = [string](Get-GsProperty $Evaluation 'section')
    $key = [string](Get-GsProperty $Evaluation 'key')
    $found = $null
    foreach ($row in (ConvertTo-GsArray (Get-GsProperty $Evidence 'secedit'))) {
        $rowSection = [string](Get-GsProperty $row 'section')
        $rowKey = [string](Get-GsProperty $row 'key')
        if ([string]::Equals($rowSection, $section, [System.StringComparison]::OrdinalIgnoreCase) -and
            [string]::Equals($rowKey, $key, [System.StringComparison]::OrdinalIgnoreCase)) {
            $found = $row
            break
        }
    }
    if ($null -eq $found) {
        return New-GsAbsentResult $Evaluation
    }
    return Invoke-GsCompare -Evaluation $Evaluation -Actual (Get-GsProperty $found 'value')
}

function Invoke-GsServiceEvaluation {
    param($Evaluation, $Evidence)
    if (Test-GsHasProperty $Evidence 'service_error') {
        return New-GsEvalResult -Status 'error' -Expected (Format-GsExpected $Evaluation) -Actual '' -Message ([string](Get-GsProperty $Evidence 'service_error'))
    }
    if (-not (Test-GsHasProperty $Evidence 'services')) {
        return New-GsEvalResult -Status 'error' -Expected (Format-GsExpected $Evaluation) -Actual '' -Message 'Service evidence was not collected.'
    }
    $name = [string](Get-GsProperty $Evaluation 'name')
    $propertyName = [string](Get-GsProperty $Evaluation 'property')
    $found = $null
    foreach ($row in (ConvertTo-GsArray (Get-GsProperty $Evidence 'services'))) {
        $rowName = [string](Get-GsProperty $row 'name')
        if ([string]::Equals($rowName, $name, [System.StringComparison]::OrdinalIgnoreCase)) {
            $found = $row
            break
        }
    }
    if ($null -eq $found) {
        return New-GsAbsentResult $Evaluation
    }
    if (-not (Test-GsHasProperty $found $propertyName)) {
        return New-GsAbsentResult $Evaluation
    }
    return Invoke-GsCompare -Evaluation $Evaluation -Actual (Get-GsProperty $found $propertyName)
}

function Invoke-GsDefenderEvaluation {
    param($Evaluation, $Evidence)
    if (Test-GsHasProperty $Evidence 'defender_error') {
        return New-GsEvalResult -Status 'error' -Expected (Format-GsExpected $Evaluation) -Actual '' -Message ([string](Get-GsProperty $Evidence 'defender_error'))
    }
    $defender = Get-GsProperty $Evidence 'defender'
    if ($null -eq $defender) {
        return New-GsEvalResult -Status 'error' -Expected (Format-GsExpected $Evaluation) -Actual '' -Message 'Microsoft Defender settings were not collected.'
    }
    $propertyName = [string](Get-GsProperty $Evaluation 'property')
    if (-not (Test-GsHasProperty $defender $propertyName)) {
        return New-GsAbsentResult $Evaluation
    }
    return Invoke-GsCompare -Evaluation $Evaluation -Actual (Get-GsProperty $defender $propertyName)
}

function Invoke-GsFeatureEvaluation {
    param($Evaluation, $Evidence)
    if (Test-GsHasProperty $Evidence 'feature_error') {
        return New-GsEvalResult -Status 'error' -Expected (Format-GsExpected $Evaluation) -Actual '' -Message ([string](Get-GsProperty $Evidence 'feature_error'))
    }
    if (-not (Test-GsHasProperty $Evidence 'features')) {
        return New-GsEvalResult -Status 'error' -Expected (Format-GsExpected $Evaluation) -Actual '' -Message 'Windows feature evidence was not collected.'
    }
    $name = [string](Get-GsProperty $Evaluation 'name')
    $found = $null
    foreach ($row in (ConvertTo-GsArray (Get-GsProperty $Evidence 'features'))) {
        $rowName = [string](Get-GsProperty $row 'name')
        if ([string]::Equals($rowName, $name, [System.StringComparison]::OrdinalIgnoreCase)) {
            $found = $row
            break
        }
    }
    if ($null -eq $found) {
        return Invoke-GsCompare -Evaluation $Evaluation -Actual 'NotFound'
    }
    return Invoke-GsCompare -Evaluation $Evaluation -Actual (Get-GsProperty $found 'state')
}

function Invoke-GsSecureBootEvaluation {
    param($Evaluation, $Evidence)
    if (Test-GsHasProperty $Evidence 'secureboot_error') {
        return New-GsEvalResult -Status 'error' -Expected 'true' -Actual '' -Message ([string](Get-GsProperty $Evidence 'secureboot_error'))
    }
    if (-not (Test-GsHasProperty $Evidence 'secureboot')) {
        return New-GsEvalResult -Status 'error' -Expected 'true' -Actual '' -Message 'Secure Boot evidence was not collected.'
    }
    $fake = [pscustomobject]@{
        method   = 'secureboot'
        operator = 'equals'
        expected = (Get-GsProperty $Evaluation 'expected')
    }
    return Invoke-GsCompare -Evaluation $fake -Actual (Get-GsProperty $Evidence 'secureboot')
}

function Invoke-GsBitLockerEvaluation {
    param($Evaluation, $Evidence)
    if (Test-GsHasProperty $Evidence 'bitlocker_error') {
        return New-GsEvalResult -Status 'error' -Expected (Format-GsExpected $Evaluation) -Actual '' -Message ([string](Get-GsProperty $Evidence 'bitlocker_error'))
    }
    if (-not (Test-GsHasProperty $Evidence 'bitlocker')) {
        return New-GsEvalResult -Status 'error' -Expected (Format-GsExpected $Evaluation) -Actual '' -Message 'BitLocker evidence was not collected.'
    }
    $volumeType = [string](Get-GsProperty $Evaluation 'volume_type')
    $propertyName = [string](Get-GsProperty $Evaluation 'property')
    $found = $null
    foreach ($row in (ConvertTo-GsArray (Get-GsProperty $Evidence 'bitlocker'))) {
        $rowType = [string](Get-GsProperty $row 'volume_type')
        if ([string]::Equals($rowType, $volumeType, [System.StringComparison]::OrdinalIgnoreCase)) {
            $found = $row
            break
        }
    }
    if ($null -eq $found) {
        return New-GsEvalResult -Status 'error' -Expected (Format-GsExpected $Evaluation) -Actual '' -Message "No $volumeType BitLocker volume was collected."
    }
    return Invoke-GsCompare -Evaluation $Evaluation -Actual (Get-GsProperty $found $propertyName)
}

function Invoke-GsAuditpolEvaluation {
    param($Evaluation, $Evidence)
    if (Test-GsHasProperty $Evidence 'auditpol_error') {
        return New-GsEvalResult -Status 'error' -Expected (Format-GsExpected $Evaluation) -Actual '' -Message ([string](Get-GsProperty $Evidence 'auditpol_error'))
    }
    if (-not (Test-GsHasProperty $Evidence 'auditpol')) {
        return New-GsEvalResult -Status 'error' -Expected (Format-GsExpected $Evaluation) -Actual '' -Message 'Audit policy evidence was not collected.'
    }
    $subcategory = [string](Get-GsProperty $Evaluation 'subcategory')
    $wantedGuid = ConvertTo-GsAuditGuid -Value ([string](Get-GsProperty $Evaluation 'subcategory_guid'))
    $wanted = Resolve-GsAuditSubcategory -Name $subcategory -Guid $wantedGuid
    if ([string]::IsNullOrWhiteSpace($wantedGuid)) {
        $wantedGuid = [string]$wanted.Guid
    }
    $found = $null
    foreach ($row in (ConvertTo-GsArray (Get-GsProperty $Evidence 'auditpol'))) {
        $rowName = [string](Get-GsProperty $row 'subcategory')
        $rowGuid = ConvertTo-GsAuditGuid -Value ([string](Get-GsProperty $row 'subcategory_guid'))
        $resolved = Resolve-GsAuditSubcategory -Name $rowName -Guid $rowGuid
        if ([string]::IsNullOrWhiteSpace($rowGuid)) {
            $rowGuid = [string]$resolved.Guid
        }
        $guidHit = (-not [string]::IsNullOrWhiteSpace($wantedGuid)) -and ($wantedGuid -eq $rowGuid)
        $nameHit = (-not [string]::IsNullOrWhiteSpace([string]$wanted.Name)) -and [string]::Equals([string]$wanted.Name, [string]$resolved.Name, [System.StringComparison]::OrdinalIgnoreCase)
        if ($guidHit -or $nameHit) {
            $found = $row
            break
        }
    }
    if ($null -eq $found) {
        $expectedText = Format-GsExpected $Evaluation
        return New-GsEvalResult -Status 'error' -Expected $expectedText -Actual '' -Message "Subcategory '$subcategory' was not in the collected audit policy."
    }
    $setting = ConvertTo-GsAuditSetting ([string](Get-GsProperty $found 'setting'))
    return Invoke-GsCompare -Evaluation $Evaluation -Actual $setting
}

function ConvertFrom-GsSeceditText {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Text)
    $rows = @()
    $section = ''
    foreach ($line in ($Text -split "`r?`n")) {
        $trim = $line.Trim()
        if ($trim.Length -eq 0 -or $trim.StartsWith(';')) {
            continue
        }
        if ($trim.StartsWith('[') -and $trim.EndsWith(']')) {
            $section = $trim.Substring(1, $trim.Length - 2).Trim()
            continue
        }
        $eq = $trim.IndexOf('=')
        if ($eq -lt 1 -or [string]::IsNullOrWhiteSpace($section)) {
            continue
        }
        $key = $trim.Substring(0, $eq).Trim()
        $value = $trim.Substring($eq + 1).Trim()
        if ($value.Length -ge 2 -and $value.StartsWith('"') -and $value.EndsWith('"')) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        $rows += [pscustomobject]@{
            section = $section
            key     = $key
            value   = $value
        }
    }
    return $rows
}

function ConvertFrom-GsAuditpolText {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Text)
    $rows = @()
    $noAudit = [regex]::Escape((Get-GsGermanNoAuditing))
    $pattern = '(?i)^(?<name>.+?)\s{2,}(?<setting>Success and Failure|No Auditing|Success|Failure|Erfolg und Fehler|' + $noAudit + '|Erfolg|Fehler)\s*$'
    $regex = New-Object System.Text.RegularExpressions.Regex $pattern
    foreach ($line in ($Text -split "`r?`n")) {
        $match = $regex.Match($line.Trim())
        if (-not $match.Success) {
            continue
        }
        $resolved = Resolve-GsAuditSubcategory -Name $match.Groups['name'].Value.Trim() -Guid ''
        $rows += [pscustomobject]@{
            subcategory      = [string]$resolved.Name
            subcategory_guid = [string]$resolved.Guid
            setting          = (ConvertTo-GsAuditSetting $match.Groups['setting'].Value)
        }
    }
    return $rows
}

function Split-GsCsvLine {
    param([string]$Line)
    $cols = New-Object System.Collections.Generic.List[string]
    foreach ($part in $Line.Split(',')) {
        [void]$cols.Add($part.Trim().Trim('"'))
    }
    Write-Output -NoEnumerate $cols.ToArray()
}

function ConvertFrom-GsAuditpolCsv {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Text)
    $rows = @()
    $lines = @($Text -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($lines.Count -lt 1) {
        return $rows
    }
    $header = Split-GsCsvLine -Line $lines[0]
    $subIndex = -1
    $setIndex = -1
    $guidIndex = -1
    for ($i = 0; $i -lt $header.Count; $i++) {
        $name = [string]$header[$i]
        if ($name -eq 'Subcategory' -or $name -eq 'Unterkategorie') {
            $subIndex = $i
        }
        elseif ($name -eq 'Inclusion Setting' -or $name -eq 'Einschlusseinstellung') {
            $setIndex = $i
        }
        elseif ($name -eq 'Subcategory GUID' -or $name -eq 'Unterkategorie-GUID' -or $name -eq 'Unterkategorie GUID') {
            $guidIndex = $i
        }
    }
    $start = 1
    if ($subIndex -lt 0 -or $setIndex -lt 0) {
        # auditpol /r keeps this column order in every display language:
        # machine, policy target, subcategory, subcategory GUID, inclusion, exclusion.
        if ($header.Count -ge 5) {
            $subIndex = 2
            $guidIndex = 3
            $setIndex = 4
            $headerGuid = ''
            if ($header.Count -gt 3) {
                $headerGuid = ConvertTo-GsAuditGuid -Value ([string]$header[3])
            }
            if (-not [string]::IsNullOrWhiteSpace($headerGuid)) {
                $start = 0
            }
        }
        else {
            throw 'auditpol CSV is missing Subcategory or Inclusion Setting.'
        }
    }
    if ($lines.Count -le $start) {
        return $rows
    }
    for ($n = $start; $n -lt $lines.Count; $n++) {
        $cols = Split-GsCsvLine -Line $lines[$n]
        if ($cols.Count -le $setIndex) { continue }
        $name = [string]$cols[$subIndex]
        $setting = [string]$cols[$setIndex]
        $guid = ''
        if ($guidIndex -ge 0 -and $cols.Count -gt $guidIndex) {
            $guid = [string]$cols[$guidIndex]
        }
        if ([string]::IsNullOrWhiteSpace($name) -and [string]::IsNullOrWhiteSpace($guid)) { continue }
        $resolved = Resolve-GsAuditSubcategory -Name $name -Guid $guid
        $rows += [pscustomobject]@{
            subcategory      = [string]$resolved.Name
            subcategory_guid = [string]$resolved.Guid
            setting          = (ConvertTo-GsAuditSetting $setting)
        }
    }
    return $rows
}

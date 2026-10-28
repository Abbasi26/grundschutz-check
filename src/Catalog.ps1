Set-StrictMode -Version 1.0

function ConvertTo-GsArray {
    param($Value)
    if ($null -eq $Value) {
        return @()
    }
    return @($Value)
}

function Get-GsProperty {
    param($Object, [string]$Name)
    if ($null -eq $Object) {
        return $null
    }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) {
            return $Object[$Name]
        }
        return $null
    }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) {
        return $null
    }
    return $prop.Value
}

function Test-GsHasProperty {
    param($Object, [string]$Name)
    if ($null -eq $Object) {
        return $false
    }
    if ($Object -is [System.Collections.IDictionary]) {
        return $Object.Contains($Name)
    }
    return $null -ne $Object.PSObject.Properties[$Name]
}

function Read-GsJsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "File not found: $Path"
    }
    $utf8 = New-Object System.Text.UTF8Encoding $false
    $raw = [System.IO.File]::ReadAllText($Path, $utf8)
    if ($raw.Length -gt 0 -and [int][char]$raw[0] -eq 0xFEFF) {
        $raw = $raw.Substring(1)
    }
    return ($raw | ConvertFrom-Json)
}

function Get-GsCatalog {
    [CmdletBinding()]
    param(
        [string]$Path
    )
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Join-Path $script:GsModuleRoot 'catalog/windows11-client.json'
    }
    $catalog = Read-GsJsonFile -Path $Path
    Add-Member -InputObject $catalog -NotePropertyName SourcePath -NotePropertyValue $Path -Force
    return $catalog
}

function Get-GsEvaluationNodes {
    param($Evaluation)
    $nodes = @()
    if ($null -eq $Evaluation) {
        return $nodes
    }
    $method = [string](Get-GsProperty $Evaluation 'method')
    if ($method -eq 'all_of' -or $method -eq 'any_of') {
        foreach ($child in (ConvertTo-GsArray (Get-GsProperty $Evaluation 'evaluations'))) {
            $nodes += @(Get-GsEvaluationNodes -Evaluation $child)
        }
        return $nodes
    }
    return @($Evaluation)
}

function Test-GsOperatorName {
    param([string]$Name)
    switch ($Name) {
        'equals' { return $true }
        'not_equals' { return $true }
        'greater_or_equal' { return $true }
        'less_or_equal' { return $true }
        'in_range' { return $true }
        'one_of' { return $true }
        'bits_set' { return $true }
        default { return $false }
    }
}

function Test-GsEvaluationShape {
    param($Evaluation, [string]$CheckId, [System.Collections.Generic.List[string]]$Errors, [int]$Depth)
    if ($Depth -gt 4) {
        $Errors.Add("$CheckId evaluation is nested more than 4 levels.")
        return
    }
    if ($null -eq $Evaluation) {
        $Errors.Add("$CheckId is missing evaluation.")
        return
    }
    $method = [string](Get-GsProperty $Evaluation 'method')
    $known = @('registry', 'secedit', 'service', 'defender', 'feature', 'secureboot', 'bitlocker', 'auditpol', 'all_of', 'any_of')
    if ($known -notcontains $method) {
        $Errors.Add("$CheckId uses unknown evaluation method '$method'.")
        return
    }
    if ($method -eq 'all_of' -or $method -eq 'any_of') {
        $children = @(ConvertTo-GsArray (Get-GsProperty $Evaluation 'evaluations'))
        if ($children.Count -lt 1) {
            $Errors.Add("$CheckId $method has no child evaluations.")
        }
        foreach ($child in $children) {
            Test-GsEvaluationShape -Evaluation $child -CheckId $CheckId -Errors $Errors -Depth ($Depth + 1)
        }
        return
    }
    if ($method -ne 'secureboot') {
        $operatorName = [string](Get-GsProperty $Evaluation 'operator')
        if (-not (Test-GsOperatorName $operatorName)) {
            $Errors.Add("$CheckId uses unknown operator '$operatorName'.")
        }
    }
    $when = [string](Get-GsProperty $Evaluation 'when_absent')
    if (-not [string]::IsNullOrWhiteSpace($when)) {
        if (@('fail', 'pass', 'not_applicable') -notcontains $when) {
            $Errors.Add("$CheckId when_absent '$when' is not fail, pass, or not_applicable.")
        }
    }
    if ($method -eq 'registry') {
        foreach ($field in @('hive', 'path', 'name')) {
            if ([string]::IsNullOrWhiteSpace([string](Get-GsProperty $Evaluation $field))) {
                $Errors.Add("$CheckId registry evaluation is missing $field.")
            }
        }
    }
    if ($method -eq 'secedit') {
        foreach ($field in @('section', 'key')) {
            if ([string]::IsNullOrWhiteSpace([string](Get-GsProperty $Evaluation $field))) {
                $Errors.Add("$CheckId secedit evaluation is missing $field.")
            }
        }
    }
    if ($method -eq 'service') {
        foreach ($field in @('name', 'property')) {
            if ([string]::IsNullOrWhiteSpace([string](Get-GsProperty $Evaluation $field))) {
                $Errors.Add("$CheckId service evaluation is missing $field.")
            }
        }
    }
    if ($method -eq 'defender' -or $method -eq 'feature' -or $method -eq 'auditpol' -or $method -eq 'bitlocker') {
        $required = @('name')
        if ($method -eq 'defender') { $required = @('property') }
        if ($method -eq 'auditpol') { $required = @('subcategory') }
        if ($method -eq 'bitlocker') { $required = @('volume_type', 'property') }
        foreach ($field in $required) {
            if ([string]::IsNullOrWhiteSpace([string](Get-GsProperty $Evaluation $field))) {
                $Errors.Add("$CheckId $method evaluation is missing $field.")
            }
        }
    }
    if ($method -eq 'auditpol') {
        $guidText = [string](Get-GsProperty $Evaluation 'subcategory_guid')
        if (-not [string]::IsNullOrWhiteSpace($guidText)) {
            if ($guidText -notmatch '^\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}$') {
                $Errors.Add("$CheckId audit subcategory_guid is not a GUID.")
            }
        }
    }
}

function Test-GsCatalog {
    [CmdletBinding()]
    param($Catalog)
    $errors = New-Object 'System.Collections.Generic.List[string]'
    if ($null -eq $Catalog) {
        $errors.Add('Catalog is null.')
        return $errors
    }
    $schemaVersion = [string](Get-GsProperty $Catalog 'schema_version')
    if ($schemaVersion -ne '0.1.0') {
        $errors.Add("schema_version must be 0.1.0 (found '$schemaVersion').")
    }
    $meta = Get-GsProperty $Catalog 'catalog'
    foreach ($field in @('id', 'title', 'version')) {
        if ([string]::IsNullOrWhiteSpace([string](Get-GsProperty $meta $field))) {
            $errors.Add("catalog.$field is required.")
        }
    }
    $checks = @(ConvertTo-GsArray (Get-GsProperty $Catalog 'checks'))
    if ($checks.Count -lt 40) {
        $errors.Add("Catalog has $($checks.Count) checks; v0.1 expects at least 40.")
    }
    $seen = @{}
    $severities = @('critical', 'high', 'medium', 'low', 'informational')
    $mappings = @('verified', 'unverified')
    foreach ($check in $checks) {
        $id = [string](Get-GsProperty $check 'id')
        if ([string]::IsNullOrWhiteSpace($id)) {
            $errors.Add('A check is missing id.')
            continue
        }
        if ($seen.ContainsKey($id)) {
            $errors.Add("Duplicate check id $id.")
        }
        else {
            $seen[$id] = $true
        }
        if ($id -notmatch '^[A-Z0-9][A-Z0-9._-]{2,80}$') {
            $errors.Add("$id does not match the id pattern.")
        }
        foreach ($field in @('title', 'rationale', 'severity', 'mapping', 'windows11_carryover')) {
            if ([string]::IsNullOrWhiteSpace([string](Get-GsProperty $check $field))) {
                $errors.Add("$id is missing $field.")
            }
        }
        $severity = [string](Get-GsProperty $check 'severity')
        if ($severities -notcontains $severity) {
            $errors.Add("$id severity '$severity' is not supported.")
        }
        $mapping = [string](Get-GsProperty $check 'mapping')
        if ($mappings -notcontains $mapping) {
            $errors.Add("$id mapping '$mapping' is not verified or unverified.")
        }
        $carry = [string](Get-GsProperty $check 'windows11_carryover')
        if ($mappings -notcontains $carry) {
            $errors.Add("$id windows11_carryover '$carry' is not verified or unverified.")
        }
        $module = Get-GsProperty $check 'module'
        if ([string]::IsNullOrWhiteSpace([string](Get-GsProperty $module 'id'))) {
            $errors.Add("$id is missing module.id.")
        }
        $refs = @(ConvertTo-GsArray (Get-GsProperty $check 'references'))
        if ($refs.Count -lt 1) {
            $errors.Add("$id has no references.")
        }
        $verifiedRefs = 0
        foreach ($ref in $refs) {
            $refMapping = [string](Get-GsProperty $ref 'mapping')
            if ($mappings -notcontains $refMapping) {
                $errors.Add("$id reference mapping '$refMapping' is invalid.")
            }
            $framework = [string](Get-GsProperty $ref 'framework')
            if ([string]::IsNullOrWhiteSpace($framework)) {
                $errors.Add("$id reference is missing framework.")
            }
            $requirementId = Get-GsProperty $ref 'requirement_id'
            if ($refMapping -eq 'verified') {
                $verifiedRefs += 1
                if ([string]::IsNullOrWhiteSpace([string]$requirementId)) {
                    $errors.Add("$id has a verified reference without a requirement id.")
                }
            }
            if ($null -ne $requirementId -and -not [string]::IsNullOrWhiteSpace([string]$requirementId)) {
                $idText = [string]$requirementId
                if ($framework -eq 'it-grundschutz-kompendium') {
                    if ($idText -notmatch '^(SYS|OPS|ORP|CON|DER|APP|NET|INF|IND)\.[0-9]+(\.[0-9]+)*\.A[0-9]+$') {
                        $errors.Add("$id Kompendium id '$idText' does not match the published id shape.")
                    }
                }
                if ($framework -eq 'grundschutz-plus-plus') {
                    if ($idText -notmatch '^(GC|STM|UMS|VRB|PERF|RISK|ASST|PERS|BES|DLS|TEST|GEB|SENS|ARCH|BER|NOT|DET|KONF|DEV|REA)\.[0-9]+(\.[0-9]+)*$') {
                        $errors.Add("$id Grundschutz++ id '$idText' does not match the catalog id shape.")
                    }
                }
            }
        }
        if ($mapping -eq 'verified' -and $verifiedRefs -lt 1) {
            $errors.Add("$id is mapping verified but has no verified reference.")
        }
        $remediation = Get-GsProperty $check 'remediation'
        foreach ($field in @('summary', 'gpo', 'intune', 'registry')) {
            if ([string]::IsNullOrWhiteSpace([string](Get-GsProperty $remediation $field))) {
                $errors.Add("$id remediation is missing $field.")
            }
        }
        Test-GsEvaluationShape -Evaluation (Get-GsProperty $check 'evaluation') -CheckId $id -Errors $errors -Depth 0
    }
    return $errors
}

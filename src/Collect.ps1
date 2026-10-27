Set-StrictMode -Version 1.0

function Test-GsWindows {
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        return [bool]$IsWindows
    }
    return $true
}

function Get-GsCanonicalHostString {
    param($HostInfo)
    $name = [string](Get-GsProperty $HostInfo 'computer_name')
    $domain = [string](Get-GsProperty $HostInfo 'domain')
    $caption = [string](Get-GsProperty $HostInfo 'os_caption')
    $version = [string](Get-GsProperty $HostInfo 'os_version')
    $build = [string](Get-GsProperty $HostInfo 'os_build')
    return ("v1`ncomputer_name={0}`ndomain={1}`nos_caption={2}`nos_version={3}`nos_build={4}`n" -f $name, $domain, $caption, $version, $build)
}

function Get-GsHostFingerprint {
    param($HostInfo)
    $canonical = Get-GsCanonicalHostString -HostInfo $HostInfo
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($canonical)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($bytes)
    }
    finally {
        $sha.Dispose()
    }
    return ([System.BitConverter]::ToString($hash).Replace('-', '').ToLowerInvariant())
}

function Get-GsDemoEvidence {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Join-Path $script:GsModuleRoot 'demo/evidence.json'
    }
    $evidence = Read-GsJsonFile -Path $Path
    if (-not (Test-GsHasProperty $evidence 'host')) {
        throw 'Demo evidence is missing the host object.'
    }
    return $evidence
}

function Add-GsUniqueString {
    param($List, [string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return }
    if ($List -notcontains $Value) {
        [void]$List.Add($Value)
    }
}

function Get-GsRequestedReads {
    param($Catalog)
    $registry = New-Object System.Collections.Generic.List[object]
    $services = New-Object 'System.Collections.Generic.List[string]'
    $features = New-Object 'System.Collections.Generic.List[string]'
    $defender = New-Object 'System.Collections.Generic.List[string]'
    $auditGuids = New-Object 'System.Collections.Generic.List[string]'
    $needs = @{
        secedit    = $false
        auditpol   = $false
        secureboot = $false
        bitlocker  = $false
    }
    foreach ($check in (ConvertTo-GsArray (Get-GsProperty $Catalog 'checks'))) {
        foreach ($node in (Get-GsEvaluationNodes -Evaluation (Get-GsProperty $check 'evaluation'))) {
            $method = [string](Get-GsProperty $node 'method')
            switch ($method) {
                'registry' {
                    $registry.Add([pscustomobject]@{
                            hive = [string](Get-GsProperty $node 'hive')
                            path = [string](Get-GsProperty $node 'path')
                            name = [string](Get-GsProperty $node 'name')
                        })
                }
                'secedit' { $needs.secedit = $true }
                'auditpol' {
                    $needs.auditpol = $true
                    $resolved = Resolve-GsAuditSubcategory -Name ([string](Get-GsProperty $node 'subcategory')) -Guid ([string](Get-GsProperty $node 'subcategory_guid'))
                    if (-not [string]::IsNullOrWhiteSpace([string]$resolved.Guid)) {
                        Add-GsUniqueString -List $auditGuids -Value ([string]$resolved.Guid)
                    }
                }
                'secureboot' { $needs.secureboot = $true }
                'bitlocker' { $needs.bitlocker = $true }
                'service' { Add-GsUniqueString -List $services -Value ([string](Get-GsProperty $node 'name')) }
                'feature' { Add-GsUniqueString -List $features -Value ([string](Get-GsProperty $node 'name')) }
                'defender' { Add-GsUniqueString -List $defender -Value ([string](Get-GsProperty $node 'property')) }
            }
        }
    }
    return [pscustomobject]@{
        Registry    = $registry
        Services    = $services
        Features    = $features
        Defender    = $defender
        AuditGuids  = $auditGuids
        Needs       = $needs
    }
}

function Get-GsAuditpolArgumentList {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$SubcategoryGuid)
    $guid = ConvertTo-GsAuditGuid -Value $SubcategoryGuid
    if ([string]::IsNullOrWhiteSpace($guid)) {
        throw 'Audit subcategory GUID is not valid.'
    }
    return @('/get', ('/subcategory:{0}' -f $guid), '/r')
}

function Select-GsAuditpolRow {
    param($Rows, [string]$SubcategoryGuid)
    $wanted = ConvertTo-GsAuditGuid -Value $SubcategoryGuid
    if ([string]::IsNullOrWhiteSpace($wanted)) {
        return $null
    }
    foreach ($row in @($Rows)) {
        $rowGuid = ConvertTo-GsAuditGuid -Value ([string](Get-GsProperty $row 'subcategory_guid'))
        if ($rowGuid -eq $wanted) {
            return $row
        }
    }
    $canonical = ''
    foreach ($entry in (Get-GsAuditSubcategoryTable)) {
        if ([string]$entry.Guid -eq $wanted) {
            $canonical = [string]$entry.Name
            break
        }
    }
    if ([string]::IsNullOrWhiteSpace($canonical)) {
        return $null
    }
    foreach ($row in @($Rows)) {
        $resolved = Resolve-GsAuditSubcategory -Name ([string](Get-GsProperty $row 'subcategory')) -Guid ([string](Get-GsProperty $row 'subcategory_guid'))
        if ([string]::Equals([string]$resolved.Name, $canonical, [System.StringComparison]::OrdinalIgnoreCase)) {
            if ($resolved.MatchedBy -eq 'name' -or $resolved.MatchedBy -eq 'alias' -or $resolved.MatchedBy -eq 'guid') {
                return $row
            }
        }
    }
    return $null
}

function Merge-GsAuditpolQueries {
    <#
    .SYNOPSIS
        Prefers per-GUID auditpol CSV text and fills gaps from a category-wide CSV.
    #>
    param(
        [string[]]$SubcategoryGuids,
        $QueryTextByGuid,
        [string]$FallbackText
    )
    $collected = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    $pending = New-Object 'System.Collections.Generic.List[string]'
    foreach ($guid in @($SubcategoryGuids)) {
        $norm = ConvertTo-GsAuditGuid -Value ([string]$guid)
        if ([string]::IsNullOrWhiteSpace($norm)) { continue }
        $text = $null
        if ($null -ne $QueryTextByGuid) {
            $text = Get-GsProperty $QueryTextByGuid $norm
            if ($null -eq $text) {
                $text = Get-GsProperty $QueryTextByGuid ([string]$guid)
            }
        }
        $match = $null
        if (-not [string]::IsNullOrWhiteSpace([string]$text)) {
            $parsed = @(ConvertFrom-GsAuditpolCsv -Text ([string]$text))
            $match = Select-GsAuditpolRow -Rows $parsed -SubcategoryGuid $norm
        }
        if ($null -eq $match) {
            [void]$pending.Add($norm)
            continue
        }
        if (-not $seen.ContainsKey($norm)) {
            $seen[$norm] = $true
            [void]$collected.Add($match)
        }
    }
    $fallbackRows = @()
    if (-not [string]::IsNullOrWhiteSpace($FallbackText)) {
        $fallbackRows = @(ConvertFrom-GsAuditpolCsv -Text $FallbackText)
    }
    foreach ($guid in @($pending)) {
        $match = Select-GsAuditpolRow -Rows $fallbackRows -SubcategoryGuid $guid
        if ($null -ne $match -and -not $seen.ContainsKey($guid)) {
            $seen[$guid] = $true
            [void]$collected.Add($match)
        }
    }
    foreach ($row in @($fallbackRows)) {
        $rowGuid = ConvertTo-GsAuditGuid -Value ([string](Get-GsProperty $row 'subcategory_guid'))
        if ([string]::IsNullOrWhiteSpace($rowGuid)) {
            $resolved = Resolve-GsAuditSubcategory -Name ([string](Get-GsProperty $row 'subcategory')) -Guid ''
            $rowGuid = [string]$resolved.Guid
        }
        if (-not [string]::IsNullOrWhiteSpace($rowGuid) -and $seen.ContainsKey($rowGuid)) {
            continue
        }
        $key = $rowGuid
        if ([string]::IsNullOrWhiteSpace($key)) {
            $key = 'name:' + [string](Get-GsProperty $row 'subcategory')
        }
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        [void]$collected.Add($row)
    }
    foreach ($item in $collected) {
        Write-Output $item
    }
}

function Read-GsMaybeUnicodeFile {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 255 -and $bytes[1] -eq 254) {
        return [System.Text.Encoding]::Unicode.GetString($bytes)
    }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) {
        return [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    }
    return [System.Text.Encoding]::UTF8.GetString($bytes)
}

function Get-GsLocalEvidence {
    param($Catalog)
    if (-not (Test-GsWindows)) {
        throw 'Local collection is only implemented on Windows.'
    }
    $reads = Get-GsRequestedReads -Catalog $Catalog
    $computer = [string]$env:COMPUTERNAME
    $domain = ''
    $caption = ''
    $version = ''
    $build = ''
    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem
        $domain = [string]$cs.Domain
        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        $caption = [string]$os.Caption
        $version = [string]$os.Version
        $build = [string]$os.BuildNumber
    }
    catch {
        $caption = 'Windows'
    }
    $evidence = [ordered]@{
        host     = [ordered]@{
            computer_name = $computer
            domain        = $domain
            os_caption    = $caption
            os_version    = $version
            os_build      = $build
        }
        registry = @()
        notes    = @(
            'Collected locally. No network call was made.',
            'The host name is hashed into host_fingerprint_sha256 and is not written into the report.'
        )
    }

    $registryRows = @()
    foreach ($read in $reads.Registry) {
        if ($read.hive -ne 'HKLM') {
            continue
        }
        $full = 'Registry::HKEY_LOCAL_MACHINE\' + $read.path
        try {
            $item = Get-ItemProperty -LiteralPath $full -Name $read.name -ErrorAction Stop
            $value = $item.PSObject.Properties[$read.name].Value
            $registryRows += [pscustomobject]@{
                hive  = 'HKLM'
                path  = $read.path
                name  = $read.name
                value = $value
            }
        }
        catch {
            # A missing value is absence, not a collector failure.
        }
    }
    $evidence.registry = $registryRows

    if ($reads.Needs.secedit) {
        $tmp = Join-Path $env:TEMP ('gsc-secedit-{0}.inf' -f ([guid]::NewGuid().ToString('n')))
        try {
            & secedit.exe /export /cfg $tmp /quiet | Out-Null
            if (-not (Test-Path -LiteralPath $tmp)) {
                $evidence.secedit_error = 'secedit /export did not write a policy file. Local administrator rights are required.'
            }
            else {
                $text = Read-GsMaybeUnicodeFile -Path $tmp
                $evidence.secedit = @(ConvertFrom-GsSeceditText -Text $text)
            }
        }
        catch {
            $evidence.secedit_error = ('secedit export failed: {0}' -f $_.Exception.Message)
        }
        finally {
            if (Test-Path -LiteralPath $tmp) {
                Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
            }
        }
    }

    if ($reads.Services.Count -gt 0) {
        $serviceRows = @()
        foreach ($name in $reads.Services) {
            try {
                $svc = Get-CimInstance -ClassName Win32_Service -Filter ("Name='{0}'" -f ($name.Replace("'", "''")))
                if ($null -eq $svc) {
                    continue
                }
                $startType = [string]$svc.StartMode
                if ($startType -eq 'Auto') { $startType = 'Automatic' }
                $serviceRows += [pscustomobject]@{
                    name       = [string]$svc.Name
                    start_type = $startType
                    status     = [string]$svc.State
                }
            }
            catch {
                $evidence.service_error = ('Service query failed: {0}' -f $_.Exception.Message)
                break
            }
        }
        $evidence.services = $serviceRows
    }

    if ($reads.Defender.Count -gt 0) {
        if (-not (Get-Command -Name Get-MpPreference -ErrorAction SilentlyContinue)) {
            $evidence.defender_error = 'Get-MpPreference is not available.'
        }
        else {
            try {
                $pref = Get-MpPreference
                $bag = [ordered]@{}
                foreach ($propertyName in $reads.Defender) {
                    $prop = $pref.PSObject.Properties[$propertyName]
                    if ($null -ne $prop) {
                        $bag[$propertyName] = $prop.Value
                    }
                }
                $evidence.defender = [pscustomobject]$bag
            }
            catch {
                $evidence.defender_error = ('Get-MpPreference failed: {0}' -f $_.Exception.Message)
            }
        }
    }

    if ($reads.Features.Count -gt 0) {
        if (-not (Get-Command -Name Get-WindowsOptionalFeature -ErrorAction SilentlyContinue)) {
            $evidence.feature_error = 'Get-WindowsOptionalFeature is not available.'
        }
        else {
            $featureRows = @()
            foreach ($name in $reads.Features) {
                try {
                    $feature = Get-WindowsOptionalFeature -Online -FeatureName $name -ErrorAction Stop
                    $featureRows += [pscustomobject]@{
                        name  = $name
                        state = [string]$feature.State
                    }
                }
                catch {
                    $featureRows += [pscustomobject]@{
                        name  = $name
                        state = 'NotFound'
                    }
                }
            }
            $evidence.features = $featureRows
        }
    }

    if ($reads.Needs.secureboot) {
        if (-not (Get-Command -Name Confirm-SecureBootUEFI -ErrorAction SilentlyContinue)) {
            $evidence.secureboot_error = 'Confirm-SecureBootUEFI is not available.'
        }
        else {
            try {
                $evidence.secureboot = [bool](Confirm-SecureBootUEFI)
            }
            catch {
                $evidence.secureboot_error = ('Secure Boot could not be read: {0}' -f $_.Exception.Message)
            }
        }
    }

    if ($reads.Needs.bitlocker) {
        if (-not (Get-Command -Name Get-BitLockerVolume -ErrorAction SilentlyContinue)) {
            $evidence.bitlocker_error = 'Get-BitLockerVolume is not available.'
        }
        else {
            try {
                $volumes = @()
                foreach ($volume in @(Get-BitLockerVolume)) {
                    $volumes += [pscustomobject]@{
                        mount              = [string]$volume.MountPoint
                        volume_type        = [string]$volume.VolumeType
                        protection_status  = [string]$volume.ProtectionStatus
                    }
                }
                $evidence.bitlocker = $volumes
            }
            catch {
                $evidence.bitlocker_error = ('BitLocker query failed: {0}' -f $_.Exception.Message)
            }
        }
    }

    if ($reads.Needs.auditpol) {
        try {
            $queryText = @{}
            foreach ($guid in @($reads.AuditGuids)) {
                $norm = ConvertTo-GsAuditGuid -Value ([string]$guid)
                if ([string]::IsNullOrWhiteSpace($norm)) { continue }
                try {
                    $argumentList = Get-GsAuditpolArgumentList -SubcategoryGuid $norm
                    $output = & auditpol.exe @argumentList
                    if ($LASTEXITCODE -ne 0) { continue }
                    $queryText[$norm] = (@($output) -join "`n")
                }
                catch {
                    continue
                }
            }
            $fallbackText = ''
            try {
                $fallback = & auditpol.exe /get /category:* /r
                if ($LASTEXITCODE -eq 0) {
                    $fallbackText = @($fallback) -join "`n"
                }
            }
            catch {
                $fallbackText = ''
            }
            try {
                $rows = @(Merge-GsAuditpolQueries -SubcategoryGuids @($reads.AuditGuids) -QueryTextByGuid $queryText -FallbackText $fallbackText)
            }
            catch {
                $rows = @(Merge-GsAuditpolQueries -SubcategoryGuids @($reads.AuditGuids) -QueryTextByGuid $queryText -FallbackText '')
            }
            if ($rows.Count -eq 0) {
                $evidence.auditpol_error = 'auditpol /get failed. Local administrator rights are required.'
            }
            else {
                $evidence.auditpol = $rows
            }
        }
        catch {
            $evidence.auditpol_error = ('auditpol failed: {0}' -f $_.Exception.Message)
        }
    }

    return [pscustomobject]$evidence
}

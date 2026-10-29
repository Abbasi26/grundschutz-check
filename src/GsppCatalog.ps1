Set-StrictMode -Version 1.0

function Read-GsppJsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "File not found: $Path"
    }
    $fullPath = (Resolve-Path -LiteralPath $Path).ProviderPath
    $utf8 = New-Object System.Text.UTF8Encoding $false
    $raw = [System.IO.File]::ReadAllText($fullPath, $utf8)
    if ($raw.Length -gt 0 -and [int][char]$raw[0] -eq 0xFEFF) {
        $raw = $raw.Substring(1)
    }
    if ($PSVersionTable.PSVersion.Major -le 5) {
        Add-Type -AssemblyName System.Web.Extensions
        $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        $serializer.MaxJsonLength = [int]::MaxValue
        return $serializer.DeserializeObject($raw)
    }
    # Keep ISO 8601 strings such as metadata.version as text (PowerShell 7.5+).
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) {
        return ($raw | ConvertFrom-Json -DateKind String)
    }
    return ($raw | ConvertFrom-Json)
}

function Get-GsppPropertyValue {
    param($Properties, [string]$Name)
    foreach ($property in (ConvertTo-GsArray $Properties)) {
        if ([string](Get-GsProperty $property 'name') -eq $Name) {
            return [string](Get-GsProperty $property 'value')
        }
    }
    return ''
}

function Get-GsppPartProse {
    param($Parts, [string]$Name)
    $prose = @()
    foreach ($part in (ConvertTo-GsArray $Parts)) {
        if ([string](Get-GsProperty $part 'name') -eq $Name) {
            $prose += [string](Get-GsProperty $part 'prose')
        }
    }
    return ($prose -join "`n")
}

function Expand-GsppParameters {
    param([string]$Text, $Parameters)
    $values = @{}
    foreach ($parameter in (ConvertTo-GsArray $Parameters)) {
        $id = [string](Get-GsProperty $parameter 'id')
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        $parameterValues = @()
        foreach ($value in (ConvertTo-GsArray (Get-GsProperty $parameter 'values'))) {
            $parameterValues += [string]$value
        }
        if ($parameterValues.Count -gt 0) {
            $values[$id] = ($parameterValues -join ', ')
        }
        else {
            $values[$id] = [string](Get-GsProperty $parameter 'label')
        }
    }
    return [regex]::Replace($Text, '\{\{\s*insert:\s*param,\s*([^}\s]+)\s*\}\}', [System.Text.RegularExpressions.MatchEvaluator]{
        param($match)
        $id = $match.Groups[1].Value
        if ($values.ContainsKey($id)) { return $values[$id] }
        return $match.Value
    })
}

function Add-GsppControls {
    param($Controls, [string]$Practice, $Group, [System.Collections.Generic.List[object]]$Output)
    foreach ($control in (ConvertTo-GsArray $Controls)) {
        $statementPart = $null
        foreach ($part in (ConvertTo-GsArray (Get-GsProperty $control 'parts'))) {
            if ([string](Get-GsProperty $part 'name') -eq 'statement') {
                $statementPart = $part
                break
            }
        }
        $statement = Expand-GsppParameters -Text (Get-GsppPartProse -Parts (Get-GsProperty $control 'parts') -Name 'statement') -Parameters (Get-GsProperty $control 'params')
        $Output.Add([pscustomobject][ordered]@{
            Id            = [string](Get-GsProperty $control 'id')
            Title         = [string](Get-GsProperty $control 'title')
            Practice      = $Practice
            GroupId       = [string](Get-GsProperty $Group 'id')
            GroupTitle    = [string](Get-GsProperty $Group 'title')
            SecurityLevel = Get-GsppPropertyValue -Properties (Get-GsProperty $control 'props') -Name 'sec_level'
            EffortLevel   = Get-GsppPropertyValue -Properties (Get-GsProperty $control 'props') -Name 'effort_level'
            ModalVerb     = Get-GsppPropertyValue -Properties (Get-GsProperty $statementPart 'props') -Name 'modal_verb'
            ActionWord    = Get-GsppPropertyValue -Properties (Get-GsProperty $statementPart 'props') -Name 'action_word'
            Statement     = $statement
            Guidance      = Get-GsppPartProse -Parts (Get-GsProperty $control 'parts') -Name 'guidance'
            Tags          = Get-GsppPropertyValue -Properties (Get-GsProperty $control 'props') -Name 'tags'
        })
        Add-GsppControls -Controls (Get-GsProperty $control 'controls') -Practice $Practice -Group $Group -Output $Output
    }
}

function Add-GsppGroups {
    param($Groups, [string]$Practice, [System.Collections.Generic.List[object]]$Output)
    foreach ($group in (ConvertTo-GsArray $Groups)) {
        Add-GsppControls -Controls (Get-GsProperty $group 'controls') -Practice $Practice -Group $group -Output $Output
        Add-GsppGroups -Groups (Get-GsProperty $group 'groups') -Practice $Practice -Output $Output
    }
}

function Import-GsppCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$ExpectedSha256
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "File not found: $Path"
    }
    $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if (-not [string]::IsNullOrWhiteSpace($ExpectedSha256) -and $hash -ne $ExpectedSha256.ToLowerInvariant()) {
        throw "SHA-256 mismatch for $Path. Expected $ExpectedSha256, got $hash."
    }
    $document = Read-GsppJsonFile -Path $Path
    $catalog = Get-GsProperty $document 'catalog'
    $metadata = Get-GsProperty $catalog 'metadata'
    $groups = @(ConvertTo-GsArray (Get-GsProperty $catalog 'groups'))
    if ($null -eq $catalog -or [string]::IsNullOrWhiteSpace([string](Get-GsProperty $metadata 'oscal-version')) -or $groups.Count -eq 0) {
        throw "File is not an OSCAL catalog with metadata.oscal-version and groups: $Path"
    }
    $controls = New-Object 'System.Collections.Generic.List[object]'
    $practices = @()
    foreach ($group in $groups) {
        $before = $controls.Count
        Add-GsppControls -Controls (Get-GsProperty $group 'controls') -Practice ([string](Get-GsProperty $group 'id')) -Group $group -Output $controls
        Add-GsppGroups -Groups (Get-GsProperty $group 'groups') -Practice ([string](Get-GsProperty $group 'id')) -Output $controls
        $practices += [pscustomobject][ordered]@{
            Id           = [string](Get-GsProperty $group 'id')
            Title        = [string](Get-GsProperty $group 'title')
            ControlCount = $controls.Count - $before
        }
    }
    return [pscustomobject][ordered]@{
        Title        = [string](Get-GsProperty $metadata 'title')
        Version      = [string](Get-GsProperty $metadata 'version')
        LastModified = [string](Get-GsProperty $metadata 'last-modified')
        OscalVersion = [string](Get-GsProperty $metadata 'oscal-version')
        Sha256       = $hash
        ControlCount = $controls.Count
        Practices    = $practices
        Controls     = $controls.ToArray()
    }
}

function Test-GsppReference {
    [CmdletBinding()]
    # PublishedTitle is the title in the imported BSI catalog; CatalogTitle is the title stored in the check catalog.
    param(
        [Parameter(Mandatory = $true)]$Catalog,
        [string]$CheckCatalogPath = (Join-Path $script:GsModuleRoot 'catalog/windows11-client.json')
    )
    $checkCatalog = Read-GsJsonFile -Path $CheckCatalogPath
    $byId = @{}
    foreach ($control in @($Catalog.Controls)) { $byId[$control.Id] = $control }
    $results = @()
    foreach ($check in (ConvertTo-GsArray (Get-GsProperty $checkCatalog 'checks'))) {
        foreach ($reference in (ConvertTo-GsArray (Get-GsProperty $check 'references'))) {
            if ([string](Get-GsProperty $reference 'framework') -ne 'grundschutz-plus-plus') { continue }
            $id = [string](Get-GsProperty $reference 'requirement_id')
            $control = $null
            if ($byId.ContainsKey($id)) { $control = $byId[$id] }
            $results += [pscustomobject][ordered]@{
                Id             = $id
                CheckId        = [string](Get-GsProperty $check 'id')
                Found          = $null -ne $control
                PublishedTitle = $(if ($null -ne $control) { [string]$control.Title } else { '' })
                CatalogTitle   = [string](Get-GsProperty $reference 'title')
                TitleMatches   = $null -ne $control -and [string](Get-GsProperty $reference 'title') -eq [string]$control.Title
            }
        }
    }
    return $results
}

function Export-GsppControlIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Catalog,
        [Parameter(Mandatory = $true)][string]$Path
    )
    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($extension -eq '.csv') {
        $Catalog.Controls | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8
        return
    }
    if ($extension -eq '.json') {
        Write-GsUtf8 -Path $Path -Text ($Catalog.Controls | ConvertTo-Json -Depth 5)
        return
    }
    throw 'Path must end in .csv or .json.'
}

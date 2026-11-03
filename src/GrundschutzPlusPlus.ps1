Set-StrictMode -Version 1.0

# Grundschutz++ is published by BSI as an OSCAL catalog under CC BY-SA 4.0:
# https://github.com/BSI-Bund/Stand-der-Technik-Bibliothek/tree/main/control_layer/Grundschutz%2B%2B
# This repository does not ship that file. Download it yourself and pass its path.

function Get-GsOscalProp {
    param($Item, [string]$Name)
    foreach ($prop in (ConvertTo-GsArray (Get-GsProperty $Item 'props'))) {
        if ([string](Get-GsProperty $prop 'name') -eq $Name) {
            return [string](Get-GsProperty $prop 'value')
        }
    }
    return $null
}

function Add-GsOscalControl {
    param($Controls, [string]$Practice, [string]$Group, [string]$Parent, [System.Collections.Generic.List[object]]$Into)
    foreach ($control in (ConvertTo-GsArray $Controls)) {
        $id = [string](Get-GsProperty $control 'id')
        if ([string]::IsNullOrWhiteSpace($id)) {
            continue
        }
        $modal = $null
        foreach ($part in (ConvertTo-GsArray (Get-GsProperty $control 'parts'))) {
            if ([string](Get-GsProperty $part 'name') -eq 'statement') {
                $modal = Get-GsOscalProp -Item $part -Name 'modal_verb'
            }
        }
        $Into.Add([pscustomobject]@{
            id           = $id
            title        = [string](Get-GsProperty $control 'title')
            practice     = $Practice
            group        = $Group
            parent       = $Parent
            class        = [string](Get-GsProperty $control 'class')
            sec_level    = Get-GsOscalProp -Item $control -Name 'sec_level'
            effort_level = Get-GsOscalProp -Item $control -Name 'effort_level'
            modal_verb   = $modal
        })
        Add-GsOscalControl -Controls (Get-GsProperty $control 'controls') -Practice $Practice -Group $Group -Parent $id -Into $Into
    }
}

function Add-GsOscalGroup {
    param($Groups, [string]$Practice, [System.Collections.Generic.List[object]]$Into)
    foreach ($group in (ConvertTo-GsArray $Groups)) {
        $groupId = [string](Get-GsProperty $group 'id')
        $practiceId = $Practice
        if ([string]::IsNullOrWhiteSpace($practiceId)) {
            $practiceId = $groupId
        }
        Add-GsOscalControl -Controls (Get-GsProperty $group 'controls') -Practice $practiceId -Group $groupId -Parent $null -Into $Into
        Add-GsOscalGroup -Groups (Get-GsProperty $group 'groups') -Practice $practiceId -Into $Into
    }
}

function ConvertTo-GsOscalText {
    param($Value)
    if ($null -eq $Value) {
        return ''
    }
    if ($Value -is [datetime]) {
        return $Value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.FFFFFFFZ', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    if ($Value -is [datetimeoffset]) {
        return $Value.UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ss.FFFFFFFZ', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    $text = [string]$Value
    # PowerShell 7 parses ISO timestamps into DateTime and Windows PowerShell 5.1 does not.
    # Normalize both to UTC so versions compare the same on every host.
    if ($text -match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}') {
        $parsed = [datetimeoffset]::MinValue
        if ([datetimeoffset]::TryParse($text, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) {
            return $parsed.UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ss.FFFFFFFZ', [System.Globalization.CultureInfo]::InvariantCulture)
        }
    }
    return $text
}

function Import-GsGrundschutzPlusPlus {
    <#
    .SYNOPSIS
        Reads a Grundschutz++ OSCAL catalog that you downloaded from BSI.
    .DESCRIPTION
        Returns the catalog metadata and one row per control: id, title, practice, group,
        parent control, class, sec_level, effort_level and the modal verb of the statement.
        Prose is not copied. The file is read only; nothing is written or sent.
    .PARAMETER Path
        Path to Grundschutz++-resolved_catalog.json (or another OSCAL catalog in the same shape).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $document = Read-GsJsonFile -Path $Path
    $catalog = Get-GsProperty $document 'catalog'
    if ($null -eq $catalog) {
        throw "Not an OSCAL catalog (no top-level 'catalog' object): $Path"
    }
    $metadata = Get-GsProperty $catalog 'metadata'
    $oscalVersion = [string](Get-GsProperty $metadata 'oscal-version')
    if ([string]::IsNullOrWhiteSpace($oscalVersion)) {
        throw "Not an OSCAL catalog (metadata.oscal-version is missing): $Path"
    }
    if (-not $oscalVersion.StartsWith('1.')) {
        throw "Unsupported OSCAL version '$oscalVersion' in $Path. Expected 1.x."
    }

    $rows = New-Object 'System.Collections.Generic.List[object]'
    Add-GsOscalGroup -Groups (Get-GsProperty $catalog 'groups') -Practice $null -Into $rows
    Add-GsOscalControl -Controls (Get-GsProperty $catalog 'controls') -Practice $null -Group $null -Parent $null -Into $rows
    if ($rows.Count -eq 0) {
        throw "The OSCAL catalog in $Path has no controls."
    }

    $seen = @{}
    $duplicates = New-Object 'System.Collections.Generic.List[string]'
    foreach ($row in $rows) {
        if ($seen.ContainsKey($row.id)) {
            $duplicates.Add($row.id)
        }
        else {
            $seen[$row.id] = $row
        }
    }

    return [pscustomobject]@{
        title         = [string](Get-GsProperty $metadata 'title')
        version       = ConvertTo-GsOscalText (Get-GsProperty $metadata 'version')
        last_modified = ConvertTo-GsOscalText (Get-GsProperty $metadata 'last-modified')
        oscal_version = $oscalVersion
        source_path   = $Path
        controls      = $rows.ToArray()
        index         = $seen
        duplicates    = $duplicates.ToArray()
    }
}

function Test-GsGrundschutzPlusPlusReference {
    <#
    .SYNOPSIS
        Checks every Grundschutz++ reference in a check catalog against an imported Grundschutz++ catalog.
    .DESCRIPTION
        Status per reference: 'ok' (id exists, title matches), 'title_changed' (id exists,
        title differs) or 'missing' (id is not in the imported catalog).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Catalog,
        [Parameter(Mandatory = $true)]$Library
    )

    $rows = New-Object 'System.Collections.Generic.List[object]'
    foreach ($check in (ConvertTo-GsArray (Get-GsProperty $Catalog 'checks'))) {
        foreach ($reference in (ConvertTo-GsArray (Get-GsProperty $check 'references'))) {
            if ([string](Get-GsProperty $reference 'framework') -ne 'grundschutz-plus-plus') {
                continue
            }
            $id = [string](Get-GsProperty $reference 'requirement_id')
            $title = [string](Get-GsProperty $reference 'title')
            $control = $null
            if ($Library.index.ContainsKey($id)) {
                $control = $Library.index[$id]
            }
            $status = 'missing'
            $currentTitle = $null
            if ($null -ne $control) {
                $currentTitle = $control.title
                $status = 'ok'
                if (-not [string]::Equals($title.Trim(), ([string]$control.title).Trim(), [System.StringComparison]::Ordinal)) {
                    $status = 'title_changed'
                }
            }
            $rows.Add([pscustomobject]@{
                check_id       = [string](Get-GsProperty $check 'id')
                requirement_id = $id
                catalog_title  = $title
                current_title  = $currentTitle
                mapping        = [string](Get-GsProperty $reference 'mapping')
                status         = $status
            })
        }
    }

    $sourceVersion = $null
    foreach ($source in (ConvertTo-GsArray (Get-GsProperty (Get-GsProperty $Catalog 'catalog') 'sources'))) {
        if ([string](Get-GsProperty $source 'id') -like 'grundschutz-plus-plus*') {
            $sourceVersion = ConvertTo-GsOscalText (Get-GsProperty $source 'version')
        }
    }

    $all = $rows.ToArray()
    return [pscustomobject]@{
        library_version = $Library.version
        catalog_source_version = $sourceVersion
        version_differs = ($null -ne $sourceVersion -and $sourceVersion -ne $Library.version)
        total           = $all.Count
        ok              = @($all | Where-Object { $_.status -eq 'ok' }).Count
        title_changed   = @($all | Where-Object { $_.status -eq 'title_changed' }).Count
        missing         = @($all | Where-Object { $_.status -eq 'missing' }).Count
        references      = $all
    }
}

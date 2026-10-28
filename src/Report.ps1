Set-StrictMode -Version 1.0

function ConvertTo-GsHtmlText {
    param($Value)
    if ($null -eq $Value) { return '' }
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function ConvertTo-GsMarkdownCell {
    param($Value)
    if ($null -eq $Value) { return '' }
    return (([string]$Value) -replace '\|', '\|' -replace "`r?`n", ' ')
}

function Get-GsPrimaryReference {
    param($Check)
    $refs = @(ConvertTo-GsArray (Get-GsProperty $Check 'references'))
    if ($refs.Count -eq 0) { return $null }
    return $refs[0]
}

function New-GsCountBag {
    return @{
        pass           = 0
        fail           = 0
        error          = 0
        not_applicable = 0
        accepted       = 0
        total          = 0
    }
}

function Add-GsCount {
    param($Bag, [string]$Status)
    $Bag.total += 1
    switch ($Status) {
        'pass' { $Bag.pass += 1 }
        'fail' { $Bag.fail += 1 }
        'error' { $Bag.error += 1 }
        'not_applicable' { $Bag.not_applicable += 1 }
        'accepted' { $Bag.accepted += 1 }
    }
}

function ConvertTo-GsCountObject {
    param($Bag, [string]$Id, [string]$Title)
    return [pscustomobject][ordered]@{
        id             = $Id
        title          = $Title
        pass           = $Bag.pass
        fail           = $Bag.fail
        error          = $Bag.error
        not_applicable = $Bag.not_applicable
        accepted       = $Bag.accepted
        total          = $Bag.total
    }
}

function New-GsReportDocument {
    param($Catalog, $Evidence, $Evaluations, [string]$Timestamp, [string]$Mode)
    $hostInfo = Get-GsProperty $Evidence 'host'
    $meta = Get-GsProperty $Catalog 'catalog'
    $moduleTitle = @{}
    foreach ($module in (ConvertTo-GsArray (Get-GsProperty $Catalog 'modules'))) {
        $moduleTitle[[string](Get-GsProperty $module 'id')] = [string](Get-GsProperty $module 'title')
    }
    $results = @()
    $moduleBags = @{}
    $moduleOrder = New-Object System.Collections.Generic.List[string]
    $practiceBags = @{}
    $practiceOrder = New-Object System.Collections.Generic.List[string]
    $summary = New-GsCountBag
    foreach ($pair in $Evaluations) {
        $check = $pair.Check
        $evaluation = $pair.Evaluation
        $module = Get-GsProperty $check 'module'
        $moduleId = [string](Get-GsProperty $module 'id')
        $primary = Get-GsPrimaryReference $check
        $refsOut = @()
        foreach ($ref in (ConvertTo-GsArray (Get-GsProperty $check 'references'))) {
            $framework = [string](Get-GsProperty $ref 'framework')
            $requirementId = Get-GsProperty $ref 'requirement_id'
            $refsOut += [pscustomobject][ordered]@{
                framework       = $framework
                requirement_id  = $requirementId
                title           = [string](Get-GsProperty $ref 'title')
                mapping         = [string](Get-GsProperty $ref 'mapping')
                source_id       = [string](Get-GsProperty $ref 'source_id')
                note            = [string](Get-GsProperty $ref 'note')
            }
            if ($framework -eq 'grundschutz-plus-plus' -and -not [string]::IsNullOrWhiteSpace([string]$requirementId)) {
                $practice = ([string]$requirementId).Split('.')[0]
                if (-not $practiceBags.ContainsKey($practice)) {
                    $practiceBags[$practice] = New-GsCountBag
                    $practiceOrder.Add($practice)
                }
                Add-GsCount -Bag $practiceBags[$practice] -Status $evaluation.Status
            }
        }
        if (-not $moduleBags.ContainsKey($moduleId)) {
            $moduleBags[$moduleId] = New-GsCountBag
            $moduleOrder.Add($moduleId)
        }
        Add-GsCount -Bag $moduleBags[$moduleId] -Status $evaluation.Status
        Add-GsCount -Bag $summary -Status $evaluation.Status
        $remediation = Get-GsProperty $check 'remediation'
        $results += [pscustomobject][ordered]@{
            id                    = [string](Get-GsProperty $check 'id')
            title                 = [string](Get-GsProperty $check 'title')
            status                = [string]$evaluation.Status
            severity              = [string](Get-GsProperty $check 'severity')
            mapping               = [string](Get-GsProperty $check 'mapping')
            windows11_carryover   = [string](Get-GsProperty $check 'windows11_carryover')
            module_id             = $moduleId
            module_title          = [string]$moduleTitle[$moduleId]
            requirement_id        = [string](Get-GsProperty $primary 'requirement_id')
            requirement_title     = [string](Get-GsProperty $primary 'title')
            references            = $refsOut
            expected              = [string]$evaluation.Expected
            actual                = [string]$evaluation.Actual
            message               = [string]$evaluation.Message
            rationale             = [string](Get-GsProperty $check 'rationale')
            conflict_note         = [string](Get-GsProperty $check 'conflict_note')
            applicability_note    = [string](Get-GsProperty $check 'applicability_note')
            exception             = (Get-GsProperty $evaluation 'Exception')
            remediation           = [pscustomobject][ordered]@{
                summary  = [string](Get-GsProperty $remediation 'summary')
                gpo      = [string](Get-GsProperty $remediation 'gpo')
                intune   = [string](Get-GsProperty $remediation 'intune')
                registry = [string](Get-GsProperty $remediation 'registry')
            }
        }
    }
    $modules = @()
    foreach ($id in $moduleOrder) {
        $title = ''
        if ($moduleTitle.ContainsKey($id)) { $title = [string]$moduleTitle[$id] }
        $modules += ConvertTo-GsCountObject -Bag $moduleBags[$id] -Id $id -Title $title
    }
    $practiceTitles = @{
        KONF = 'Konfiguration'
        BER  = 'Berechtigung'
        DET  = 'Detektion'
        ARCH = 'Architektur'
    }
    $practices = @()
    foreach ($id in $practiceOrder) {
        $title = $id
        if ($practiceTitles.ContainsKey($id)) { $title = [string]$practiceTitles[$id] }
        $practices += ConvertTo-GsCountObject -Bag $practiceBags[$id] -Id $id -Title $title
    }
    $notes = @()
    foreach ($note in (ConvertTo-GsArray (Get-GsProperty $Evidence 'notes'))) {
        $notes += [string]$note
    }
    if ($Mode -eq 'demo') {
        $notes = @('Demo mode used bundled fictional evidence. This report is not evidence about a real system.') + $notes
    }
    $audit = @()
    foreach ($row in (ConvertTo-GsArray (Get-GsProperty $Evidence 'auditpol'))) {
        $audit += [pscustomobject][ordered]@{
            subcategory = [string](Get-GsProperty $row 'subcategory')
            setting     = [string](Get-GsProperty $row 'setting')
        }
    }
    return [pscustomobject][ordered]@{
        tool     = [pscustomobject][ordered]@{
            name    = $script:GsToolName
            version = $script:GsToolVersion
        }
        catalog  = [pscustomobject][ordered]@{
            id             = [string](Get-GsProperty $meta 'id')
            title          = [string](Get-GsProperty $meta 'title')
            version        = [string](Get-GsProperty $meta 'version')
            schema_version = [string](Get-GsProperty $Catalog 'schema_version')
        }
        evidence = [pscustomobject][ordered]@{
            generated_at             = $Timestamp
            mode                     = $Mode
            host_fingerprint_sha256  = (Get-GsHostFingerprint -HostInfo $hostInfo)
            host_fingerprint_note    = 'SHA-256 of the v1 canonical host string (name, domain, OS caption, version, build). The host name is not stored in this report.'
            platform                 = [pscustomobject][ordered]@{
                os_caption = [string](Get-GsProperty $hostInfo 'os_caption')
                os_version = [string](Get-GsProperty $hostInfo 'os_version')
                os_build   = [string](Get-GsProperty $hostInfo 'os_build')
            }
            audit_policy             = $audit
            notes                    = $notes
        }
        summary  = [pscustomobject][ordered]@{
            pass           = $summary.pass
            fail           = $summary.fail
            error          = $summary.error
            not_applicable = $summary.not_applicable
            accepted       = $summary.accepted
            total          = $summary.total
            modules        = $modules
            grundschutz_plus_plus = $practices
        }
        results  = $results
    }
}

function Get-GsHtmlStyle {
    return @'
:root { color-scheme: light; --ink:#142033; --muted:#5c6b7a; --line:#d5dde6; --paper:#f4f7fa; --card:#fff; --navy:#10243f; --fail:#9f1239; --pass:#166534; --err:#9a3412; --na:#3f6212; --chip:#e8eef5; }
* { box-sizing: border-box; }
body { margin:0; font:16px/1.45 "Segoe UI", "Liberation Sans", sans-serif; color:var(--ink); background:var(--paper); }
header { background:var(--navy); color:#fff; padding:28px 32px 22px; }
header h1 { margin:0 0 4px; font-size:28px; letter-spacing:-0.02em; }
header p { margin:0; color:#c9d6e5; }
main { padding:24px 32px 64px; max-width:1180px; margin:0 auto; }
.banner { border-left:4px solid #b45309; background:#fff7ed; padding:12px 14px; margin:0 0 16px; }
.banner.demo { border-color:#1d4ed8; background:#eff6ff; }
.grid { display:grid; grid-template-columns:repeat(4,1fr); gap:12px; margin:16px 0; }
.card { background:var(--card); border:1px solid var(--line); border-radius:8px; padding:14px 16px; }
.card .n { font-size:28px; font-weight:650; }
.card span { color:var(--muted); font-size:13px; }
.fail .n { color:var(--fail); } .pass .n { color:var(--pass); } .err .n { color:var(--err); }
table { width:100%; border-collapse:collapse; background:#fff; }
th, td { text-align:left; padding:8px 10px; border-bottom:1px solid var(--line); vertical-align:top; font-size:14px; }
th { font-size:12px; letter-spacing:.04em; text-transform:uppercase; color:var(--muted); }
.status { font-weight:650; text-transform:uppercase; font-size:12px; letter-spacing:.04em; }
.status.fail { color:var(--fail); } .status.pass { color:var(--pass); } .status.error { color:var(--err); } .status.not_applicable { color:var(--na); } .status.accepted { color:#7c3aed; }
.delta li { margin:2px 0; }
.sev { font-size:12px; }
.badge { display:inline-block; background:var(--chip); border-radius:99px; padding:1px 8px; font-size:12px; margin-right:4px; }
.badge.unverified { background:#ffedd5; color:#9a3412; }
.badge.verified { background:#dcfce7; color:#166534; }
details { margin-top:6px; }
pre { white-space:pre-wrap; font:13px/1.4 ui-monospace, Consolas, monospace; background:#f8fafc; padding:8px; border-radius:6px; }
.meta { display:grid; grid-template-columns:180px 1fr; gap:4px 12px; }
.meta div { padding:3px 0; border-bottom:1px solid var(--line); }
button { background:#fff; border:1px solid var(--line); border-radius:6px; padding:6px 10px; margin-right:6px; cursor:pointer; }
button.active { background:var(--navy); color:#fff; }
h2 { margin:28px 0 8px; font-size:20px; }
footer { color:var(--muted); font-size:13px; margin-top:28px; }
@media (max-width:800px) { .grid, .meta { grid-template-columns:1fr 1fr; } main, header { padding-left:16px; padding-right:16px; } }
@media print { button { display:none; } body { background:#fff; } }
'@
}

function Get-GsHtmlScript {
    return @'
function gscFilter(kind, button) {
  var rows = document.querySelectorAll("[data-status]");
  for (var i = 0; i < rows.length; i++) {
    var show = kind === "all" || rows[i].getAttribute("data-status") === kind;
    rows[i].style.display = show ? "" : "none";
  }
  var buttons = document.querySelectorAll("button[data-filter]");
  for (var j = 0; j < buttons.length; j++) {
    buttons[j].className = buttons[j] === button ? "active" : "";
  }
}
'@
}

function ConvertTo-GsHtmlReport {
    param($Document)
    $e = $Document.evidence
    $s = $Document.summary
    $b = New-Object System.Text.StringBuilder
    [void]$b.AppendLine('<!DOCTYPE html>')
    [void]$b.AppendLine('<html lang="en"><head><meta charset="utf-8">')
    [void]$b.AppendLine('<meta name="viewport" content="width=device-width, initial-scale=1">')
    [void]$b.AppendLine('<title>GrundschutzCheck audit report</title>')
    [void]$b.AppendLine('<style>')
    [void]$b.AppendLine((Get-GsHtmlStyle))
    [void]$b.AppendLine('</style></head><body>')
    [void]$b.AppendLine('<header><h1>GrundschutzCheck</h1>')
    [void]$b.AppendLine('<p>Windows 11 client hardening evidence against BSI IT-Grundschutz and Grundschutz++.</p></header>')
    [void]$b.AppendLine('<main>')
    if ([string]$e.mode -eq 'demo') {
        [void]$b.AppendLine('<div class="banner demo"><strong>Demo.</strong> These results were rendered from bundled fictional evidence. They are not an audit of a real computer.</div>')
    }
    [void]$b.AppendLine('<div class="banner"><strong>Read-only.</strong> Remediation snippets are text. This run did not change the system. A pass is an indicator, not a certificate that the whole BSI requirement is met.</div>')
    [void]$b.AppendLine('<div class="grid">')
    [void]$b.AppendLine('<div class="card pass"><div class="n">' + $s.pass + '</div><span>Pass</span></div>')
    [void]$b.AppendLine('<div class="card fail"><div class="n">' + $s.fail + '</div><span>Fail</span></div>')
    [void]$b.AppendLine('<div class="card err"><div class="n">' + $s.error + '</div><span>Error</span></div>')
    [void]$b.AppendLine('<div class="card"><div class="n">' + $s.total + '</div><span>Checks</span></div>')
    [void]$b.AppendLine('</div>')
    if ([int]$s.accepted -gt 0) {
        [void]$b.AppendLine('<div class="banner"><strong>' + $s.accepted + ' accepted risk(s).</strong> These checks fail, but a documented exception with an owner and an expiry date covers them. They are listed with status ACCEPTED.</div>')
    }
    $cmp = Get-GsProperty $Document 'comparison'
    if ($null -ne $cmp) {
        [void]$b.AppendLine('<section class="card delta"><h2>Changes since baseline</h2>')
        [void]$b.AppendLine('<p>Baseline generated ' + (ConvertTo-GsHtmlText $cmp.baseline_generated_at) + ', catalog ' + (ConvertTo-GsHtmlText $cmp.baseline_catalog_version) + '.' + $(if ($cmp.same_host -eq $false) { ' <strong>The baseline is from a different host.</strong>' } else { '' }) + '</p>')
        [void]$b.AppendLine('<p>Newly failing: ' + @($cmp.newly_failing).Count + ' &middot; Fixed: ' + @($cmp.fixed).Count + ' &middot; Still failing: ' + @($cmp.still_failing).Count + '</p>')
        foreach ($group in @(@('Newly failing', $cmp.newly_failing), @('Fixed', $cmp.fixed))) {
            if (@($group[1]).Count -gt 0) {
                [void]$b.AppendLine('<p><strong>' + $group[0] + '</strong></p><ul>')
                foreach ($item in @($group[1])) {
                    [void]$b.AppendLine('<li>' + (ConvertTo-GsHtmlText $item.id) + ' ' + (ConvertTo-GsHtmlText $item.title) + ' (' + (ConvertTo-GsHtmlText $item.before) + ' &rarr; ' + (ConvertTo-GsHtmlText $item.after) + ')</li>')
                }
                [void]$b.AppendLine('</ul>')
            }
        }
        [void]$b.AppendLine('</section>')
    }
    [void]$b.AppendLine('<section class="card"><h2>Evidence</h2><div class="meta">')
    [void]$b.AppendLine('<div>Generated (UTC)</div><div>' + (ConvertTo-GsHtmlText $e.generated_at) + '</div>')
    [void]$b.AppendLine('<div>Mode</div><div>' + (ConvertTo-GsHtmlText $e.mode) + '</div>')
    [void]$b.AppendLine('<div>Tool</div><div>' + (ConvertTo-GsHtmlText $Document.tool.name) + ' ' + (ConvertTo-GsHtmlText $Document.tool.version) + '</div>')
    [void]$b.AppendLine('<div>Catalog</div><div>' + (ConvertTo-GsHtmlText $Document.catalog.id) + ' ' + (ConvertTo-GsHtmlText $Document.catalog.version) + '</div>')
    [void]$b.AppendLine('<div>Host fingerprint</div><div><code>' + (ConvertTo-GsHtmlText $e.host_fingerprint_sha256) + '</code></div>')
    [void]$b.AppendLine('<div>Fingerprint note</div><div>' + (ConvertTo-GsHtmlText $e.host_fingerprint_note) + '</div>')
    [void]$b.AppendLine('<div>Platform</div><div>' + (ConvertTo-GsHtmlText $e.platform.os_caption) + ' / ' + (ConvertTo-GsHtmlText $e.platform.os_version) + ' / build ' + (ConvertTo-GsHtmlText $e.platform.os_build) + '</div>')
    [void]$b.AppendLine('</div></section>')
    [void]$b.AppendLine('<h2>Summary by BSI module</h2>')
    [void]$b.AppendLine('<table><thead><tr><th>Module</th><th>Title</th><th>Pass</th><th>Fail</th><th>Error</th><th>N/A</th></tr></thead><tbody>')
    foreach ($module in @($s.modules)) {
        [void]$b.AppendLine('<tr><td>' + (ConvertTo-GsHtmlText $module.id) + '</td><td>' + (ConvertTo-GsHtmlText $module.title) + '</td><td>' + $module.pass + '</td><td>' + $module.fail + '</td><td>' + $module.error + '</td><td>' + $module.not_applicable + '</td></tr>')
    }
    [void]$b.AppendLine('</tbody></table>')
    [void]$b.AppendLine('<h2>Summary by Grundschutz++ practice</h2>')
    [void]$b.AppendLine('<p>Counts include every check that cites a control in that practice, including citations marked unverified.</p>')
    [void]$b.AppendLine('<table><thead><tr><th>Practice</th><th>Title</th><th>Pass</th><th>Fail</th><th>Error</th></tr></thead><tbody>')
    foreach ($practice in @($s.grundschutz_plus_plus)) {
        [void]$b.AppendLine('<tr><td>' + (ConvertTo-GsHtmlText $practice.id) + '</td><td>' + (ConvertTo-GsHtmlText $practice.title) + '</td><td>' + $practice.pass + '</td><td>' + $practice.fail + '</td><td>' + $practice.error + '</td></tr>')
    }
    [void]$b.AppendLine('</tbody></table>')
    [void]$b.AppendLine('<h2>Checks</h2>')
    [void]$b.AppendLine('<p><button type="button" data-filter="all" class="active" onclick="gscFilter(''all'', this)">All</button>')
    [void]$b.AppendLine('<button type="button" data-filter="fail" onclick="gscFilter(''fail'', this)">Fail</button>')
    [void]$b.AppendLine('<button type="button" data-filter="error" onclick="gscFilter(''error'', this)">Error</button>')
    [void]$b.AppendLine('<button type="button" data-filter="accepted" onclick="gscFilter(''accepted'', this)">Accepted</button>')
    [void]$b.AppendLine('<button type="button" data-filter="pass" onclick="gscFilter(''pass'', this)">Pass</button></p>')
    [void]$b.AppendLine('<table><thead><tr><th>Status</th><th>Check</th><th>Requirement</th><th>Observed</th></tr></thead><tbody>')
    foreach ($row in @($Document.results)) {
        [void]$b.AppendLine('<tr data-status="' + (ConvertTo-GsHtmlText $row.status) + '"><td><div class="status ' + (ConvertTo-GsHtmlText $row.status) + '">' + (ConvertTo-GsHtmlText $row.status) + '</div><div class="sev">' + (ConvertTo-GsHtmlText $row.severity) + '</div></td><td>')
        [void]$b.AppendLine('<strong>' + (ConvertTo-GsHtmlText $row.id) + '</strong> ' + (ConvertTo-GsHtmlText $row.title))
        [void]$b.AppendLine('<div><span class="badge ' + (ConvertTo-GsHtmlText $row.mapping) + '">mapping ' + (ConvertTo-GsHtmlText $row.mapping) + '</span>')
        [void]$b.AppendLine('<span class="badge ' + (ConvertTo-GsHtmlText $row.windows11_carryover) + '">Windows 11 carry-over ' + (ConvertTo-GsHtmlText $row.windows11_carryover) + '</span></div>')
        if (-not [string]::IsNullOrWhiteSpace([string]$row.conflict_note)) {
            [void]$b.AppendLine('<div class="banner">' + (ConvertTo-GsHtmlText $row.conflict_note) + '</div>')
        }
        $ex = Get-GsProperty $row 'exception'
        if ($null -ne $ex) {
            [void]$b.AppendLine('<div class="banner">Exception (' + (ConvertTo-GsHtmlText $ex.state) + '): ' + (ConvertTo-GsHtmlText $ex.reason) + ' Owner: ' + (ConvertTo-GsHtmlText $ex.owner) + '. Expires: ' + (ConvertTo-GsHtmlText $ex.expires) + '.</div>')
        }
        [void]$b.AppendLine('<details><summary>Rationale and remediation (not applied)</summary>')
        [void]$b.AppendLine('<p>' + (ConvertTo-GsHtmlText $row.rationale) + '</p>')
        if (-not [string]::IsNullOrWhiteSpace([string]$row.applicability_note)) {
            [void]$b.AppendLine('<p>' + (ConvertTo-GsHtmlText $row.applicability_note) + '</p>')
        }
        [void]$b.AppendLine('<p><strong>GPO.</strong></p><pre>' + (ConvertTo-GsHtmlText $row.remediation.gpo) + '</pre>')
        [void]$b.AppendLine('<p><strong>Intune.</strong></p><pre>' + (ConvertTo-GsHtmlText $row.remediation.intune) + '</pre>')
        [void]$b.AppendLine('<p><strong>Registry.</strong></p><pre>' + (ConvertTo-GsHtmlText $row.remediation.registry) + '</pre>')
        [void]$b.AppendLine('<p>' + (ConvertTo-GsHtmlText $row.remediation.summary) + '</p></details></td><td>')
        [void]$b.AppendLine('<div>' + (ConvertTo-GsHtmlText $row.requirement_id) + '</div><div>' + (ConvertTo-GsHtmlText $row.requirement_title) + '</div>')
        foreach ($ref in @($row.references)) {
            $rid = [string]$ref.requirement_id
            if ([string]::IsNullOrWhiteSpace($rid)) { $rid = '(no id)' }
            [void]$b.AppendLine('<div><span class="badge ' + (ConvertTo-GsHtmlText $ref.mapping) + '">' + (ConvertTo-GsHtmlText $ref.mapping) + '</span> ' + (ConvertTo-GsHtmlText $ref.framework) + ' ' + (ConvertTo-GsHtmlText $rid) + '</div>')
        }
        [void]$b.AppendLine('</td><td><div>Expected: ' + (ConvertTo-GsHtmlText $row.expected) + '</div><div>Actual: ' + (ConvertTo-GsHtmlText $row.actual) + '</div><div>' + (ConvertTo-GsHtmlText $row.message) + '</div></td></tr>')
    }
    [void]$b.AppendLine('</tbody></table>')
    [void]$b.AppendLine('<h2>Collected audit policy</h2>')
    [void]$b.AppendLine('<p>The full advanced audit policy captured for this run. Only subcategories that have a catalog check are scored above.</p>')
    [void]$b.AppendLine('<table><thead><tr><th>Subcategory</th><th>Setting</th></tr></thead><tbody>')
    foreach ($row in @($e.audit_policy)) {
        [void]$b.AppendLine('<tr><td>' + (ConvertTo-GsHtmlText $row.subcategory) + '</td><td>' + (ConvertTo-GsHtmlText $row.setting) + '</td></tr>')
    }
    [void]$b.AppendLine('</tbody></table>')
    [void]$b.AppendLine('<footer><p>No telemetry. Data stayed on the machine that produced this file.</p>')
    foreach ($note in @($e.notes)) {
        [void]$b.AppendLine('<p>' + (ConvertTo-GsHtmlText $note) + '</p>')
    }
    [void]$b.AppendLine('</footer></main><script>')
    [void]$b.AppendLine((Get-GsHtmlScript))
    [void]$b.AppendLine('</script></body></html>')
    return $b.ToString()
}

function ConvertTo-GsMarkdownReport {
    param($Document)
    $e = $Document.evidence
    $s = $Document.summary
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# GrundschutzCheck audit report')
    $lines.Add('')
    if ([string]$e.mode -eq 'demo') {
        $lines.Add('> Demo. These results were rendered from bundled fictional evidence. They are not an audit of a real computer.')
        $lines.Add('')
    }
    $lines.Add('Read-only run. Remediation snippets were not applied.')
    $lines.Add('')
    $lines.Add('## Evidence')
    $lines.Add('')
    $lines.Add('- Generated (UTC): ' + $e.generated_at)
    $lines.Add('- Mode: ' + $e.mode)
    $lines.Add('- Tool: ' + $Document.tool.name + ' ' + $Document.tool.version)
    $lines.Add('- Catalog: ' + $Document.catalog.id + ' ' + $Document.catalog.version)
    $lines.Add('- Host fingerprint (SHA-256): `' + $e.host_fingerprint_sha256 + '`')
    $lines.Add('- ' + $e.host_fingerprint_note)
    $lines.Add('- Platform: ' + $e.platform.os_caption + ' / ' + $e.platform.os_version + ' / build ' + $e.platform.os_build)
    $lines.Add('')
    $lines.Add('## Summary')
    $lines.Add('')
    $lines.Add('- Pass: ' + $s.pass)
    $lines.Add('- Fail: ' + $s.fail)
    $lines.Add('- Error: ' + $s.error)
    $lines.Add('- Not applicable: ' + $s.not_applicable)
    if ([int]$s.accepted -gt 0) {
        $lines.Add('- Accepted risk (documented exception): ' + $s.accepted)
    }
    $lines.Add('- Total: ' + $s.total)
    $lines.Add('')
    $cmp = Get-GsProperty $Document 'comparison'
    if ($null -ne $cmp) {
        $lines.Add('## Changes since baseline')
        $lines.Add('')
        $lines.Add('Baseline generated ' + $cmp.baseline_generated_at + ', catalog ' + $cmp.baseline_catalog_version + '.')
        if ($cmp.same_host -eq $false) {
            $lines.Add('')
            $lines.Add('> The baseline is from a different host.')
        }
        $lines.Add('')
        $lines.Add('| Change | Count |')
        $lines.Add('| --- | --- |')
        $lines.Add('| Newly failing | ' + @($cmp.newly_failing).Count + ' |')
        $lines.Add('| Fixed | ' + @($cmp.fixed).Count + ' |')
        $lines.Add('| Still failing | ' + @($cmp.still_failing).Count + ' |')
        $lines.Add('| New checks | ' + @($cmp.new_checks).Count + ' |')
        $lines.Add('| Removed checks | ' + @($cmp.removed_checks).Count + ' |')
        $lines.Add('')
        foreach ($item in @($cmp.newly_failing)) {
            $lines.Add('- Newly failing: ' + $item.id + ' ' + (ConvertTo-GsMarkdownCell $item.title) + ' (' + $item.before + ' -> ' + $item.after + ')')
        }
        foreach ($item in @($cmp.fixed)) {
            $lines.Add('- Fixed: ' + $item.id + ' ' + (ConvertTo-GsMarkdownCell $item.title) + ' (' + $item.before + ' -> ' + $item.after + ')')
        }
        $lines.Add('')
    }
    $lines.Add('## Summary by BSI module')
    $lines.Add('')
    $lines.Add('| Module | Title | Pass | Fail | Error | N/A |')
    $lines.Add('| --- | --- | --- | --- | --- | --- |')
    foreach ($module in @($s.modules)) {
        $lines.Add('| ' + (ConvertTo-GsMarkdownCell $module.id) + ' | ' + (ConvertTo-GsMarkdownCell $module.title) + ' | ' + $module.pass + ' | ' + $module.fail + ' | ' + $module.error + ' | ' + $module.not_applicable + ' |')
    }
    $lines.Add('')
    $lines.Add('## Summary by Grundschutz++ practice')
    $lines.Add('')
    $lines.Add('| Practice | Title | Pass | Fail | Error |')
    $lines.Add('| --- | --- | --- | --- | --- |')
    foreach ($practice in @($s.grundschutz_plus_plus)) {
        $lines.Add('| ' + (ConvertTo-GsMarkdownCell $practice.id) + ' | ' + (ConvertTo-GsMarkdownCell $practice.title) + ' | ' + $practice.pass + ' | ' + $practice.fail + ' | ' + $practice.error + ' |')
    }
    $lines.Add('')
    $lines.Add('## Checks')
    $lines.Add('')
    foreach ($row in @($Document.results)) {
        $lines.Add('### ' + $row.id + ' - ' + $row.status + ' (' + $row.severity + ')')
        $lines.Add('')
        $lines.Add($row.title)
        $lines.Add('')
        $lines.Add('- Requirement: ' + $row.requirement_id + ' ' + $row.requirement_title)
        $lines.Add('- Module: ' + $row.module_id)
        $lines.Add('- Mapping: ' + $row.mapping)
        $lines.Add('- Windows 11 carry-over: ' + $row.windows11_carryover)
        $lines.Add('- Expected: ' + $row.expected)
        $lines.Add('- Actual: ' + $row.actual)
        $lines.Add('- ' + $row.message)
        $ex = Get-GsProperty $row 'exception'
        if ($null -ne $ex) {
            $lines.Add('- Exception (' + $ex.state + '): ' + $ex.reason + ' Owner: ' + $ex.owner + '. Expires: ' + $ex.expires + '.')
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$row.conflict_note)) {
            $lines.Add('')
            $lines.Add('Conflict: ' + $row.conflict_note)
        }
        $lines.Add('')
        $lines.Add($row.rationale)
        $lines.Add('')
        $lines.Add('GPO:')
        $lines.Add('')
        $lines.Add('```')
        $lines.Add([string]$row.remediation.gpo)
        $lines.Add('```')
        $lines.Add('')
        $lines.Add('Intune:')
        $lines.Add('')
        $lines.Add('```')
        $lines.Add([string]$row.remediation.intune)
        $lines.Add('```')
        $lines.Add('')
        $lines.Add('Registry:')
        $lines.Add('')
        $lines.Add('```')
        $lines.Add([string]$row.remediation.registry)
        $lines.Add('```')
        $lines.Add('')
    }
    $lines.Add('## Collected audit policy')
    $lines.Add('')
    $lines.Add('| Subcategory | Setting |')
    $lines.Add('| --- | --- |')
    foreach ($row in @($e.audit_policy)) {
        $lines.Add('| ' + (ConvertTo-GsMarkdownCell $row.subcategory) + ' | ' + (ConvertTo-GsMarkdownCell $row.setting) + ' |')
    }
    $lines.Add('')
    $lines.Add('No telemetry. Data stayed on the machine that produced this file.')
    $lines.Add('')
    return ($lines -join "`n")
}

function ConvertTo-GsCsvReport {
    param($Document)
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('id,title,status,severity,mapping,windows11_carryover,module_id,requirement_id,expected,actual,message')
    foreach ($row in @($Document.results)) {
        $fields = @(
            $row.id, $row.title, $row.status, $row.severity, $row.mapping, $row.windows11_carryover,
            $row.module_id, $row.requirement_id, $row.expected, $row.actual, $row.message
        )
        $encoded = @()
        foreach ($field in $fields) {
            $text = [string]$field
            $text = $text -replace '"', '""'
            $encoded += ('"' + $text + '"')
        }
        $lines.Add($encoded -join ',')
    }
    return ($lines -join "`n")
}

function Write-GsUtf8 {
    param([string]$Path, [string]$Text)
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $Text, $utf8)
}

function Write-GsReportFiles {
    param($Document, [string]$Directory, [string[]]$Formats)
    if (-not (Test-Path -LiteralPath $Directory)) {
        New-Item -ItemType Directory -Path $Directory | Out-Null
    }
    $selected = @()
    foreach ($format in $Formats) {
        if ($format -eq 'All') {
            $selected += @('Html', 'Markdown', 'Json', 'Csv')
        }
        else {
            $selected += $format
        }
    }
    $written = [ordered]@{}
    if ($selected -contains 'Html') {
        $path = Join-Path $Directory 'grundschutzcheck-report.html'
        Write-GsUtf8 -Path $path -Text (ConvertTo-GsHtmlReport -Document $Document)
        $written.html = $path
    }
    if ($selected -contains 'Markdown') {
        $path = Join-Path $Directory 'grundschutzcheck-report.md'
        Write-GsUtf8 -Path $path -Text (ConvertTo-GsMarkdownReport -Document $Document)
        $written.markdown = $path
    }
    if ($selected -contains 'Json') {
        $path = Join-Path $Directory 'grundschutzcheck-report.json'
        $json = $Document | ConvertTo-Json -Depth 12
        Write-GsUtf8 -Path $path -Text $json
        $written.json = $path
    }
    if ($selected -contains 'Csv') {
        $path = Join-Path $Directory 'grundschutzcheck-findings.csv'
        Write-GsUtf8 -Path $path -Text (ConvertTo-GsCsvReport -Document $Document)
        $written.csv = $path
    }
    return [pscustomobject]$written
}

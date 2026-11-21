BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $script:RepoRoot 'GrundschutzCheck.psd1') -Force
}

Describe 'Demo report' {
    BeforeAll {
        $script:OutDir = Join-Path (Join-Path $script:RepoRoot '.oc-tmp') ('gsc-pester-' + [guid]::NewGuid().ToString('n'))
        $script:Report = Invoke-GrundschutzCheck -Demo -OutputDirectory $script:OutDir -Timestamp '2026-10-21T12:00:00Z'
    }

    AfterAll {
        if (Test-Path -LiteralPath $script:OutDir) {
            Remove-Item -LiteralPath $script:OutDir -Recurse -Force
        }
    }

    It 'renders pass and fail rows and no evaluation errors' {
        $script:Report.summary.error | Should -Be 0
        $script:Report.summary.pass | Should -BeGreaterThan 0
        $script:Report.summary.fail | Should -BeGreaterThan 0
        $script:Report.summary.total | Should -Be ($script:Report.summary.pass + $script:Report.summary.fail)
        @($script:Report.results | Where-Object { $_.id -eq 'GS-W11-010' }).status | Should -Be 'fail'
        @($script:Report.results | Where-Object { $_.id -eq 'GS-W11-048' }).status | Should -Be 'pass'
        @($script:Report.results | Where-Object { $_.id -eq 'GS-W11-061' }).status | Should -Be 'pass'
    }

    It 'writes a self-contained HTML report and the other formats' {
        $htmlPath = $script:Report.outputs.html
        $mdPath = $script:Report.outputs.markdown
        $jsonPath = $script:Report.outputs.json
        $csvPath = $script:Report.outputs.csv
        foreach ($path in @($htmlPath, $mdPath, $jsonPath, $csvPath)) {
            Test-Path -LiteralPath $path | Should -BeTrue
        }
        $html = [System.IO.File]::ReadAllText($htmlPath)
        $html | Should -Match 'fictional'
        $html | Should -Not -Match '<script src'
        $html | Should -Not -Match '<link rel="stylesheet"'
        $markdown = [System.IO.File]::ReadAllText($mdPath)
        $json = [System.IO.File]::ReadAllText($jsonPath)
        foreach ($token in @('DEMO-WIN11-01', 'DEMO.example')) {
            $html.Contains($token) | Should -BeFalse
            $markdown.Contains($token) | Should -BeFalse
            $json.Contains($token) | Should -BeFalse
        }
        $evidenceFile = [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot 'demo/evidence.json'))
        $evidenceFile.Contains('DEMO-WIN11-01') | Should -BeTrue
    }

    It 'records evidence metadata and a stable host fingerprint' {
        $jsonText = [System.IO.File]::ReadAllText($script:Report.outputs.json)
        $jsonText | Should -Match '"generated_at":\s*"2026-10-21T12:00:00Z"'
        $parsed = $jsonText | ConvertFrom-Json
        $parsed.evidence.mode | Should -Be 'demo'
        $parsed.tool.version | Should -Be '0.2.0'
        $parsed.catalog.version | Should -Be '0.1.0'
        @($parsed.summary.modules).Count | Should -BeGreaterThan 0
        @($parsed.summary.grundschutz_plus_plus).Count | Should -BeGreaterThan 0
        $parsed.evidence.host_fingerprint_sha256 | Should -Match '^[0-9a-f]{64}$'
        $expected = InModuleScope GrundschutzCheck {
            Get-GsHostFingerprint -HostInfo @{
                computer_name = 'DEMO-WIN11-01'
                domain        = 'DEMO.example'
                os_caption    = 'Windows 11 Enterprise'
                os_version    = '10.0.26100'
                os_build      = '26100'
            }
        }
        $parsed.evidence.host_fingerprint_sha256 | Should -Be $expected
        $csv = [System.IO.File]::ReadAllText($script:Report.outputs.csv)
        @($csv -split "`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count | Should -Be ($script:Report.summary.total + 1)
    }

    It 'renders the limits of a pass in HTML, Markdown, and JSON' {
        $html = [System.IO.File]::ReadAllText($script:Report.outputs.html)
        $markdown = [System.IO.File]::ReadAllText($script:Report.outputs.markdown)
        $parsed = [System.IO.File]::ReadAllText($script:Report.outputs.json) | ConvertFrom-Json
        $sentences = @(
            'Ein Firewall-Pass belegt keine Allow-List.'
            'Ein Defender-Pass belegt keine aktuellen Signaturen.'
        )
        foreach ($text in @($html, $markdown)) {
            $text | Should -Match 'Grenzen eines Pass'
            foreach ($sentence in $sentences) {
                $text.Contains($sentence) | Should -BeTrue
            }
        }
        @($parsed.catalog.limits).Count | Should -Be 8
        $parsed.summary.total | Should -Be 63
        $notes = @($parsed.catalog.limits | ForEach-Object { $_.note }) -join ' '
        foreach ($sentence in $sentences) {
            $notes.Contains($sentence) | Should -BeTrue
        }
        foreach ($limit in @($parsed.catalog.limits)) {
            @($limit.PSObject.Properties.Name) | Should -Not -Contain 'requirement_id'
        }
    }

    It 'shows N/A column in Grundschutz++ practice tables' {
        $work = Join-Path $script:RepoRoot '.oc-tmp/opencode/report-na'
        New-Item -ItemType Directory -Path $work -Force | Out-Null

        # Build a modified catalog where GS-W11-038 (EnableLUA registry check)
        # gets a GPP reference and when_absent=not_applicable. The demo evidence
        # omits the EnableLUA value, so the check evaluates to not_applicable.
        $catalog = Get-GsCatalog
        $check = $catalog.checks | Where-Object { $_.id -eq 'GS-W11-038' }
        $check.references = @(
            [pscustomobject]@{
                framework      = 'grundschutz-plus-plus'
                requirement_id = 'KONF.2.4'
                title          = 'Deaktivierung nicht benoetigter Systemfunktionen'
                mapping        = 'verified'
                source_id      = 'grundschutz-plus-plus-2026-09-24'
                note           = 'Test fixture for N/A rendering.'
            }
        )
        $check.evaluation.when_absent = 'not_applicable'
        $catalogPath = Join-Path $work 'na-catalog.json'
        [System.IO.File]::WriteAllText($catalogPath, ($catalog | ConvertTo-Json -Depth 12))

        $evidence = [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot 'demo/evidence.json')) | ConvertFrom-Json
        $evidence.registry = @($evidence.registry | Where-Object { $_.name -ne 'EnableLUA' })
        $evidencePath = Join-Path $work 'na-evidence.json'
        [System.IO.File]::WriteAllText($evidencePath, ($evidence | ConvertTo-Json -Depth 12))

        $report = Invoke-GrundschutzCheck -Demo -CatalogPath $catalogPath -EvidencePath $evidencePath -OutputDirectory (Join-Path $work 'out') -Timestamp '2026-11-17T00:00:00Z'

        # At least one practice must have not_applicable > 0.
        $naPractice = @($report.summary.grundschutz_plus_plus | Where-Object { $_.not_applicable -gt 0 })
        $naPractice.Count | Should -BeGreaterThan 0
        $report.summary.not_applicable | Should -BeGreaterOrEqual 1

        # --- HTML: isolate the GPP practice table ---
        $html = [System.IO.File]::ReadAllText($report.outputs.html)
        $htmlStart = $html.IndexOf('Summary by Grundschutz++ practice')
        $htmlSection = $html.Substring($htmlStart)
        $htmlSection | Should -Match '<th>N/A</th>'

        # Sum of the N/A column in the HTML GPP table must equal summary.not_applicable.
        $htmlNaSum = 0
        $rowPattern = '<tr><td>([^<]+)</td><td>[^<]+</td><td>\d+</td><td>\d+</td><td>\d+</td><td>(\d+)</td><td>\d+</td></tr>'
        foreach ($m in [regex]::Matches($htmlSection, $rowPattern)) {
            $htmlNaSum += [int]$m.Groups[2].Value
        }
        $htmlNaSum | Should -Be $report.summary.not_applicable

        # --- Markdown: isolate the GPP practice table ---
        $md = [System.IO.File]::ReadAllText($report.outputs.markdown)
        $mdStart = $md.IndexOf('## Summary by Grundschutz++ practice')
        $mdEnd   = $md.IndexOf('## Checks', $mdStart)
        $mdSection = $md.Substring($mdStart, $mdEnd - $mdStart)
        $mdSection | Should -Match '\| N/A \|'
        $mdSection | Should -Match '\| --- \| --- \| --- \| --- \| --- \| --- \|'

        # Sum of the N/A column in the MD GPP table must equal summary.not_applicable.
        $mdNaSum = 0
        $mdRowPattern = '\| [^|]+ \| [^|]+ \| \d+ \| \d+ \| \d+ \| (\d+) \| \d+ \|'
        foreach ($m in [regex]::Matches($mdSection, $mdRowPattern)) {
            $mdNaSum += [int]$m.Groups[1].Value
        }
        $mdNaSum | Should -Be $report.summary.not_applicable
    }
}

Describe 'Markdown report language switch' {
    BeforeAll {
        $script:LangWork = Join-Path $script:RepoRoot '.oc-tmp/opencode/report-language'
        if (Test-Path -LiteralPath $script:LangWork) {
            Remove-Item -LiteralPath $script:LangWork -Recurse -Force
        }
        New-Item -ItemType Directory -Path $script:LangWork -Force | Out-Null

        $script:DeReport = Invoke-GrundschutzCheck -Demo -OutputDirectory (Join-Path $script:LangWork 'de') -Format Markdown -Timestamp '2026-11-21T00:00:00Z' -Language de
        $script:DeMarkdown = [System.IO.File]::ReadAllText($script:DeReport.outputs.markdown)

        $script:EnDefaultReport = Invoke-GrundschutzCheck -Demo -OutputDirectory (Join-Path $script:LangWork 'en-default') -Format Markdown -Timestamp '2026-11-21T00:00:00Z'
        $script:EnDefaultMarkdown = [System.IO.File]::ReadAllText($script:EnDefaultReport.outputs.markdown)

        $script:EnExplicitReport = Invoke-GrundschutzCheck -Demo -OutputDirectory (Join-Path $script:LangWork 'en-explicit') -Format Markdown -Timestamp '2026-11-21T00:00:00Z' -Language en
        $script:EnExplicitMarkdown = [System.IO.File]::ReadAllText($script:EnExplicitReport.outputs.markdown)
    }

    It 'uses German headings and labels' {
        $script:DeMarkdown | Should -Match '(?m)^# GrundschutzCheck Prüfbericht\r?$'
        $script:DeMarkdown | Should -Match '(?m)^## Nachweise\r?$'
        $script:DeMarkdown | Should -Match '(?m)^## Zusammenfassung\r?$'
        $script:DeMarkdown | Should -Match '(?m)^## Zusammenfassung nach BSI-Modul\r?$'
        $script:DeMarkdown | Should -Match '(?m)^## Zusammenfassung nach Grundschutz\+\+-Praxis\r?$'
        $script:DeMarkdown | Should -Match '(?m)^## Prüfungen\r?$'
        $script:DeMarkdown | Should -Match '(?m)^## Erfasste Audit-Richtlinie\r?$'
        $script:DeMarkdown | Should -Match '\| Modul \| Titel \|'
        $script:DeMarkdown | Should -Match '\| Unterkategorie \| Einstellung \|'
        $script:DeMarkdown.Contains('## Evidence') | Should -BeFalse
        $script:DeMarkdown.Contains('## Summary') | Should -BeFalse
        $script:DeMarkdown.Contains('## Checks') | Should -BeFalse
    }

    It 'keeps the English output as the unchanged default' {
        $script:EnDefaultMarkdown | Should -Be $script:EnExplicitMarkdown
        $script:EnDefaultMarkdown | Should -Match '(?m)^# GrundschutzCheck audit report\r?$'
        $script:EnDefaultMarkdown | Should -Match '(?m)^## Evidence\r?$'
        $script:EnDefaultMarkdown | Should -Match '(?m)^## Summary\r?$'
        $script:EnDefaultMarkdown | Should -Match '(?m)^## Checks\r?$'
    }

    It 'localizes the changes-since-baseline section' {
        $baselineReport = Invoke-GrundschutzCheck -Demo -OutputDirectory (Join-Path $script:LangWork 'baseline-src') -Format Json -Timestamp '2026-11-21T00:00:00Z' -Language en
        $jsonPath = $baselineReport.outputs.json
        $baselineOut = Invoke-GrundschutzCheck -Demo -OutputDirectory (Join-Path $script:LangWork 'de-baseline') -Format Markdown -Timestamp '2026-11-21T01:00:00Z' -Language de -BaselinePath $jsonPath
        $md = [System.IO.File]::ReadAllText($baselineOut.outputs.markdown)
        $md | Should -Match '(?m)^## Änderungen seit der Baseline\r?$'
        $md | Should -Match '\| Änderung \| Anzahl \|'
        $md | Should -Match '\| Weiterhin fehlgeschlagen \|'
        $md.Contains('## Changes since baseline') | Should -BeFalse
    }

    It 'leaves HTML, JSON, and CSV identical across languages' {
        $deAll = Invoke-GrundschutzCheck -Demo -OutputDirectory (Join-Path $script:LangWork 'de-all') -Format All -Timestamp '2026-11-21T02:00:00Z' -Language de
        $enAll = Invoke-GrundschutzCheck -Demo -OutputDirectory (Join-Path $script:LangWork 'en-all') -Format All -Timestamp '2026-11-21T02:00:00Z' -Language en
        foreach ($key in @('html', 'json', 'csv')) {
            $deText = [System.IO.File]::ReadAllText($deAll.outputs.$key)
            $enText = [System.IO.File]::ReadAllText($enAll.outputs.$key)
            $deText | Should -Be $enText
        }
    }

    It 'rejects an unknown language at parameter binding' {
        { Invoke-GrundschutzCheck -Demo -OutputDirectory (Join-Path $script:LangWork 'bad') -Format Markdown -Language fr } | Should -Throw
    }

    AfterAll {
        if (Test-Path -LiteralPath $script:LangWork) {
            Remove-Item -LiteralPath $script:LangWork -Recurse -Force
        }
    }
}

Describe 'Local collection guard' {
    It 'refuses a live run when the platform is not Windows' {
        $onWindows = $false
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            $onWindows = [bool]$IsWindows
        }
        else {
            $onWindows = $true
        }
        if ($onWindows) {
            Set-ItResult -Skipped -Because 'live collection is implemented on Windows'
        }
        { Invoke-GrundschutzCheck -OutputDirectory (Join-Path ([System.IO.Path]::GetTempPath()) 'gsc-should-not-run') } | Should -Throw -ExpectedMessage '*Windows*'
    }
}

Describe 'Read-only source' {
    It 'does not call network or write cmdlets from the module' {
        $files = @(
            Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'src') -Filter '*.ps1' -File
            Get-Item -LiteralPath (Join-Path $script:RepoRoot 'GrundschutzCheck.psm1')
            Get-Item -LiteralPath (Join-Path $script:RepoRoot 'Invoke-GrundschutzCheck.ps1')
        )
        $forbidden = @(
            'Invoke-WebRequest',
            'Invoke-RestMethod',
            'Set-ItemProperty',
            'New-ItemProperty',
            'Remove-ItemProperty',
            'Set-MpPreference',
            'secedit /configure',
            'auditpol /set'
        )
        $hits = @()
        foreach ($file in $files) {
            $text = [System.IO.File]::ReadAllText($file.FullName)
            foreach ($token in $forbidden) {
                if ($text.Contains($token)) {
                    $hits += ($file.Name + ' contains ' + $token)
                }
            }
        }
        ($hits -join "`n") | Should -Be ''
    }
}

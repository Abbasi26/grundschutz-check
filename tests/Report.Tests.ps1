BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $script:RepoRoot 'GrundschutzCheck.psd1') -Force
}

Describe 'Demo report' {
    BeforeAll {
        $script:OutDir = Join-Path ([System.IO.Path]::GetTempPath()) ('gsc-pester-' + [guid]::NewGuid().ToString('n'))
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

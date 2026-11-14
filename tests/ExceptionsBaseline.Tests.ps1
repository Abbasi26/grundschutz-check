BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $script:RepoRoot 'GrundschutzCheck.psd1') -Force
    $script:Work = Join-Path $script:RepoRoot ('.oc-tmp/gsc-v02-' + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Path $script:Work -Force | Out-Null
    $script:ExampleExceptions = Join-Path $script:RepoRoot 'examples/exceptions.example.json'
    $script:ExampleExceptionsCsv = Join-Path $script:RepoRoot 'examples/exceptions.example.csv'
    $script:Stamp = '2026-10-21T12:00:00Z'
    function script:Write-TestFile {
        param([string]$Name, [string]$Text)
        $path = Join-Path $script:Work $Name
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($path, $Text, $utf8)
        return $path
    }
    function script:Write-TestJson {
        param([string]$Name, [string]$Text)
        return (Write-TestFile -Name $Name -Text $Text)
    }
    function script:Get-Row {
        param($Report, [string]$Id)
        return @($Report.results | Where-Object { $_.id -eq $Id })[0]
    }
}

AfterAll {
    if (Test-Path -LiteralPath $script:Work) { Remove-Item -LiteralPath $script:Work -Recurse -Force }
}

Describe 'Exceptions (accepted risk)' {
    BeforeAll {
        $script:Plain = Invoke-GrundschutzCheck -Demo -OutputDirectory (Join-Path $script:Work 'plain') -Timestamp $script:Stamp
        $script:WithEx = Invoke-GrundschutzCheck -Demo -OutputDirectory (Join-Path $script:Work 'ex') -Timestamp $script:Stamp -ExceptionPath $script:ExampleExceptions
    }

    It 'turns a failing check with a current exception into accepted' {
        $row = Get-Row $script:WithEx 'GS-W11-004'
        $row.status | Should -Be 'accepted'
        $row.exception.state | Should -Be 'applied'
        $row.exception.owner | Should -Match 'IT security officer'
        $row.message | Should -Match 'Accepted risk until 2027-06-30'
    }

    It 'keeps an expired exception as fail and says so' {
        $row = Get-Row $script:WithEx 'GS-W11-008'
        $row.status | Should -Be 'fail'
        $row.exception.state | Should -Be 'expired'
        $row.message | Should -Match 'expired on 2026-06-30'
        (@($script:WithEx.evidence.notes) -join ' ') | Should -Match 'GS-W11-008 expired'
    }

    It 'moves counts from fail to accepted without changing the total' {
        $script:WithEx.summary.accepted | Should -Be 2
        $script:WithEx.summary.fail | Should -Be ($script:Plain.summary.fail - 2)
        $script:WithEx.summary.total | Should -Be $script:Plain.summary.total
        $script:Plain.summary.accepted | Should -Be 0
    }

    It 'shows accepted risks in every report format' {
        $html = [System.IO.File]::ReadAllText($script:WithEx.outputs.html)
        $html | Should -Match 'accepted risk'
        $html | Should -Match 'data-filter="accepted"'
        $md = [System.IO.File]::ReadAllText($script:WithEx.outputs.markdown)
        $md | Should -Match 'Accepted risk \(documented exception\): 2'
        $md | Should -Match 'GS-W11-004 - accepted'
        $csv = [System.IO.File]::ReadAllText($script:WithEx.outputs.csv)
        $csv | Should -Match '"GS-W11-004","[^"]*","accepted"'
        $json = [System.IO.File]::ReadAllText($script:WithEx.outputs.json) | ConvertFrom-Json
        @($json.results | Where-Object { $_.id -eq 'GS-W11-004' })[0].exception.ticket | Should -Be 'RISK-0001'
    }

    It 'notes an exception that is no longer needed' {
        $path = Write-TestJson 'pass-ex.json' '{"exceptions":[{"check_id":"GS-W11-048","reason":"r","owner":"o","expires":"2030-01-01"}]}'
        $r = Invoke-GrundschutzCheck -Demo -OutputDirectory (Join-Path $script:Work 'pass-ex') -Timestamp $script:Stamp -ExceptionPath $path -Format Json
        (Get-Row $r 'GS-W11-048').status | Should -Be 'pass'
        (Get-Row $r 'GS-W11-048').exception.state | Should -Be 'not_needed'
        (@($r.evidence.notes) -join ' ') | Should -Match 'no longer needed'
    }

    It 'rejects unknown checks, missing fields, bad dates, and duplicates' {
        $path = Write-TestJson 'bad-ex.json' '{"exceptions":[{"check_id":"GS-W11-999","reason":"r","owner":"o","expires":"2030-01-01"},{"check_id":"GS-W11-010","owner":"o","expires":"next year"},{"check_id":"GS-W11-010","reason":"r","owner":"o","expires":"2030-01-01"}]}'
        $err = $null
        try { Invoke-GrundschutzCheck -Demo -OutputDirectory (Join-Path $script:Work 'bad') -ExceptionPath $path -Format Json | Out-Null } catch { $err = $_.Exception.Message }
        $err | Should -Match 'unknown check GS-W11-999'
        $err | Should -Match 'has no reason'
        $err | Should -Match 'yyyy-MM-dd'
        $err | Should -Match 'repeats check GS-W11-010'
    }

    It 'requires an exceptions array' {
        $path = Write-TestJson 'no-array.json' '{"items":[]}'
        { Invoke-GrundschutzCheck -Demo -OutputDirectory (Join-Path $script:Work 'noarr') -ExceptionPath $path -Format Json } | Should -Throw "*'exceptions' array*"
    }

    It 'accepts CSV exceptions like JSON in demo mode' {
        $jsonReport = Invoke-GrundschutzCheck -Demo -OutputDirectory (Join-Path $script:Work 'ex-json') -Timestamp $script:Stamp -ExceptionPath $script:ExampleExceptions
        $csvReport = Invoke-GrundschutzCheck -Demo -OutputDirectory (Join-Path $script:Work 'ex-csv') -Timestamp $script:Stamp -ExceptionPath $script:ExampleExceptionsCsv
        $csvReport.summary.accepted | Should -Be $jsonReport.summary.accepted
        $csvReport.summary.fail | Should -Be $jsonReport.summary.fail
        $csvReport.summary.total | Should -Be $jsonReport.summary.total
        foreach ($id in @('GS-W11-004', 'GS-W11-008', 'GS-W11-052')) {
            $j = Get-Row $jsonReport $id
            $c = Get-Row $csvReport $id
            $c.status | Should -Be $j.status
            $c.exception.state | Should -Be $j.exception.state
            $c.exception.reason | Should -Be $j.exception.reason
            $c.exception.owner | Should -Be $j.exception.owner
            $c.exception.expires | Should -Be $j.exception.expires
            $c.exception.ticket | Should -Be $j.exception.ticket
        }
    }

    It 'accepts a CSV with only a header as an empty exception list' {
        $path = Write-TestFile 'header-only.csv' "check_id,reason,owner,expires,ticket`n"
        $r = Invoke-GrundschutzCheck -Demo -OutputDirectory (Join-Path $script:Work 'header-only') -Timestamp $script:Stamp -ExceptionPath $path -Format Json
        $r.summary.accepted | Should -Be 0
        $r.summary.fail | Should -Be $script:Plain.summary.fail
    }

    It 'accepts CSV with an empty ticket and quoted commas' {
        $path = Write-TestFile 'quoted.csv' "check_id,reason,owner,expires,ticket`nGS-W11-048,""Grund, mit Komma"",Beauftragte Müller,2030-01-01,"
        $r = Invoke-GrundschutzCheck -Demo -OutputDirectory (Join-Path $script:Work 'quoted') -Timestamp $script:Stamp -ExceptionPath $path -Format Json
        (Get-Row $r 'GS-W11-048').status | Should -Be 'pass'
        (Get-Row $r 'GS-W11-048').exception.ticket | Should -Be ''
        (Get-Row $r 'GS-W11-048').exception.reason | Should -Be 'Grund, mit Komma'
        (Get-Row $r 'GS-W11-048').exception.owner | Should -Be 'Beauftragte Müller'
    }

    It 'rejects a CSV missing required columns' {
        foreach ($case in @(
            @{ name = 'no-check.csv'; text = "reason,owner,expires,ticket`nr,o,2030-01-01,t" },
            @{ name = 'no-reason.csv'; text = "check_id,owner,expires,ticket`nGS-W11-048,o,2030-01-01,t" },
            @{ name = 'no-owner.csv'; text = "check_id,reason,expires,ticket`nGS-W11-048,r,2030-01-01,t" },
            @{ name = 'no-expires.csv'; text = "check_id,reason,owner,ticket`nGS-W11-048,r,o,t" },
            @{ name = 'no-ticket.csv'; text = "check_id,reason,owner,expires`nGS-W11-048,r,o,2030-01-01" }
        )) {
            $path = Write-TestFile $case.name $case.text
            { Invoke-GrundschutzCheck -Demo -OutputDirectory (Join-Path $script:Work $case.name) -ExceptionPath $path -Format Json } | Should -Throw '*missing required CSV column*'
        }
    }

    It 'rejects unknown checks, missing values, bad dates, and duplicates in CSV' {
        $path = Write-TestFile 'bad-ex.csv' (@(
            'check_id,reason,owner,expires,ticket'
            'GS-W11-999,r,o,2030-01-01,t'
            'GS-W11-010,,o,next year,t'
            'GS-W11-010,r,o,2030-01-01,t'
            'GS-W11-011,r,o,2026-02-30,t'
        ) -join "`n")
        $err = $null
        try { Invoke-GrundschutzCheck -Demo -OutputDirectory (Join-Path $script:Work 'bad-csv') -ExceptionPath $path -Format Json | Out-Null } catch { $err = $_.Exception.Message }
        $err | Should -Match 'CSV row 1 names unknown check GS-W11-999'
        $err | Should -Match 'CSV row 2 \(GS-W11-010\) has no reason'
        $err | Should -Match 'CSV row 2 \(GS-W11-010\) needs expires as yyyy-MM-dd'
        $err | Should -Match 'CSV row 3 repeats check GS-W11-010'
        $err | Should -Match 'CSV row 4 \(GS-W11-011\) needs expires as yyyy-MM-dd'
    }

    It 'rejects an empty or headerless CSV file' {
        $empty = Write-TestFile 'empty.csv' ''
        { Invoke-GrundschutzCheck -Demo -OutputDirectory (Join-Path $script:Work 'empty-csv') -ExceptionPath $empty -Format Json } | Should -Throw '*empty or has no header*'
    }
}

Describe 'Baseline comparison' {
    BeforeAll {
        $script:BaseDir = Join-Path $script:Work 'base'
        $base = Invoke-GrundschutzCheck -Demo -OutputDirectory $script:BaseDir -Timestamp $script:Stamp -Format Json
        $script:BaseJson = $base.outputs.json
        # Edit the baseline: pretend GS-W11-010 passed before and GS-W11-048 failed before.
        $doc = [System.IO.File]::ReadAllText($script:BaseJson) | ConvertFrom-Json
        foreach ($row in $doc.results) {
            if ($row.id -eq 'GS-W11-010') { $row.status = 'pass' }
            if ($row.id -eq 'GS-W11-048') { $row.status = 'fail' }
        }
        $doc.results = @($doc.results | Where-Object { $_.id -ne 'GS-W11-061' })
        $script:EditedBase = Join-Path $script:Work 'edited-base.json'
        [System.IO.File]::WriteAllText($script:EditedBase, ($doc | ConvertTo-Json -Depth 12))
        $script:Cmp = Invoke-GrundschutzCheck -Demo -OutputDirectory (Join-Path $script:Work 'cmp') -Timestamp '2026-10-28T12:00:00Z' -BaselinePath $script:EditedBase
    }

    It 'finds newly failing, fixed, and new checks' {
        $c = $script:Cmp.comparison
        @($c.newly_failing | ForEach-Object { $_.id }) | Should -Be @('GS-W11-010')
        @($c.fixed | ForEach-Object { $_.id }) | Should -Be @('GS-W11-048')
        @($c.new_checks | ForEach-Object { $_.id }) | Should -Be @('GS-W11-061')
        @($c.still_failing).Count | Should -Be ($script:Cmp.summary.fail - 1)
        $c.same_host | Should -BeTrue
        $c.baseline_generated_at | Should -Match '^2026-10-21'
    }

    It 'reports no changes against an identical baseline' {
        $r = Invoke-GrundschutzCheck -Demo -OutputDirectory (Join-Path $script:Work 'same') -Timestamp $script:Stamp -BaselinePath $script:BaseJson -Format Json
        @($r.comparison.newly_failing).Count | Should -Be 0
        @($r.comparison.fixed).Count | Should -Be 0
    }

    It 'renders the comparison in Markdown, HTML, and JSON' {
        $md = [System.IO.File]::ReadAllText($script:Cmp.outputs.markdown)
        $md | Should -Match '## Changes since baseline'
        $md | Should -Match 'Newly failing: GS-W11-010'
        $md | Should -Match 'Fixed: GS-W11-048'
        [System.IO.File]::ReadAllText($script:Cmp.outputs.html) | Should -Match 'Changes since baseline'
        $json = [System.IO.File]::ReadAllText($script:Cmp.outputs.json) | ConvertFrom-Json
        @($json.comparison.newly_failing)[0].id | Should -Be 'GS-W11-010'
    }

    It 'rejects a baseline without results' {
        $path = Write-TestJson 'empty-base.json' '{"results":[]}'
        { Invoke-GrundschutzCheck -Demo -OutputDirectory (Join-Path $script:Work 'eb') -BaselinePath $path -Format Json } | Should -Throw '*no results*'
    }
}

Describe 'Script exit codes with -FailOnRegression' {
    BeforeAll {
        $script:Script = Join-Path $script:RepoRoot 'Invoke-GrundschutzCheck.ps1'
        $script:Pwsh = (Get-Process -Id $PID).Path
    }

    It 'exits 0 when nothing regressed even though checks fail' {
        $base = Join-Path $script:Work 'base/grundschutzcheck-report.json'
        & $script:Pwsh -NoProfile -File $script:Script -Demo -OutputDirectory (Join-Path $script:Work 'x1') -Timestamp $script:Stamp -BaselinePath $base -FailOnRegression | Out-Null
        $LASTEXITCODE | Should -Be 0
    }

    It 'exits 1 when a check newly fails' {
        & $script:Pwsh -NoProfile -File $script:Script -Demo -OutputDirectory (Join-Path $script:Work 'x2') -Timestamp $script:Stamp -BaselinePath $script:EditedBase -FailOnRegression | Out-Null
        $LASTEXITCODE | Should -Be 1
    }
}

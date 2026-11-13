BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $script:RepoRoot 'GrundschutzCheck.psd1') -Force
    $script:Work = Join-Path ([System.IO.Path]::GetTempPath()) ('gsc-v02-' + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Path $script:Work | Out-Null
    $script:ExampleExceptions = Join-Path $script:RepoRoot 'examples/exceptions.example.json'
    $script:Stamp = '2026-10-21T12:00:00Z'
    function script:Write-TestJson {
        param([string]$Name, [string]$Text)
        $path = Join-Path $script:Work $Name
        [System.IO.File]::WriteAllText($path, $Text)
        return $path
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

Describe 'Exception expiry warnings' {
    BeforeAll {
        $script:WarnWork = Join-Path $script:RepoRoot '.oc-tmp/pester-exception-expiry'
        if (Test-Path -LiteralPath $script:WarnWork) { Remove-Item -LiteralPath $script:WarnWork -Recurse -Force }
        New-Item -ItemType Directory -Path $script:WarnWork | Out-Null
        function script:Write-WarnJson {
            param([string]$Name, [string]$Text)
            $path = Join-Path $script:WarnWork $Name
            [System.IO.File]::WriteAllText($path, $Text)
            return $path
        }
    }

    AfterAll {
        if (Test-Path -LiteralPath $script:WarnWork) { Remove-Item -LiteralPath $script:WarnWork -Recurse -Force }
    }

    It 'warns for a current applied exception expiring in <Days> days' -TestCases @(
        @{ Days = 0;  Expires = '2026-10-21' }
        @{ Days = 1;  Expires = '2026-10-22' }
        @{ Days = 30; Expires = '2026-11-20' }
    ) {
        param($Days, $Expires)
        $path = Write-WarnJson "soon-$Days.json" ('{"exceptions":[{"check_id":"GS-W11-004","reason":"r","owner":"o","expires":"' + $Expires + '"}]}')
        $r = Invoke-GrundschutzCheck -Demo -OutputDirectory (Join-Path $script:WarnWork "soon-$Days") -Timestamp $script:Stamp -ExceptionPath $path -Format Json
        $row = Get-Row $r 'GS-W11-004'
        $row.status | Should -Be 'accepted'
        $row.exception.state | Should -Be 'applied'
        $notes = @($r.evidence.notes) -join ' '
        $notes | Should -Match 'GS-W11-004 expires soon'
        $notes | Should -Match $Expires
        $notes | Should -Match 'within 30 days'
    }

    It 'does not warn when the exception expires in more than 30 days and keeps counts the same as a soon-expiring case' {
        $soonPath = Write-WarnJson 'cmp-30.json' '{"exceptions":[{"check_id":"GS-W11-004","reason":"r","owner":"o","expires":"2026-11-20"}]}'
        $latePath = Write-WarnJson 'cmp-31.json' '{"exceptions":[{"check_id":"GS-W11-004","reason":"r","owner":"o","expires":"2026-11-21"}]}'
        $soon = Invoke-GrundschutzCheck -Demo -OutputDirectory (Join-Path $script:WarnWork 'cmp-30') -Timestamp $script:Stamp -ExceptionPath $soonPath -Format Json
        $late = Invoke-GrundschutzCheck -Demo -OutputDirectory (Join-Path $script:WarnWork 'cmp-31') -Timestamp $script:Stamp -ExceptionPath $latePath -Format Json
        $soonRow = Get-Row $soon 'GS-W11-004'
        $lateRow = Get-Row $late 'GS-W11-004'
        $soonRow.status | Should -Be 'accepted'
        $lateRow.status | Should -Be 'accepted'
        $soonRow.exception.state | Should -Be 'applied'
        $lateRow.exception.state | Should -Be 'applied'
        (@($soon.evidence.notes) -join ' ') | Should -Match 'expires soon'
        (@($late.evidence.notes) -join ' ') | Should -Not -Match 'expires soon'
        $late.summary.total | Should -Be $soon.summary.total
        $late.summary.accepted | Should -Be $soon.summary.accepted
        $late.summary.fail | Should -Be $soon.summary.fail
        $late.summary.pass | Should -Be $soon.summary.pass
        $late.summary.error | Should -Be $soon.summary.error
    }

    It 'keeps only the existing message for an already expired exception' {
        $row = Get-Row $script:WithEx 'GS-W11-008'
        $row.status | Should -Be 'fail'
        $row.exception.state | Should -Be 'expired'
        $notes = @($script:WithEx.evidence.notes) -join ' '
        $notes | Should -Match 'GS-W11-008 expired'
        $notes | Should -Not -Match 'GS-W11-008 expires soon'
    }

    It 'does not warn for a passing check even if its exception expires soon' {
        $path = Write-WarnJson 'pass-soon.json' '{"exceptions":[{"check_id":"GS-W11-048","reason":"r","owner":"o","expires":"2026-10-22"}]}'
        $r = Invoke-GrundschutzCheck -Demo -OutputDirectory (Join-Path $script:WarnWork 'pass-soon') -Timestamp $script:Stamp -ExceptionPath $path -Format Json
        $row = Get-Row $r 'GS-W11-048'
        $row.status | Should -Be 'pass'
        $row.exception.state | Should -Be 'not_needed'
        (@($r.evidence.notes) -join ' ') | Should -Not -Match 'expires soon'
        (@($r.evidence.notes) -join ' ') | Should -Match 'no longer needed'
    }

    It 'does not warn for an evaluation error even if its exception expires soon' {
        InModuleScope GrundschutzCheck {
            $pairs = @([pscustomobject]@{
                Check      = [pscustomobject]@{ id = 'GS-W11-099' }
                Evaluation = [pscustomobject]@{ Status = 'error'; Message = 'boom' }
            })
            $exceptions = @{
                'GS-W11-099' = [pscustomobject]@{ check_id = 'GS-W11-099'; reason = 'r'; owner = 'o'; expires = '2026-10-22'; ticket = '' }
            }
            $notes = @(Set-GsExceptionStatus -Pairs $pairs -Exceptions $exceptions -Timestamp '2026-10-21T12:00:00Z')
            $pairs[0].Evaluation.Status | Should -Be 'error'
            $pairs[0].Evaluation.Exception.state | Should -Be 'not_applied_error'
            ($notes -join ' ') | Should -Match 'could not be evaluated'
            ($notes -join ' ') | Should -Not -Match 'expires soon'
        }
    }
}

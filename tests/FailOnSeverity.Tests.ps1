BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $script:RepoRoot 'GrundschutzCheck.psd1') -Force
    $script:Work = Join-Path $script:RepoRoot '.oc-tmp/fos'
    New-Item -ItemType Directory -Path $script:Work -Force | Out-Null
    $script:Stamp = '2026-10-21T12:00:00Z'
    $script:Script = Join-Path $script:RepoRoot 'Invoke-GrundschutzCheck.ps1'
    $script:Pwsh = (Get-Process -Id $PID).Path
    $script:Document = [pscustomobject]@{
        results = @(
            [pscustomobject]@{ id = 'low'; status = 'fail'; severity = 'low' }
            [pscustomobject]@{ id = 'medium'; status = 'fail'; severity = 'medium' }
            [pscustomobject]@{ id = 'high'; status = 'fail'; severity = 'high' }
            [pscustomobject]@{ id = 'critical'; status = 'fail'; severity = 'critical' }
            [pscustomobject]@{ id = 'acc'; status = 'accepted'; severity = 'critical' }
            [pscustomobject]@{ id = 'err'; status = 'error'; severity = 'critical' }
        )
    }
}

AfterAll {
    if (Test-Path -LiteralPath $script:Work) { Remove-Item -LiteralPath $script:Work -Recurse -Force }
}

Describe 'Get-GsBlockingFailures' {
    It 'returns only high and critical fails for -MinimumSeverity high' {
        $ids = @(Get-GsBlockingFailures -Document $script:Document -MinimumSeverity 'high' | ForEach-Object { $_.id })
        $ids | Should -Be @('high', 'critical')
    }

    It 'counts every fail at or above informational but never accepted or error' {
        @(Get-GsBlockingFailures -Document $script:Document -MinimumSeverity 'informational').Count | Should -Be 4
    }
}

Describe 'Script exit codes with -FailOnSeverity' {
    It 'exits 1 for a plain demo run' {
        & $script:Pwsh -NoProfile -File $script:Script -Demo -OutputDirectory (Join-Path $script:Work 'plain') -Timestamp $script:Stamp | Out-Null
        $LASTEXITCODE | Should -Be 1
    }

    It 'exits 0 with -FailOnSeverity critical because the demo has no critical fail' {
        & $script:Pwsh -NoProfile -File $script:Script -Demo -OutputDirectory (Join-Path $script:Work 'crit') -Timestamp $script:Stamp -FailOnSeverity critical | Out-Null
        $LASTEXITCODE | Should -Be 0
    }

    It 'exits 1 with -FailOnSeverity high' {
        & $script:Pwsh -NoProfile -File $script:Script -Demo -OutputDirectory (Join-Path $script:Work 'high') -Timestamp $script:Stamp -FailOnSeverity high | Out-Null
        $LASTEXITCODE | Should -Be 1
    }

    It 'exits 1 with -FailOnSeverity medium' {
        & $script:Pwsh -NoProfile -File $script:Script -Demo -OutputDirectory (Join-Path $script:Work 'medium') -Timestamp $script:Stamp -FailOnSeverity medium | Out-Null
        $LASTEXITCODE | Should -Be 1
    }

    It 'rejects -FailOnSeverity together with -FailOnRegression before the baseline check' {
        # Windows PowerShell 5.1 turns native stderr into a terminating error when
        # $ErrorActionPreference is Stop (Pester's default). The child pwsh writes
        # the rejection message to stderr, so lower the preference inside the scope
        # that captures it. PowerShell 7 keeps native stderr non-terminating.
        $out = & {
            $ErrorActionPreference = 'Continue'
            & $script:Pwsh -NoProfile -File $script:Script -Demo -OutputDirectory (Join-Path $script:Work 'both') -Timestamp $script:Stamp -FailOnRegression -FailOnSeverity high 2>&1
        }
        $LASTEXITCODE | Should -Not -Be 0
        ($out -join ' ') | Should -Match 'FailOnSeverity.*FailOnRegression|cannot.*both'
    }
}
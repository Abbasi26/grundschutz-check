BeforeAll {
    Import-Module GrundschutzCheck -Force
}

Describe 'Invoke-GsEvaluation - registry' {
    It 'returns pass when value matches' {
        $eval = @{
            method = 'registry'
            hive   = 'HKLM'
            path   = 'SOFTWARE\Test'
            name   = 'Value1'
            operator = 'equals'
            expected = 1
        }
        $evidence = @{
            registry = @(
                @{ hive = 'HKLM'; path = 'SOFTWARE\Test'; name = 'Value1'; value = 1 }
            )
        }
        $result = Invoke-GsEvaluation -Evaluation $eval -Evidence $evidence
        $result.Status | Should -Be 'pass'
    }

    It 'returns fail when value does not match' {
        $eval = @{
            method = 'registry'
            hive   = 'HKLM'
            path   = 'SOFTWARE\Test'
            name   = 'Value1'
            operator = 'equals'
            expected = 1
        }
        $evidence = @{
            registry = @(
                @{ hive = 'HKLM'; path = 'SOFTWARE\Test'; name = 'Value1'; value = 0 }
            )
        }
        $result = Invoke-GsEvaluation -Evaluation $eval -Evidence $evidence
        $result.Status | Should -Be 'fail'
    }

    It 'returns error when evidence missing' {
        $eval = @{
            method = 'registry'
            hive   = 'HKLM'
            path   = 'SOFTWARE\Test'
            name   = 'Value1'
            operator = 'equals'
            expected = 1
        }
        $evidence = @{}
        $result = Invoke-GsEvaluation -Evaluation $eval -Evidence $evidence
        $result.Status | Should -Be 'error'
    }

    It 'returns error when collection error present' {
        $eval = @{
            method = 'registry'
            hive   = 'HKLM'
            path   = 'SOFTWARE\Test'
            name   = 'Value1'
            operator = 'equals'
            expected = 1
        }
        $evidence = @{
            registry_error = 'Access denied'
        }
        $result = Invoke-GsEvaluation -Evaluation $eval -Evidence $evidence
        $result.Status | Should -Be 'error'
    }

    It 'handles when_absent pass' {
        $eval = @{
            method = 'registry'
            hive   = 'HKLM'
            path   = 'SOFTWARE\Test'
            name   = 'Missing'
            operator = 'equals'
            expected = 1
            when_absent = 'pass'
        }
        $evidence = @{
            registry = @()
        }
        $result = Invoke-GsEvaluation -Evaluation $eval -Evidence $evidence
        $result.Status | Should -Be 'pass'
    }

    It 'handles when_absent not_applicable' {
        $eval = @{
            method = 'registry'
            hive   = 'HKLM'
            path   = 'SOFTWARE\Test'
            name   = 'Missing'
            operator = 'equals'
            expected = 1
            when_absent = 'not_applicable'
        }
        $evidence = @{
            registry = @()
        }
        $result = Invoke-GsEvaluation -Evaluation $eval -Evidence $evidence
        $result.Status | Should -Be 'not_applicable'
    }
}

Describe 'Invoke-GsEvaluation - all_of' {
    It 'returns pass when all children pass' {
        $eval = @{
            method = 'all_of'
            evaluations = @(
                @{ method = 'registry'; hive = 'HKLM'; path = 'A'; name = 'V1'; operator = 'equals'; expected = 1 }
                @{ method = 'registry'; hive = 'HKLM'; path = 'A'; name = 'V2'; operator = 'equals'; expected = 2 }
            )
        }
        $evidence = @{
            registry = @(
                @{ hive = 'HKLM'; path = 'A'; name = 'V1'; value = 1 }
                @{ hive = 'HKLM'; path = 'A'; name = 'V2'; value = 2 }
            )
        }
        $result = Invoke-GsEvaluation -Evaluation $eval -Evidence $evidence
        $result.Status | Should -Be 'pass'
    }

    It 'returns fail when any child fails' {
        $eval = @{
            method = 'all_of'
            evaluations = @(
                @{ method = 'registry'; hive = 'HKLM'; path = 'A'; name = 'V1'; operator = 'equals'; expected = 1 }
                @{ method = 'registry'; hive = 'HKLM'; path = 'A'; name = 'V2'; operator = 'equals'; expected = 2 }
            )
        }
        $evidence = @{
            registry = @(
                @{ hive = 'HKLM'; path = 'A'; name = 'V1'; value = 1 }
                @{ hive = 'HKLM'; path = 'A'; name = 'V2'; value = 99 }
            )
        }
        $result = Invoke-GsEvaluation -Evaluation $eval -Evidence $evidence
        $result.Status | Should -Be 'fail'
    }

    It 'returns error when any child errors and none fail' {
        $eval = @{
            method = 'all_of'
            evaluations = @(
                @{ method = 'registry'; hive = 'HKLM'; path = 'A'; name = 'V1'; operator = 'equals'; expected = 1 }
                @{ method = 'defender'; property = 'DisableRealtimeMonitoring'; operator = 'equals'; expected = $false }
            )
        }
        $evidence = @{
            registry = @(
                @{ hive = 'HKLM'; path = 'A'; name = 'V1'; value = 1 }
            )
        }
        $result = Invoke-GsEvaluation -Evaluation $eval -Evidence $evidence
        $result.Status | Should -Be 'error'
    }

    It 'returns not_applicable when all children not_applicable' {
        $eval = @{
            method = 'all_of'
            evaluations = @(
                @{ method = 'registry'; hive = 'HKLM'; path = 'A'; name = 'Missing1'; operator = 'equals'; expected = 1; when_absent = 'not_applicable' }
                @{ method = 'registry'; hive = 'HKLM'; path = 'A'; name = 'Missing2'; operator = 'equals'; expected = 1; when_absent = 'not_applicable' }
            )
        }
        $evidence = @{
            registry = @()
        }
        $result = Invoke-GsEvaluation -Evaluation $eval -Evidence $evidence
        $result.Status | Should -Be 'not_applicable'
    }

    It 'returns error for empty composite' {
        $eval = @{
            method = 'all_of'
            evaluations = @()
        }
        $evidence = @{}
        $result = Invoke-GsEvaluation -Evaluation $eval -Evidence $evidence
        $result.Status | Should -Be 'error'
    }
}

Describe 'any_of status precedence' {
    It 'returns <ExpectedStatus> for <LeftStatus> and <RightStatus> in either order' -ForEach @(
        @{ LeftStatus = 'fail'; RightStatus = 'error'; ExpectedStatus = 'error' }
        @{ LeftStatus = 'pass'; RightStatus = 'error'; ExpectedStatus = 'pass' }
        @{ LeftStatus = 'fail'; RightStatus = 'not_applicable'; ExpectedStatus = 'fail' }
        @{ LeftStatus = 'not_applicable'; RightStatus = 'not_applicable'; ExpectedStatus = 'not_applicable' }
    ) {
        InModuleScope GrundschutzCheck -Parameters @{
            LeftStatus = $LeftStatus
            RightStatus = $RightStatus
            ExpectedStatus = $ExpectedStatus
        } {
            param($LeftStatus, $RightStatus, $ExpectedStatus)

            $children = @{
                pass = @{
                    method = 'registry'; hive = 'HKLM'; path = 'A'; name = 'Present'
                    operator = 'equals'; expected = 1
                }
                fail = @{
                    method = 'registry'; hive = 'HKLM'; path = 'A'; name = 'Present'
                    operator = 'equals'; expected = 0
                }
                error = @{
                    method = 'defender'; property = 'DisableRealtimeMonitoring'
                    operator = 'equals'; expected = $false
                }
                not_applicable = @{
                    method = 'registry'; hive = 'HKLM'; path = 'A'; name = 'Missing'
                    operator = 'equals'; expected = 1; when_absent = 'not_applicable'
                }
            }
            $evidence = @{
                registry = @(
                    @{ hive = 'HKLM'; path = 'A'; name = 'Present'; value = 1 }
                )
            }

            foreach ($reverse in @($false, $true)) {
                $evaluations = @($children[$LeftStatus], $children[$RightStatus])
                if ($reverse) {
                    [array]::Reverse($evaluations)
                }
                $result = Invoke-GsEvaluation -Evaluation @{
                    method = 'any_of'; evaluations = $evaluations
                } -Evidence $evidence
                $result.Status | Should -Be $ExpectedStatus
            }
        }
    }
}
# Not checked: full suites or live Windows collection; no repository files were changed.
# Risk: custom fail/error alternatives become error and can change CLI exit code to 2.

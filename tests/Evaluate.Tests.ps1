BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $script:RepoRoot 'GrundschutzCheck.psd1') -Force
}

Describe 'Evaluators' {
    It 'parses a secedit export and strips quotes' {
        InModuleScope GrundschutzCheck -Parameters @{ RepoRoot = $script:RepoRoot } {
            param($RepoRoot)
            $text = [System.IO.File]::ReadAllText((Join-Path $RepoRoot 'tests/fixtures/secedit-sample.inf'))
            $rows = @(ConvertFrom-GsSeceditText -Text $text)
            $history = @($rows | Where-Object { $_.key -eq 'PasswordHistorySize' })[0]
            $history.section | Should -Be 'System Access'
            $history.value | Should -Be '24'
            $name = @($rows | Where-Object { $_.key -eq 'NewAdministratorName' })[0]
            $name.value | Should -Be 'LocalAdmin'
        }
    }

    It 'normalizes English and German audit policy text' {
        InModuleScope GrundschutzCheck {
            $noAudit = 'Keine {0}berwachung' -f [string]([char]0x00DC)
            $text = @"
Logon                                     Success and Failure
Credential Validation                     Erfolg und Fehler
Account Lockout                           $noAudit
Logoff                                    Erfolg
"@
            $rows = @(ConvertFrom-GsAuditpolText -Text $text)
            ($rows | Where-Object { $_.subcategory -eq 'Logon' }).setting | Should -Be 'Success and Failure'
            ($rows | Where-Object { $_.subcategory -eq 'Credential Validation' }).setting | Should -Be 'Success and Failure'
            ($rows | Where-Object { $_.subcategory -eq 'Account Lockout' }).setting | Should -Be 'No Auditing'
            ($rows | Where-Object { $_.subcategory -eq 'Logoff' }).setting | Should -Be 'Success'
        }
    }

    It 'parses auditpol CSV' {
        InModuleScope GrundschutzCheck -Parameters @{ RepoRoot = $script:RepoRoot } {
            param($RepoRoot)
            $text = [System.IO.File]::ReadAllText((Join-Path $RepoRoot 'tests/fixtures/auditpol-sample.csv'))
            $rows = @(ConvertFrom-GsAuditpolCsv -Text $text)
            $rows.Count | Should -Be 3
            ($rows | Where-Object { $_.subcategory -eq 'Credential Validation' }).setting | Should -Be 'Success and Failure'
        }
    }

    It 'compares registry values, including absence' {
        InModuleScope GrundschutzCheck {
            $pass = Invoke-GsEvaluation -Evaluation @{
                method = 'registry'; hive = 'HKLM'; path = 'SOFTWARE\Example'; name = 'AllowTelemetry'
                operator = 'equals'; expected = 0
            } -Evidence @{
                registry = @(@{ hive = 'HKLM'; path = 'software\example'; name = 'allowtelemetry'; value = 0 })
            }
            $pass.Status | Should -Be 'pass'

            $fail = Invoke-GsEvaluation -Evaluation @{
                method = 'registry'; hive = 'HKLM'; path = 'SOFTWARE\Example'; name = 'AllowTelemetry'
                operator = 'equals'; expected = 0
            } -Evidence @{
                registry = @(@{ hive = 'HKLM'; path = 'SOFTWARE\Example'; name = 'AllowTelemetry'; value = 1 })
            }
            $fail.Status | Should -Be 'fail'

            $missing = Invoke-GsEvaluation -Evaluation @{
                method = 'registry'; hive = 'HKLM'; path = 'SOFTWARE\Example'; name = 'Gone'
                operator = 'equals'; expected = 1
            } -Evidence @{ registry = @() }
            $missing.Status | Should -Be 'fail'

            $accepted = Invoke-GsEvaluation -Evaluation @{
                method = 'registry'; hive = 'HKLM'; path = 'SOFTWARE\Example'; name = 'Gone'
                operator = 'equals'; expected = 0; when_absent = 'pass'
            } -Evidence @{ registry = @() }
            $accepted.Status | Should -Be 'pass'
        }
    }

    It 'fails all_of when any child fails' {
        InModuleScope GrundschutzCheck {
            $result = Invoke-GsEvaluation -Evaluation @{
                method = 'all_of'
                evaluations = @(
                    @{ method = 'registry'; hive = 'HKLM'; path = 'A'; name = 'One'; operator = 'equals'; expected = 1 },
                    @{ method = 'registry'; hive = 'HKLM'; path = 'A'; name = 'Two'; operator = 'equals'; expected = 1 }
                )
            } -Evidence @{
                registry = @(
                    @{ hive = 'HKLM'; path = 'A'; name = 'One'; value = 1 },
                    @{ hive = 'HKLM'; path = 'A'; name = 'Two'; value = 0 }
                )
            }
            $result.Status | Should -Be 'fail'
        }
    }

    It 'tests bit masks and inclusive ranges' {
        InModuleScope GrundschutzCheck {
            $mask = @{ method = 'registry'; hive = 'HKLM'; path = 'Lsa'; name = 'NTLMMinClientSec'; operator = 'bits_set'; expected = 537395200 }
            $ok = Invoke-GsEvaluation -Evaluation $mask -Evidence @{ registry = @(@{ hive = 'HKLM'; path = 'Lsa'; name = 'NTLMMinClientSec'; value = '537395200' }) }
            $ok.Status | Should -Be 'pass'
            $bad = Invoke-GsEvaluation -Evaluation $mask -Evidence @{ registry = @(@{ hive = 'HKLM'; path = 'Lsa'; name = 'NTLMMinClientSec'; value = 524288 }) }
            $bad.Status | Should -Be 'fail'

            $range = @{ method = 'registry'; hive = 'HKLM'; path = 'P'; name = 'InactivityTimeoutSecs'; operator = 'in_range'; expected = @(600, 900) }
            (Invoke-GsEvaluation -Evaluation $range -Evidence @{ registry = @(@{ hive = 'HKLM'; path = 'P'; name = 'InactivityTimeoutSecs'; value = 600 }) }).Status | Should -Be 'pass'
            (Invoke-GsEvaluation -Evaluation $range -Evidence @{ registry = @(@{ hive = 'HKLM'; path = 'P'; name = 'InactivityTimeoutSecs'; value = 0 }) }).Status | Should -Be 'fail'
        }
    }

    It 'reads services, Defender booleans, features, Secure Boot, and BitLocker' {
        InModuleScope GrundschutzCheck {
            $service = Invoke-GsEvaluation -Evaluation @{
                method = 'service'; name = 'DiagTrack'; property = 'start_type'; operator = 'equals'; expected = 'Disabled'
            } -Evidence @{ services = @(@{ name = 'DiagTrack'; start_type = 'Automatic'; status = 'Running' }) }
            $service.Status | Should -Be 'fail'

            $defender = Invoke-GsEvaluation -Evaluation @{
                method = 'defender'; property = 'DisableRealtimeMonitoring'; operator = 'equals'; expected = $false
            } -Evidence @{ defender = @{ DisableRealtimeMonitoring = 0 } }
            $defender.Status | Should -Be 'pass'

            $feature = Invoke-GsEvaluation -Evaluation @{
                method = 'feature'; name = 'MicrosoftWindowsPowerShellV2Root'; operator = 'one_of'; expected = @('Disabled', 'NotFound')
            } -Evidence @{ features = @() }
            $feature.Status | Should -Be 'pass'
            $feature.Actual | Should -Be 'NotFound'

            $boot = Invoke-GsEvaluation -Evaluation @{ method = 'secureboot'; expected = $true } -Evidence @{ secureboot = $true }
            $boot.Status | Should -Be 'pass'

            $volume = Invoke-GsEvaluation -Evaluation @{
                method = 'bitlocker'; volume_type = 'OperatingSystem'; property = 'protection_status'; operator = 'equals'; expected = 'On'
            } -Evidence @{ bitlocker = @(@{ volume_type = 'Data'; protection_status = 'On' }) }
            $volume.Status | Should -Be 'error'
        }
    }

    It 'returns error when a different German audit subcategory was collected' {
        InModuleScope GrundschutzCheck {
            $result = Invoke-GsEvaluation -Evaluation @{
                method = 'auditpol'; subcategory = 'Logon'; operator = 'equals'; expected = 'Success and Failure'
            } -Evidence @{ auditpol = @(@{ subcategory = 'Abmeldung'; setting = 'Erfolg und Fehler' }) }
            $result.Status | Should -Be 'error'
        }
    }

    It 'parses recorded English and German auditpol CSV to the same rows' {
        InModuleScope GrundschutzCheck -Parameters @{ RepoRoot = $script:RepoRoot } {
            param($RepoRoot)
            $utf8 = New-Object System.Text.UTF8Encoding $false
            $enText = [System.IO.File]::ReadAllText((Join-Path $RepoRoot 'tests/fixtures/auditpol-en.csv'), $utf8)
            $deText = [System.IO.File]::ReadAllText((Join-Path $RepoRoot 'tests/fixtures/auditpol-de.csv'), $utf8)
            $en = @(ConvertFrom-GsAuditpolCsv -Text $enText)
            $de = @(ConvertFrom-GsAuditpolCsv -Text $deText)
            $en.Count | Should -Be 8
            $de.Count | Should -Be 8
            for ($i = 0; $i -lt $en.Count; $i++) {
                $de[$i].subcategory | Should -Be $en[$i].subcategory
                $de[$i].subcategory_guid | Should -Be $en[$i].subcategory_guid
                $de[$i].setting | Should -Be $en[$i].setting
            }
            ($en | Where-Object { $_.subcategory -eq 'Logon' }).setting | Should -Be 'Success and Failure'
            ($en | Where-Object { $_.subcategory -eq 'Logon' }).subcategory_guid | Should -Be '{0cce9215-69ae-11d9-bed3-505054503030}'
            ($en | Where-Object { $_.subcategory -eq 'Credential Validation' }).subcategory_guid | Should -Be '{0cce923f-69ae-11d9-bed3-505054503030}'
            ($en | Where-Object { $_.subcategory -eq 'Account Lockout' }).setting | Should -Be 'No Auditing'
            ($en | Where-Object { $_.subcategory -eq 'User Account Management' }).setting | Should -Be 'Failure'
            ($de | Where-Object { $_.subcategory -eq 'Security Group Management' }).setting | Should -Be 'Success'
            ($de | Where-Object { $_.subcategory -eq 'Process Creation' }).setting | Should -Be 'Success and Failure'
            ($de | Where-Object { $_.subcategory -eq 'Special Logon' }).setting | Should -Be 'Success'
        }
    }

    It 'maps German display names when the GUID column is empty' {
        InModuleScope GrundschutzCheck -Parameters @{ RepoRoot = $script:RepoRoot } {
            param($RepoRoot)
            $utf8 = New-Object System.Text.UTF8Encoding $false
            $text = [System.IO.File]::ReadAllText((Join-Path $RepoRoot 'tests/fixtures/auditpol-de-fallback.csv'), $utf8)
            $rows = @(ConvertFrom-GsAuditpolCsv -Text $text)
            $rows.Count | Should -Be 8
            ($rows | Where-Object { $_.subcategory -eq 'Logon' }).subcategory_guid | Should -Be '{0cce9215-69ae-11d9-bed3-505054503030}'
            ($rows | Where-Object { $_.subcategory -eq 'Logon' }).setting | Should -Be 'Success and Failure'
            ($rows | Where-Object { $_.subcategory -eq 'Credential Validation' }).setting | Should -Be 'Success and Failure'
            ($rows | Where-Object { $_.subcategory -eq 'Account Lockout' }).setting | Should -Be 'No Auditing'
            ($rows | Where-Object { $_.subcategory -eq 'Logoff' }).setting | Should -Be 'Success'
        }
    }

    It 'queries an audit subcategory by GUID' {
        InModuleScope GrundschutzCheck {
            $argumentList = @(Get-GsAuditpolArgumentList -SubcategoryGuid '{0CCE9215-69AE-11D9-BED3-505054503030}')
            ($argumentList -join ' ') | Should -Be '/get /subcategory:{0cce9215-69ae-11d9-bed3-505054503030} /r'
        }
    }

    It 'keeps a German GUID query and falls back to German names when that query is missing' {
        InModuleScope GrundschutzCheck -Parameters @{ RepoRoot = $script:RepoRoot } {
            param($RepoRoot)
            $utf8 = New-Object System.Text.UTF8Encoding $false
            $deText = [System.IO.File]::ReadAllText((Join-Path $RepoRoot 'tests/fixtures/auditpol-de.csv'), $utf8)
            $fallback = [System.IO.File]::ReadAllText((Join-Path $RepoRoot 'tests/fixtures/auditpol-de-fallback.csv'), $utf8)
            $logon = '{0cce9215-69ae-11d9-bed3-505054503030}'
            $credential = '{0cce923f-69ae-11d9-bed3-505054503030}'
            $fromGuid = @(Merge-GsAuditpolQueries -SubcategoryGuids @($credential) -QueryTextByGuid @{ $credential = $deText } -FallbackText '')
            $fromGuid.Count | Should -Be 1
            $fromGuid[0].subcategory | Should -Be 'Credential Validation'
            $fromGuid[0].setting | Should -Be 'Success and Failure'

            $fromName = @(Merge-GsAuditpolQueries -SubcategoryGuids @($logon, $credential) -QueryTextByGuid @{} -FallbackText $fallback)
            ($fromName | Where-Object { $_.subcategory -eq 'Logon' }).setting | Should -Be 'Success and Failure'
            ($fromName | Where-Object { $_.subcategory -eq 'Credential Validation' }).setting | Should -Be 'Success and Failure'
            @($fromName | Where-Object { $_.subcategory -eq 'Logon' }).Count | Should -Be 1
        }
    }

    It 'passes Logon from the German display name or from the GUID alone' {
        InModuleScope GrundschutzCheck {
            $byName = Invoke-GsEvaluation -Evaluation @{
                method = 'auditpol'; subcategory = 'Logon'; operator = 'equals'; expected = 'Success and Failure'
            } -Evidence @{ auditpol = @(@{ subcategory = 'Anmelden'; setting = 'Erfolg und Fehler' }) }
            $byName.Status | Should -Be 'pass'

            $ue = [string]([char]0x00FC)
            $Ue = [string]([char]0x00DC)
            $alternate = ('{0}berpr{1}fung der Anmeldeinformationen' -f $Ue, $ue)
            $byAlias = Invoke-GsEvaluation -Evaluation @{
                method = 'auditpol'; subcategory = 'Credential Validation'; operator = 'equals'; expected = 'Success and Failure'
            } -Evidence @{ auditpol = @(@{ subcategory = $alternate; setting = 'Erfolg und Fehler' }) }
            $byAlias.Status | Should -Be 'pass'

            $byGuid = Invoke-GsEvaluation -Evaluation @{
                method = 'auditpol'
                subcategory = 'Logon'
                subcategory_guid = '{0CCE9215-69AE-11D9-BED3-505054503030}'
                operator = 'equals'
                expected = 'Success and Failure'
            } -Evidence @{
                auditpol = @(@{
                    subcategory = 'nicht-der-name'
                    subcategory_guid = '{0CCE9215-69AE-11D9-BED3-505054503030}'
                    setting = 'Erfolg und Fehler'
                })
            }
            $byGuid.Status | Should -Be 'pass'
        }
    }
}

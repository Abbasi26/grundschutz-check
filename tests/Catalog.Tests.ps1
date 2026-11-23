BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $script:RepoRoot 'GrundschutzCheck.psd1') -Force
}

Describe 'Windows 11 catalog' {
    BeforeAll {
        $script:VerifiedKompendium = @(
            'SYS.2.1.A1', 'SYS.2.1.A3', 'SYS.2.1.A6', 'SYS.2.1.A8', 'SYS.2.1.A15', 'SYS.2.1.A16',
            'SYS.2.1.A18', 'SYS.2.1.A28', 'SYS.2.1.A31', 'SYS.2.2.3.A4', 'SYS.2.2.3.A5', 'SYS.2.2.3.A6',
            'SYS.2.2.3.A12', 'SYS.2.2.3.A15', 'SYS.2.2.3.A16', 'SYS.2.2.3.A17', 'SYS.2.2.3.A18',
            'SYS.2.2.3.A19', 'SYS.2.2.3.A20', 'SYS.2.2.3.A22', 'SYS.2.2.3.A23', 'SYS.2.2.3.A24',
            'SYS.2.2.3.A25', 'SYS.3.1.A3'
        )
        $script:UnverifiedKompendium = @('DER.1.A5')
        $script:VerifiedGrundschutz = @(
            'KONF.2.4', 'KONF.2.4.2', 'KONF.2.9', 'KONF.3.2', 'KONF.3.8', 'KONF.4.1.1', 'KONF.4.3',
            'KONF.4.4', 'KONF.7.1', 'KONF.7.15', 'KONF.7.16', 'KONF.8.1.1', 'BER.3.10', 'BER.3.12',
            'BER.3.20', 'BER.6.2', 'DET.3.1.1', 'DET.3.1.2'
        )
        $script:UnverifiedGrundschutz = @('BER.6.4', 'BER.6.5')
    }

    It 'matches the published schema rules' {
        InModuleScope GrundschutzCheck {
            $catalog = Get-GsCatalog
            $errors = @(Test-GsCatalog -Catalog $catalog)
            ($errors -join "`n") | Should -Be ''
        }
    }

    It 'has at least 40 checks and keeps Windows 11 carry-over unverified' {
        InModuleScope GrundschutzCheck {
            $catalog = Get-GsCatalog
            $checks = @(ConvertTo-GsArray (Get-GsProperty $catalog 'checks'))
            $checks.Count | Should -BeGreaterOrEqual 40
            foreach ($check in $checks) {
                [string](Get-GsProperty $check 'windows11_carryover') | Should -Be 'unverified'
            }
        }
    }

    It 'cites only requirement ids read from the published catalogs' {
        InModuleScope GrundschutzCheck -Parameters @{
            VerifiedKompendium    = $script:VerifiedKompendium
            UnverifiedKompendium  = $script:UnverifiedKompendium
            VerifiedGrundschutz   = $script:VerifiedGrundschutz
            UnverifiedGrundschutz = $script:UnverifiedGrundschutz
        } {
            param($VerifiedKompendium, $UnverifiedKompendium, $VerifiedGrundschutz, $UnverifiedGrundschutz)
            $catalog = Get-GsCatalog
            foreach ($check in @(ConvertTo-GsArray (Get-GsProperty $catalog 'checks'))) {
                foreach ($ref in @(ConvertTo-GsArray (Get-GsProperty $check 'references'))) {
                    $framework = [string](Get-GsProperty $ref 'framework')
                    $mapping = [string](Get-GsProperty $ref 'mapping')
                    $requirementId = [string](Get-GsProperty $ref 'requirement_id')
                    if ($framework -eq 'it-grundschutz-kompendium') {
                        $allowed = $UnverifiedKompendium
                        if ($mapping -eq 'verified') { $allowed = $VerifiedKompendium }
                    }
                    elseif ($framework -eq 'grundschutz-plus-plus') {
                        $allowed = $UnverifiedGrundschutz
                        if ($mapping -eq 'verified') { $allowed = $VerifiedGrundschutz }
                    }
                    elseif ($framework -eq 'disa-stig') {
                        $requirementId | Should -Match '^WN11-[A-Z0-9]+-[0-9]{6}$'
                        [string](Get-GsProperty $ref 'group_id') | Should -Match '^V-[0-9]+$'
                        [string](Get-GsProperty $ref 'rule_id') | Should -Match '^SV-[0-9]+r[0-9]+_rule$'
                        $mapping | Should -Be 'verified'
                        continue
                    }
                    else {
                        throw "Unexpected framework $framework"
                    }
                    $allowed -contains $requirementId | Should -BeTrue
                }
            }
        }
    }

    It 'matches the checked DISA STIG V2R11 subset exactly' {
        InModuleScope GrundschutzCheck {
            $expected = @(
                'GS-W11-001|WN11-AC-000020|V-253300|SV-253300r1256653_rule'
                'GS-W11-006|WN11-SO-000010|V-253433|SV-253433r958504_rule'
                'GS-W11-023|WN11-CC-000020|V-253353|SV-253353r1268251_rule'
                'GS-W11-023|WN11-CC-000025|V-253354|SV-253354r1268251_rule'
                'GS-W11-024|WN11-SO-000100|V-253449|SV-253449r958908_rule'
                'GS-W11-025|WN11-SO-000120|V-253451|SV-253451r958908_rule'
                'GS-W11-041|WN11-CC-000326|V-253414|SV-253414r958422_rule'
                'GS-W11-060|WN11-AU-000070|V-253316|SV-253316r991581_rule'
                'GS-W11-060|WN11-AU-000075|V-253317|SV-253317r991581_rule'
                'GS-W11-061|WN11-AU-000005|V-253306|SV-253306r991570_rule'
                'GS-W11-061|WN11-AU-000010|V-253307|SV-253307r991570_rule'
            )
            $catalog = Get-GsCatalog
            $found = @(
                foreach ($check in @(ConvertTo-GsArray (Get-GsProperty $catalog 'checks'))) {
                    $checkId = [string](Get-GsProperty $check 'id')
                    foreach ($ref in @(ConvertTo-GsArray (Get-GsProperty $check 'references'))) {
                        if ([string](Get-GsProperty $ref 'framework') -ne 'disa-stig') { continue }
                        $requirementId = [string](Get-GsProperty $ref 'requirement_id')
                        $requirementId | Should -Match '^WN11-[A-Z0-9]+-[0-9]{6}$'
                        [string](Get-GsProperty $ref 'mapping') | Should -Be 'verified'
                        [string](Get-GsProperty $ref 'source_id') | Should -Be 'disa-stig-windows-11-v2r11'
                        '{0}|{1}|{2}|{3}' -f $checkId, $requirementId, (Get-GsProperty $ref 'group_id'), (Get-GsProperty $ref 'rule_id')
                    }
                }
            )
            (Compare-Object ($expected | Sort-Object) ($found | Sort-Object)) | Should -BeNullOrEmpty
        }
    }

    It 'queries the audit checks by MS-GPAC subcategory GUID' {
        InModuleScope GrundschutzCheck {
            $catalog = Get-GsCatalog
            $checks = @(ConvertTo-GsArray (Get-GsProperty $catalog 'checks'))
            $logon = @($checks | Where-Object { $_.id -eq 'GS-W11-060' })[0]
            $credential = @($checks | Where-Object { $_.id -eq 'GS-W11-061' })[0]
            [string]$logon.evaluation.subcategory_guid | Should -Be '{0CCE9215-69AE-11D9-BED3-505054503030}'
            [string]$credential.evaluation.subcategory_guid | Should -Be '{0CCE923F-69AE-11D9-BED3-505054503030}'
            $reads = Get-GsRequestedReads -Catalog $catalog
            @($reads.AuditGuids) | Should -Contain '{0cce9215-69ae-11d9-bed3-505054503030}'
            @($reads.AuditGuids) | Should -Contain '{0cce923f-69ae-11d9-bed3-505054503030}'
        }
    }

    It 'records the password-age disagreement as unverified' {
        InModuleScope GrundschutzCheck {
            $catalog = Get-GsCatalog
            $check = @((ConvertTo-GsArray (Get-GsProperty $catalog 'checks')) | Where-Object { $_.id -eq 'GS-W11-004' })[0]
            [string]$check.conflict_note | Should -Match 'BER\.6\.5'
            $ref = @($check.references | Where-Object { $_.requirement_id -eq 'BER.6.5' })[0]
            [string]$ref.mapping | Should -Be 'unverified'
            [string]$check.severity | Should -Be 'low'
        }
    }

    It 'rejects a STIG reference without a rule id' {
        InModuleScope GrundschutzCheck {
            $catalog = Get-GsCatalog
            $check = @((ConvertTo-GsArray (Get-GsProperty $catalog 'checks')) | Where-Object { $_.id -eq 'GS-W11-024' })[0]
            $ref = @($check.references | Where-Object { $_.framework -eq 'disa-stig' })[0]
            $ref.requirement_id | Should -Be 'WN11-SO-000100'
            $ref.PSObject.Properties.Remove('rule_id')
            $errors = @(Test-GsCatalog -Catalog $catalog)
            ($errors -join "`n") | Should -Match 'missing an SV- rule id'
        }
    }

    It 'rejects a check whose module.id is not in modules' {
        InModuleScope GrundschutzCheck {
            $catalog = Get-GsCatalog
            $check = @((ConvertTo-GsArray (Get-GsProperty $catalog 'checks')) | Where-Object { $_.id -eq 'GS-W11-001' })[0]
            $check.module.id = 'SYS.9.9'
            $errors = @(Test-GsCatalog -Catalog $catalog)
            ($errors -join "`n") | Should -Match "GS-W11-001 uses unknown module\.id 'SYS\.9\.9'\."
        }
    }

    It 'rejects a reference whose source_id is not in catalog.sources' {
        InModuleScope GrundschutzCheck {
            $catalog = Get-GsCatalog
            $check = @((ConvertTo-GsArray (Get-GsProperty $catalog 'checks')) | Where-Object { $_.id -eq 'GS-W11-001' })[0]
            $check.references[0].source_id = 'no-such-source'
            $errors = @(Test-GsCatalog -Catalog $catalog)
            ($errors -join "`n") | Should -Match "GS-W11-001 reference uses unknown source_id 'no-such-source'\."
        }
    }

    It 'rejects a registry evaluation on a hive other than HKLM' {
        InModuleScope GrundschutzCheck {
            $catalog = Get-GsCatalog
            $check = @((ConvertTo-GsArray (Get-GsProperty $catalog 'checks')) | Where-Object { $_.id -eq 'GS-W11-007' })[0]
            $check.evaluation.hive = 'HKCU'
            $errors = @(Test-GsCatalog -Catalog $catalog)
            ($errors -join "`n") | Should -Match "GS-W11-007 registry hive 'HKCU' is not HKLM\."
        }
    }

    It 'rejects a registry evaluation nested in all_of on a hive other than HKLM' {
        InModuleScope GrundschutzCheck {
            $catalog = Get-GsCatalog
            $check = @((ConvertTo-GsArray (Get-GsProperty $catalog 'checks')) | Where-Object { $_.id -eq 'GS-W11-022' })[0]
            $check.evaluation.evaluations[0].hive = 'HKCU'
            $errors = @(Test-GsCatalog -Catalog $catalog)
            ($errors -join "`n") | Should -Match "GS-W11-022 registry hive 'HKCU' is not HKLM\."
        }
    }
}

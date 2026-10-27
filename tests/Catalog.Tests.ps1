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
                    else {
                        throw "Unexpected framework $framework"
                    }
                    $allowed -contains $requirementId | Should -BeTrue
                }
            }
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
}

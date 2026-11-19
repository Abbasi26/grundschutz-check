BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $script:RepoRoot 'GrundschutzCheck.psd1') -Force
    $script:Fixture = Join-Path $PSScriptRoot 'fixtures/grundschutzplusplus-mini.json'
}

Describe 'Import-GsGrundschutzPlusPlus' {
    It 'reads metadata and flattens nested groups and controls' {
        $library = Import-GsGrundschutzPlusPlus -Path $script:Fixture
        $library.version | Should -Be 'fixture-2026-11-01'
        $library.oscal_version | Should -Be '1.1.3'
        $library.last_modified | Should -Be '2026-11-01T00:00:00Z'
        @($library.controls).Count | Should -Be 3
        @($library.duplicates).Count | Should -Be 0

        $ber = $library.index['BER.6.2']
        $ber.practice | Should -Be 'BER'
        $ber.group | Should -Be 'BER.6'
        $ber.sec_level | Should -Be 'normal-SdT'
        $ber.effort_level | Should -Be '3'
        $ber.modal_verb | Should -Be 'MUSS'

        $nested = $library.index['KONF.2.4.2']
        $nested.parent | Should -Be 'KONF.2.4'
        $nested.practice | Should -Be 'KONF'
        $nested.modal_verb | Should -BeNullOrEmpty
    }

    It 'does not copy prose into the rows' {
        $library = Import-GsGrundschutzPlusPlus -Path $script:Fixture
        $names = @($library.controls[0].PSObject.Properties.Name)
        $names | Should -Not -Contain 'prose'
        $names | Should -Not -Contain 'parts'
    }

    It 'normalizes ISO timestamps to UTC on every PowerShell version' {
        InModuleScope GrundschutzCheck {
            ConvertTo-GsOscalText '2026-10-29T08:03:12.736989+00:00' | Should -Be '2026-10-29T08:03:12.736989Z'
            ConvertTo-GsOscalText '2026-10-29T10:03:12+02:00' | Should -Be '2026-10-29T08:03:12Z'
            ConvertTo-GsOscalText 'fixture-2026-11-01' | Should -Be 'fixture-2026-11-01'
            ConvertTo-GsOscalText $null | Should -Be ''
        }
    }

    It 'rejects files that are not OSCAL catalogs' {
        $dir = Join-Path $script:RepoRoot '.tmp'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $notCatalog = Join-Path $dir 'not-oscal.json'
        Set-Content -LiteralPath $notCatalog -Value '{"schema_version":"0.1.0","checks":[]}' -Encoding UTF8
        { Import-GsGrundschutzPlusPlus -Path $notCatalog } | Should -Throw '*catalog*'

        $noVersion = Join-Path $dir 'no-version.json'
        Set-Content -LiteralPath $noVersion -Value '{"catalog":{"metadata":{"title":"x"},"groups":[]}}' -Encoding UTF8
        { Import-GsGrundschutzPlusPlus -Path $noVersion } | Should -Throw '*oscal-version*'

        $empty = Join-Path $dir 'empty.json'
        Set-Content -LiteralPath $empty -Value '{"catalog":{"metadata":{"oscal-version":"1.1.3"},"groups":[]}}' -Encoding UTF8
        { Import-GsGrundschutzPlusPlus -Path $empty } | Should -Throw '*no controls*'

        { Import-GsGrundschutzPlusPlus -Path (Join-Path $dir 'does-not-exist.json') } | Should -Throw '*not found*'
    }
}

Describe 'Test-GsGrundschutzPlusPlusReference' {
    BeforeAll {
        $script:Library = Import-GsGrundschutzPlusPlus -Path $script:Fixture
        $script:Catalog = [pscustomobject]@{
            catalog = [pscustomobject]@{
                sources = @([pscustomobject]@{ id = 'grundschutz-plus-plus-2026-09-24'; version = 'older' })
            }
            checks  = @(
                [pscustomobject]@{
                    id         = 'GS-T-001'
                    references = @(
                        [pscustomobject]@{ framework = 'it-grundschutz-kompendium'; requirement_id = 'SYS.2.1.A1'; title = 'x'; mapping = 'verified' },
                        [pscustomobject]@{ framework = 'grundschutz-plus-plus'; requirement_id = 'BER.6.2'; title = 'Blockieren von Passwort Recycling'; mapping = 'verified' }
                    )
                },
                [pscustomobject]@{
                    id         = 'GS-T-002'
                    references = @(
                        [pscustomobject]@{ framework = 'grundschutz-plus-plus'; requirement_id = 'KONF.2.4'; title = 'Fixture old title'; mapping = 'verified' },
                        [pscustomobject]@{ framework = 'grundschutz-plus-plus'; requirement_id = 'DET.3.1.2'; title = 'Fixture missing'; mapping = 'unverified' }
                    )
                }
            )
        }
    }

    It 'classifies each Grundschutz++ reference and ignores other frameworks' {
        $result = Test-GsGrundschutzPlusPlusReference -Catalog $script:Catalog -Library $script:Library
        $result.total | Should -Be 3
        $result.ok | Should -Be 1
        $result.title_changed | Should -Be 1
        $result.missing | Should -Be 1
        $byId = @{}
        foreach ($row in $result.references) { $byId[$row.requirement_id] = $row }
        $byId['BER.6.2'].status | Should -Be 'ok'
        $byId['KONF.2.4'].status | Should -Be 'title_changed'
        $byId['KONF.2.4'].current_title | Should -Be 'Fixture title that differs on purpose'
        $byId['DET.3.1.2'].status | Should -Be 'missing'
        $byId['DET.3.1.2'].check_id | Should -Be 'GS-T-002'
    }

    It 'reports when the catalog cites another Grundschutz++ version' {
        $result = Test-GsGrundschutzPlusPlusReference -Catalog $script:Catalog -Library $script:Library
        $result.catalog_source_version | Should -Be 'older'
        $result.library_version | Should -Be 'fixture-2026-11-01'
        $result.version_differs | Should -BeTrue
    }

    It 'runs against the shipped Windows 11 catalog' {
        $result = Test-GsGrundschutzPlusPlusReference -Catalog (Get-GsCatalog) -Library $script:Library
        $result.total | Should -BeGreaterThan 0
        ($result.ok + $result.title_changed + $result.missing) | Should -Be $result.total
    }
}

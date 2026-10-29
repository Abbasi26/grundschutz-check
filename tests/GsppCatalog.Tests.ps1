BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $script:RepoRoot 'GrundschutzCheck.psd1') -Force
    $script:FixturePath = Join-Path $script:RepoRoot 'tests/fixtures/gspp/catalog.json'
    $script:CheckCatalogPath = Join-Path $script:RepoRoot 'catalog/windows11-client.json'
}

Describe 'Grundschutz++ OSCAL catalog' {
    BeforeAll {
        $script:TempDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('gspp-pester-' + [guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path $script:TempDirectory | Out-Null
        $script:Catalog = Import-GsppCatalog -Path $script:FixturePath
    }

    AfterAll {
        if (Test-Path -LiteralPath $script:TempDirectory) {
            Remove-Item -LiteralPath $script:TempDirectory -Recurse -Force
        }
    }

    It 'imports the fixture and walks nested controls' {
        $script:Catalog.Title | Should -Be 'Anwenderkatalog Grundschutz++'
        $script:Catalog.OscalVersion | Should -Be '1.1.3'
        $script:Catalog.ControlCount | Should -BeGreaterThan 20
        @($script:Catalog.Practices).Count | Should -Be 3
        $nested = @($script:Catalog.Controls | Where-Object { $_.Id -eq 'KONF.2.4.2' })[0]
        $nested.GroupId | Should -Be 'KONF.2'
        $nested.Practice | Should -Be 'KONF'
    }

    It 'expands statement parameters' {
        @($script:Catalog.Controls | Where-Object { $_.Statement -match '\{\{' }).Count | Should -Be 0
        @($script:Catalog.Controls | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Statement) }).Count | Should -BeGreaterThan 0
    }

    It 'rejects a SHA-256 mismatch' {
        { Import-GsppCatalog -Path $script:FixturePath -ExpectedSha256 ('0' * 64) } | Should -Throw '*SHA-256 mismatch*'
    }

    It 'rejects a non-OSCAL JSON document' {
        $path = Join-Path $script:TempDirectory 'not-oscal.json'
        [System.IO.File]::WriteAllText($path, '{"catalog":{"metadata":{},"groups":[]}}', (New-Object System.Text.UTF8Encoding $false))
        { Import-GsppCatalog -Path $path } | Should -Throw '*not an OSCAL catalog*'
    }

    It 'finds every current Grundschutz++ reference' {
        $references = @(Test-GsppReference -Catalog $script:Catalog -CheckCatalogPath $script:CheckCatalogPath)
        @($references | Where-Object { -not $_.Found }).Count | Should -Be 0
        @($references | Where-Object { -not $_.TitleMatches }).Count | Should -Be 0
    }

    It 'reports a missing reference' {
        $path = Join-Path $script:TempDirectory 'missing-reference.json'
        [System.IO.File]::WriteAllText($path, '{"checks":[{"id":"TEST-001","references":[{"framework":"grundschutz-plus-plus","requirement_id":"KONF.99.99","title":"Missing"}]}]}', (New-Object System.Text.UTF8Encoding $false))
        $reference = @(Test-GsppReference -Catalog $script:Catalog -CheckCatalogPath $path)[0]
        $reference.Id | Should -Be 'KONF.99.99'
        $reference.Found | Should -BeFalse
        $reference.TitleMatches | Should -BeFalse
    }

    It 'exports CSV and JSON control indexes' {
        $csvPath = Join-Path $script:TempDirectory 'controls.csv'
        $jsonPath = Join-Path $script:TempDirectory 'controls.json'
        Export-GsppControlIndex -Catalog $script:Catalog -Path $csvPath
        Export-GsppControlIndex -Catalog $script:Catalog -Path $jsonPath
        (Test-Path -LiteralPath $csvPath) | Should -BeTrue
        (Test-Path -LiteralPath $jsonPath) | Should -BeTrue
        ([System.IO.File]::ReadAllText($csvPath)).Contains('KONF.2.4') | Should -BeTrue
        @(([System.IO.File]::ReadAllText($jsonPath) | ConvertFrom-Json)).Count | Should -Be $script:Catalog.ControlCount
    }

    It 'imports the full catalog when GSPP_FULL_CATALOG is available' {
        $fullPath = [string]$env:GSPP_FULL_CATALOG
        if ([string]::IsNullOrWhiteSpace($fullPath) -or -not (Test-Path -LiteralPath $fullPath)) {
            Set-ItResult -Skipped -Because 'GSPP_FULL_CATALOG is not available'
            return
        }
        $fullCatalog = Import-GsppCatalog -Path $fullPath
        $fullCatalog.ControlCount | Should -BeGreaterThan 600
        $references = @(Test-GsppReference -Catalog $fullCatalog -CheckCatalogPath $script:CheckCatalogPath)
        @($references | Where-Object { -not $_.Found }).Count | Should -Be 0
    }
}

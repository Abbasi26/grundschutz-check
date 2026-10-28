@{
    RootModule        = 'GrundschutzCheck.psm1'
    ModuleVersion     = '0.2.0'
    GUID              = 'f0c96ef7-6444-4d5a-97dc-fcd42672da59'
    Author            = 'Wasaf Abbasi'
    CompanyName       = 'Wasaf Abbasi'
    Copyright         = '(c) 2026 Wasaf Abbasi'
    Description       = 'Read-only Windows 11 client hardening checks against BSI IT-Grundschutz and Grundschutz++, with an evidence report.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Invoke-GrundschutzCheck', 'Get-GsCatalog')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags = @('BSI', 'Grundschutz', 'Windows', 'hardening', 'audit')
        }
    }
}

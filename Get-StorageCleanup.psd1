@{
    RootModule        = 'Get-StorageCleanup.psm1'
    ModuleVersion     = '2.0.0'
    GUID              = '6b1f6c0e-3a52-4c1e-9d0b-5a7e2f4c9b11'
    Author            = 'Dave G (NOC Engineer)'
    CompanyName       = 'Systems Engineering'
    Description       = 'Menu-driven storage analysis and cleanup. Semantic versioning (MAJOR.MINOR.PATCH).'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Get-StorageCleanup','Invoke-ServerCleanup')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}

@{
    RootModule        = 'Get-StorageCleanup.psm1'
    ModuleVersion     = '1.1.0'
    GUID              = '6b1f6c0e-3a52-4c1e-9d0b-5a7e2f4c9b11'
    Author            = 'NOC Core'
    CompanyName       = 'Systems Engineering'
    Description       = 'Server disk cleanup and large folder/file analysis.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Get-StorageCleanup','Start-ServerCleanup','Get-LargestFolders','Find-LargeFiles','Get-StorageCleanupVersion')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}

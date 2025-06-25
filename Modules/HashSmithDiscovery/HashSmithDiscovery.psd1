@{
    RootModule = 'HashSmithDiscovery.psm1'
    ModuleVersion = '4.1.0'
    GUID = 'c3d4e5f6-a7b8-9012-cdef-345678901234'
    Author = 'HashSmith Production Team'
    CompanyName = 'HashSmith'
    Copyright = '(c) 2025 HashSmith. All rights reserved.'
    Description = 'File discovery engine for HashSmith file integrity verification system'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Get-HashSmithAllFiles',
        'Test-HashSmithFileDiscoveryCompleteness'
    )
    VariablesToExport = @()
    CmdletsToExport = @()
    AliasesToExport = @()
}

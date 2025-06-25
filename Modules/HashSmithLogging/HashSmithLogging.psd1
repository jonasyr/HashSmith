@{
    RootModule = 'HashSmithLogging.psm1'
    ModuleVersion = '4.1.0'
    GUID = 'e5f6a7b8-c9d0-1234-efab-567890123456'
    Author = 'HashSmith Production Team'
    CompanyName = 'HashSmith'
    Copyright = '(c) 2025 HashSmith. All rights reserved.'
    Description = 'Enhanced log management for HashSmith file integrity verification system'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Initialize-HashSmithLogFile',
        'Write-HashSmithHashEntry',
        'Write-HashSmithLogEntryAtomic',
        'Clear-HashSmithLogBatch',
        'Get-HashSmithExistingEntries'
    )
    VariablesToExport = @()
    CmdletsToExport = @()
    AliasesToExport = @()
}

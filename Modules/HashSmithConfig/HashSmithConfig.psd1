@{
    RootModule = 'HashSmithConfig.psm1'
    ModuleVersion = '4.1.0'
    GUID = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author = 'HashSmith Production Team'
    CompanyName = 'HashSmith'
    Copyright = '(c) 2025 HashSmith. All rights reserved.'
    Description = 'Configuration and global variables management for HashSmith file integrity verification system'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Get-HashSmithConfig',
        'Get-HashSmithStatistics',
        'Get-HashSmithCircuitBreaker',
        'Get-HashSmithExitCode',
        'Set-HashSmithExitCode',
        'Get-HashSmithLogBatch',
        'Get-HashSmithNetworkConnections',
        'Get-HashSmithStructuredLogs',
        'Add-HashSmithStructuredLog',
        'Initialize-HashSmithConfig',
        'Reset-HashSmithStatistics'
    )
    VariablesToExport = @(
        'Config',
        'Statistics',
        'CircuitBreaker',
        'ExitCode',
        'LogBatch',
        'NetworkConnections',
        'StructuredLogs'
    )
    CmdletsToExport = @()
    AliasesToExport = @()
}

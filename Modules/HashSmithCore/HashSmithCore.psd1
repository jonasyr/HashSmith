@{
    RootModule = 'HashSmithCore.psm1'
    ModuleVersion = '4.1.0'
    GUID = 'b2c3d4e5-f6a7-8901-bcde-f23456789012'
    Author = 'HashSmith Production Team'
    CompanyName = 'HashSmith'
    Copyright = '(c) 2025 HashSmith. All rights reserved.'
    Description = 'Core utilities and helper functions for HashSmith file integrity verification system'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Write-HashSmithLog',
        'Test-HashSmithNetworkPath',
        'Update-HashSmithCircuitBreaker',
        'Test-HashSmithCircuitBreaker',
        'Get-HashSmithNormalizedPath',
        'Test-HashSmithFileAccessible',
        'Test-HashSmithSymbolicLink',
        'Get-HashSmithFileIntegritySnapshot',
        'Test-HashSmithFileIntegrityMatch'
    )
    VariablesToExport = @()
    CmdletsToExport = @()
    AliasesToExport = @()
}

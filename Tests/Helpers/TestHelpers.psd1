@{
    RootModule = 'TestHelpers.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'f1e2d3c4-b5a6-7890-1234-567890abcdef'
    Author = 'HashSmith Test Team'
    CompanyName = 'HashSmith Testing Framework'
    Copyright = '(c) 2025 HashSmith Test Suite. All rights reserved.'
    Description = 'Test helper functions and utilities for HashSmith Pester test suite'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Initialize-TestData',
        'New-MockFileStructure',
        'Get-ExpectedTestHash',
        'New-TestConfiguration',
        'Test-HashFormat',
        'Measure-TestExecution',
        'New-TestDirectory',
        'Test-LogFileFormat',
        'Invoke-MockFileSystemError',
        'Compare-TestHashtables',
        'Invoke-TestCleanup'
    )
    VariablesToExport = @()
    CmdletsToExport = @()
    AliasesToExport = @()
    RequiredModules = @()
    PrivateData = @{
        PSData = @{
            Tags = @('Testing', 'Pester', 'HashSmith', 'FileIntegrity')
            ProjectUri = 'https://github.com/hashsmith/hashsmith'
            ReleaseNotes = 'Initial release of HashSmith test helper functions'
        }
    }
}
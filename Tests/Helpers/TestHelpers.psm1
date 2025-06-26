<#
.SYNOPSIS
    HashSmith Test Helpers Module

.DESCRIPTION
    PowerShell module containing test helper functions and utilities for the HashSmith
    file integrity verification system test suite.

.NOTES
    Version: 1.0.0
    This module should be imported by the main test suite
#>

# Dot-source the helper functions
$helpersScript = Join-Path $PSScriptRoot "TestHelpers.ps1"
if (Test-Path $helpersScript) {
    . $helpersScript
} else {
    throw "TestHelpers.ps1 not found at: $helpersScript"
}

# Module-level initialization
Write-Verbose "HashSmith Test Helpers module loaded"

# Set up module-level variables
$Script:TestModuleInfo = @{
    Name = "HashSmithTestHelpers"
    Version = "1.0.0"
    LoadTime = Get-Date
    Functions = @(
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
}

<#
.SYNOPSIS
    Gets information about the test helpers module
#>
function Get-TestHelpersInfo {
    [CmdletBinding()]
    param()
    
    return $Script:TestModuleInfo.Clone()
}

<#
.SYNOPSIS
    Validates that all test helper functions are available
#>
function Test-TestHelpersAvailability {
    [CmdletBinding()]
    param()
    
    $missingFunctions = @()
    
    foreach ($functionName in $Script:TestModuleInfo.Functions) {
        if (-not (Get-Command $functionName -ErrorAction SilentlyContinue)) {
            $missingFunctions += $functionName
        }
    }
    
    if ($missingFunctions.Count -gt 0) {
        throw "Missing test helper functions: $($missingFunctions -join ', ')"
    }
    
    Write-Verbose "All test helper functions are available"
    return $true
}

<#
.SYNOPSIS
    Creates a comprehensive test environment
#>
function New-TestEnvironment {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$BasePath,
        
        [Parameter()]
        [switch]$IncludeComplexData,
        
        [Parameter()]
        [hashtable]$CustomConfiguration = @{}
    )
    
    # Cross-platform temp directory handling
    if (-not $BasePath) {
        $BasePath = if ($env:TEMP) { $env:TEMP } elseif ($env:TMPDIR) { $env:TMPDIR } else { '/tmp' }
    }
    
    # Create unique test environment
    $testEnvId = "HashSmithTest_$(Get-Date -Format 'yyyyMMdd_HHmmss')_$(Get-Random -Maximum 9999)"
    $testEnvPath = Join-Path $BasePath $testEnvId
    
    Write-Verbose "Creating test environment: $testEnvPath"
    
    # Create directory structure
    New-Item -Path $testEnvPath -ItemType Directory -Force | Out-Null
    $dataPath = Join-Path $testEnvPath "Data"
    $logsPath = Join-Path $testEnvPath "Logs"
    $tempPath = Join-Path $testEnvPath "Temp"
    
    @($dataPath, $logsPath, $tempPath) | ForEach-Object {
        New-Item -Path $_ -ItemType Directory -Force | Out-Null
    }
    
    # Initialize test data
    Initialize-TestData -SampleDataPath $dataPath
    
    # Create complex data if requested
    if ($IncludeComplexData) {
        $complexStructure = @{
            "level1/file1.txt" = "Level 1 content"
            "level1/level2/file2.txt" = "Level 2 content"
            "level1/level2/level3/file3.txt" = "Level 3 content"
            "level1/level2/level3/level4/file4.txt" = "Level 4 content"
            "parallel1/data1.bin" = [byte[]](1..1000)
            "parallel2/data2.bin" = [byte[]](1001..2000)
            "unicode/файл.txt" = "Unicode filename content"
            "spaces in names/file with spaces.txt" = "Spaces in names content"
        }
        
        New-MockFileStructure -BasePath $dataPath -Structure $complexStructure
    }
    
    # Create test configuration
    $testConfig = New-TestConfiguration -Overrides $CustomConfiguration
    $testConfig.TestEnvironmentPath = $testEnvPath
    $testConfig.DataPath = $dataPath
    $testConfig.LogsPath = $logsPath
    $testConfig.TempPath = $tempPath
    
    # Register for cleanup
    if (-not (Get-Variable -Name "TestEnvironments" -Scope Global -ErrorAction SilentlyContinue)) {
        $Global:TestEnvironments = @()
    }
    $Global:TestEnvironments += $testEnvPath
    
    return @{
        Path = $testEnvPath
        DataPath = $dataPath
        LogsPath = $logsPath
        TempPath = $tempPath
        Configuration = $testConfig
        Id = $testEnvId
    }
}

<#
.SYNOPSIS
    Removes test environment and cleans up resources
#>
function Remove-TestEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$EnvironmentPath
    )
    
    if (Test-Path $EnvironmentPath) {
        try {
            Remove-Item $EnvironmentPath -Recurse -Force -ErrorAction Stop
            Write-Verbose "Removed test environment: $EnvironmentPath"
            
            # Remove from global tracking
            if ($Global:TestEnvironments) {
                $Global:TestEnvironments = $Global:TestEnvironments | Where-Object { $_ -ne $EnvironmentPath }
            }
        } catch {
            Write-Warning "Failed to remove test environment: $EnvironmentPath - $($_.Exception.Message)"
        }
    }
}

<#
.SYNOPSIS
    Creates mock HashSmith statistics for testing
#>
function New-MockHashSmithStatistics {
    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$FilesDiscovered = 100,
        
        [Parameter()]
        [int]$FilesProcessed = 95,
        
        [Parameter()]
        [int]$FilesError = 5,
        
        [Parameter()]
        [long]$BytesProcessed = 1048576,
        
        [Parameter()]
        [datetime]$StartTime = (Get-Date).AddMinutes(-10)
    )
    
    return @{
        FilesDiscovered = $FilesDiscovered
        FilesProcessed = $FilesProcessed
        FilesSkipped = 0
        FilesError = $FilesError
        FilesSymlinks = 2
        FilesRaceCondition = 1
        BytesProcessed = $BytesProcessed
        NetworkPaths = 0
        LongPaths = 3
        RetriableErrors = 3
        NonRetriableErrors = 2
        StartTime = $StartTime
        DiscoveryErrors = @()
        ProcessingErrors = @()
        SystemLoad = @{
            CPU = 45
            Memory = 2048
            DiskIO = 15
        }
    }
}

<#
.SYNOPSIS
    Creates mock discovery results for testing
#>
function New-MockDiscoveryResult {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.IO.FileInfo[]]$Files = @(),
        
        [Parameter()]
        [hashtable]$Statistics = @{}
    )
    
    if ($Files.Count -eq 0) {
        # Create mock files
        $Files = @(
            [System.IO.FileInfo]::new("C:\Test\File1.txt")
            [System.IO.FileInfo]::new("C:\Test\File2.bin")
            [System.IO.FileInfo]::new("C:\Test\SubDir\File3.txt")
        )
    }
    
    if ($Statistics.Count -eq 0) {
        $Statistics = @{
            TotalFound = $Files.Count
            TotalSkipped = 0
            TotalErrors = 0
            TotalSymlinks = 0
            DiscoveryTime = 2.5
            DirectoriesProcessed = 2
            FilesPerSecond = [Math]::Round($Files.Count / 2.5, 1)
        }
    }
    
    return @{
        Files = $Files
        Errors = @()
        Statistics = $Statistics
    }
}

<#
.SYNOPSIS
    Asserts that a hash result has the expected structure
#>
function Assert-HashResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Result,
        
        [Parameter()]
        [bool]$ExpectedSuccess = $true,
        
        [Parameter()]
        [string]$ExpectedAlgorithm = 'MD5'
    )
    
    # Check required properties
    $requiredProperties = @('Success', 'Hash', 'Size', 'Error', 'Attempts', 'Duration')
    foreach ($property in $requiredProperties) {
        if (-not $Result.ContainsKey($property)) {
            throw "Hash result missing required property: $property"
        }
    }
    
    # Validate success state
    if ($Result.Success -ne $ExpectedSuccess) {
        throw "Expected Success=$ExpectedSuccess, got Success=$($Result.Success)"
    }
    
    # Validate hash format if successful
    if ($ExpectedSuccess -and $Result.Hash) {
        if (-not (Test-HashFormat -Hash $Result.Hash -Algorithm $ExpectedAlgorithm)) {
            throw "Invalid hash format for algorithm $ExpectedAlgorithm`: $($Result.Hash)"
        }
    }
    
    # Validate error information if failed
    if (-not $ExpectedSuccess) {
        if ([string]::IsNullOrEmpty($Result.Error)) {
            throw "Failed result should have error message"
        }
        if (-not $Result.ContainsKey('ErrorCategory') -or [string]::IsNullOrEmpty($Result.ErrorCategory)) {
            throw "Failed result should have error category"
        }
    }
    
    Write-Verbose "Hash result validation passed"
}

<#
.SYNOPSIS
    Module cleanup when removed
#>
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    # Clean up any remaining test environments
    if ($Global:TestEnvironments) {
        foreach ($envPath in $Global:TestEnvironments) {
            Remove-TestEnvironment -EnvironmentPath $envPath
        }
    }
    
    # Invoke general test cleanup
    Invoke-TestCleanup
    
    Write-Verbose "HashSmith Test Helpers module cleanup completed"
}

# Validate module load
try {
    Test-TestHelpersAvailability
    Write-Verbose "HashSmith Test Helpers module loaded successfully with $($Script:TestModuleInfo.Functions.Count) functions"
} catch {
    Write-Error "Failed to validate test helpers module: $($_.Exception.Message)"
    throw
}

# Export additional functions specific to this module
Export-ModuleMember -Function @(
    'Get-TestHelpersInfo',
    'Test-TestHelpersAvailability', 
    'New-TestEnvironment',
    'Remove-TestEnvironment',
    'New-MockHashSmithStatistics',
    'New-MockDiscoveryResult',
    'Assert-HashResult'
)
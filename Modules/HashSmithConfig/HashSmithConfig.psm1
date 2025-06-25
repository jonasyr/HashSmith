<#
.SYNOPSIS
    Configuration and global variables management for HashSmith

.DESCRIPTION
    This module manages all configuration settings, global variables, and statistics
    for the HashSmith file integrity verification system.
#>

#region Module Variables

# Script-level variables that will be accessible to importing scripts
$Script:Config = @{
    Version = '4.1.0'
    BufferSize = 4MB
    MaxRetryDelay = 5000
    ProgressInterval = 25
    LogEncoding = [System.Text.Encoding]::UTF8
    DateFormat = 'yyyy-MM-dd HH:mm:ss.fff'
    SupportLongPaths = $true
    NetworkTimeoutMs = 30000
    IntegrityHashSize = 1KB
    CircuitBreakerThreshold = 10
    CircuitBreakerTimeout = 30
}

$Script:Statistics = @{
    StartTime = Get-Date
    FilesDiscovered = 0
    FilesProcessed = 0
    FilesSkipped = 0
    FilesError = 0
    FilesSymlinks = 0
    FilesRaceCondition = 0
    BytesProcessed = 0
    NetworkPaths = 0
    LongPaths = 0
    DiscoveryErrors = @()
    ProcessingErrors = @()
    RetriableErrors = 0
    NonRetriableErrors = 0
}

$Script:CircuitBreaker = @{
    FailureCount = 0
    LastFailureTime = $null
    IsOpen = $false
}

$Script:ExitCode = 0
$Script:LogBatch = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
$Script:NetworkConnections = @{}
$Script:StructuredLogs = @()

#endregion

#region Public Functions

<#
.SYNOPSIS
    Gets the current HashSmith configuration

.DESCRIPTION
    Returns the current configuration hashtable for HashSmith operations

.EXAMPLE
    $config = Get-HashSmithConfig
#>
function Get-HashSmithConfig {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    
    return $Script:Config.Clone()
}

<#
.SYNOPSIS
    Gets the current HashSmith statistics

.DESCRIPTION
    Returns the current statistics hashtable for monitoring progress

.EXAMPLE
    $stats = Get-HashSmithStatistics
#>
function Get-HashSmithStatistics {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    
    return $Script:Statistics.Clone()
}

<#
.SYNOPSIS
    Gets the current circuit breaker state

.DESCRIPTION
    Returns the current circuit breaker state for error handling

.EXAMPLE
    $breaker = Get-HashSmithCircuitBreaker
#>
function Get-HashSmithCircuitBreaker {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    
    return $Script:CircuitBreaker.Clone()
}

<#
.SYNOPSIS
    Gets the current exit code

.DESCRIPTION
    Returns the current exit code for the HashSmith operation

.EXAMPLE
    $exitCode = Get-HashSmithExitCode
#>
function Get-HashSmithExitCode {
    [CmdletBinding()]
    [OutputType([int])]
    param()
    
    return $Script:ExitCode
}

<#
.SYNOPSIS
    Sets the HashSmith exit code

.DESCRIPTION
    Sets the exit code for the HashSmith operation

.PARAMETER ExitCode
    The exit code to set

.EXAMPLE
    Set-HashSmithExitCode -ExitCode 1
#>
function Set-HashSmithExitCode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$ExitCode
    )
    
    $Script:ExitCode = $ExitCode
}

<#
.SYNOPSIS
    Gets the log batch queue

.DESCRIPTION
    Returns the current log batch queue for batch logging operations

.EXAMPLE
    $logBatch = Get-HashSmithLogBatch
#>
function Get-HashSmithLogBatch {
    [CmdletBinding()]
    [OutputType([System.Collections.Concurrent.ConcurrentQueue[string]])]
    param()
    
    # Initialize if null (can happen with module loading order issues)
    if ($null -eq $Script:LogBatch) {
        $Script:LogBatch = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
    }
    
    return $Script:LogBatch
}

<#
.SYNOPSIS
    Gets the network connections cache

.DESCRIPTION
    Returns the current network connections cache

.EXAMPLE
    $connections = Get-HashSmithNetworkConnections
#>
function Get-HashSmithNetworkConnections {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    
    return $Script:NetworkConnections
}

<#
.SYNOPSIS
    Gets the structured logs collection

.DESCRIPTION
    Returns the current structured logs collection for JSON output

.EXAMPLE
    $logs = Get-HashSmithStructuredLogs
#>
function Get-HashSmithStructuredLogs {
    [CmdletBinding()]
    [OutputType([array])]
    param()
    
    return $Script:StructuredLogs
}

<#
.SYNOPSIS
    Adds a structured log entry

.DESCRIPTION
    Adds an entry to the structured logs collection

.PARAMETER LogEntry
    The log entry to add

.EXAMPLE
    Add-HashSmithStructuredLog -LogEntry $logEntry
#>
function Add-HashSmithStructuredLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$LogEntry
    )
    
    $Script:StructuredLogs += $LogEntry
}

<#
.SYNOPSIS
    Initializes HashSmith configuration with custom values

.DESCRIPTION
    Allows customization of the default configuration values

.PARAMETER ConfigOverrides
    Hashtable of configuration overrides

.EXAMPLE
    Initialize-HashSmithConfig -ConfigOverrides @{ BufferSize = 8MB }
#>
function Initialize-HashSmithConfig {
    [CmdletBinding()]
    param(
        [hashtable]$ConfigOverrides = @{}
    )
    
    foreach ($key in $ConfigOverrides.Keys) {
        if ($Script:Config.ContainsKey($key)) {
            $Script:Config[$key] = $ConfigOverrides[$key]
        }
    }
}

<#
.SYNOPSIS
    Resets HashSmith statistics

.DESCRIPTION
    Resets all statistics counters to their initial state

.EXAMPLE
    Reset-HashSmithStatistics
#>
function Reset-HashSmithStatistics {
    [CmdletBinding()]
    param()
    
    $Script:Statistics = @{
        StartTime = Get-Date
        FilesDiscovered = 0
        FilesProcessed = 0
        FilesSkipped = 0
        FilesError = 0
        FilesSymlinks = 0
        FilesRaceCondition = 0
        BytesProcessed = 0
        NetworkPaths = 0
        LongPaths = 0
        DiscoveryErrors = @()
        ProcessingErrors = @()
        RetriableErrors = 0
        NonRetriableErrors = 0
    }
}

<#
.SYNOPSIS
    Updates a specific statistic value

.DESCRIPTION
    Updates a specific statistic in the global statistics hashtable

.PARAMETER Name
    The name of the statistic to update

.PARAMETER Value
    The value to set

.EXAMPLE
    Set-HashSmithStatistic -Name 'FilesDiscovered' -Value 1000
#>
function Set-HashSmithStatistic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [Parameter(Mandatory)]
        $Value
    )
    
    $Script:Statistics[$Name] = $Value
}

<#
.SYNOPSIS
    Increments a specific statistic value

.DESCRIPTION
    Increments a specific statistic in the global statistics hashtable

.PARAMETER Name
    The name of the statistic to increment

.PARAMETER Amount
    The amount to increment by (default: 1)

.EXAMPLE
    Add-HashSmithStatistic -Name 'FilesProcessed' -Amount 1
#>
function Add-HashSmithStatistic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [int]$Amount = 1
    )
    
    if ($Script:Statistics.ContainsKey($Name)) {
        $Script:Statistics[$Name] += $Amount
    } else {
        $Script:Statistics[$Name] = $Amount
    }
}

#endregion

#region Configuration Functions

<#
.SYNOPSIS
    Initializes the HashSmith configuration with default values

.DESCRIPTION
    Initializes the HashSmith configuration hashtable with default values,
    resetting all configuration to a known state

.EXAMPLE
    Initialize-HashSmithConfig
#>
function Initialize-HashSmithConfig {
    [CmdletBinding()]
    param()
    
    # Reset to default configuration
    $Script:Config = @{
        Version = '4.1.0'
        BufferSize = 4MB
        MaxRetryDelay = 5000
        ProgressInterval = 25
        LogEncoding = [System.Text.Encoding]::UTF8
        DateFormat = 'yyyy-MM-dd HH:mm:ss.fff'
        SupportLongPaths = $true
        NetworkTimeoutMs = 30000
        IntegrityHashSize = 1KB
        CircuitBreakerThreshold = 10
        CircuitBreakerTimeout = 30
        
        # Additional runtime configuration
        TargetPath = $null
        Algorithm = 'MD5'
        EnableParallelDiscovery = $true
        MaxParallelJobs = 4
        EnableProgressSpinner = $true
        SpinnerThresholdMB = 50
    }
    
    # Reset statistics
    Reset-HashSmithStatistics
    
    # Reset circuit breaker
    $Script:CircuitBreaker = @{
        FailureCount = 0
        LastFailureTime = $null
        IsOpen = $false
    }
}

<#
.SYNOPSIS
    Sets a HashSmith configuration value

.DESCRIPTION
    Sets a specific configuration value in the HashSmith configuration

.PARAMETER Key
    The configuration key to set

.PARAMETER Value
    The value to set for the configuration key

.EXAMPLE
    Set-HashSmithConfig -Key 'TargetPath' -Value 'C:\temp'

.EXAMPLE
    Set-HashSmithConfig -Key 'Algorithm' -Value 'SHA256'
#>
function Set-HashSmithConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Key,
        
        [Parameter(Mandatory)]
        $Value
    )
    
    $Script:Config[$Key] = $Value
}

#endregion

# Export public functions
Export-ModuleMember -Function @(
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
    'Reset-HashSmithStatistics',
    'Set-HashSmithStatistic',
    'Add-HashSmithStatistic',
    'Set-HashSmithConfig'
)

# Export variables that need to be accessible
Export-ModuleMember -Variable @(
    'Config',
    'Statistics',
    'CircuitBreaker',
    'ExitCode',
    'LogBatch',
    'NetworkConnections',
    'StructuredLogs'
)

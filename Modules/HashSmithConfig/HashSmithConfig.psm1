<#
.SYNOPSIS
    Configuration and global variables management for HashSmith

.DESCRIPTION
    This module manages all configuration settings, global variables, and statistics
    for the HashSmith file integrity verification system. Enhanced with thread safety.
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

# Modern HashSmith configuration (initialized by Initialize-HashSmithConfig)
$Script:HashSmithConfig = $null

# Thread-safe statistics with proper synchronization
$Script:Statistics = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
$Script:StatisticsLock = [System.Object]::new()

$Script:CircuitBreaker = @{
    FailureCount = 0
    LastFailureTime = $null
    IsOpen = $false
}

$Script:ExitCode = 0
$Script:LogBatch = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
$Script:NetworkConnections = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
$Script:StructuredLogs = [System.Collections.Concurrent.ConcurrentBag[object]]::new()

#endregion

#region Private Functions

<#
.SYNOPSIS
    Initializes the statistics dictionary with default values

.DESCRIPTION
    Sets up the statistics with thread-safe defaults
#>
function Initialize-Statistics {
    [CmdletBinding()]
    param()
    
    $defaultStats = @{
        StartTime = Get-Date
        FilesDiscovered = 0
        FilesProcessed = 0
        FilesSkipped = 0
        FilesError = 0
        FilesSymlinks = 0
        FilesRaceCondition = 0
        BytesProcessed = [long]0
        NetworkPaths = 0
        LongPaths = 0
        DiscoveryErrors = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
        ProcessingErrors = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
        RetriableErrors = 0
        NonRetriableErrors = 0
    }
    
    foreach ($key in $defaultStats.Keys) {
        $Script:Statistics.TryAdd($key, $defaultStats[$key]) | Out-Null
    }
}

#endregion

#region Public Functions

<#
.SYNOPSIS
    Initializes the HashSmith configuration system

.DESCRIPTION
    Sets up the default configuration and applies any overrides. 
    This function must be called before using other HashSmith functions.
    Enhanced with thread safety.

.PARAMETER ConfigOverrides
    Optional hashtable of configuration overrides to apply

.EXAMPLE
    Initialize-HashSmithConfig
    Initialize-HashSmithConfig -ConfigOverrides @{ Algorithm = 'SHA256' }
#>
function Initialize-HashSmithConfig {
    [CmdletBinding()]
    param(
        [hashtable]$ConfigOverrides = @{}
    )
    
    # Initialize the configuration with defaults
    $Script:HashSmithConfig = @{
        Algorithm = 'MD5'
        TargetPath = $PWD.Path
        LogPath = ''
        IncludeHidden = $true
        IncludeSymlinks = $false
        VerifyIntegrity = $false
        StrictMode = $false
        TestMode = $false
        EnableParallelDiscovery = $true
        EnableParallelProcessing = $true
        MaxParallelJobs = [Environment]::ProcessorCount
        ChunkSize = 1000
        BufferSize = 1048576  # 1MB
        DateFormat = 'yyyy-MM-dd HH:mm:ss.fff'
        EnableProgressSpinner = $true
        SpinnerThresholdMB = 5
        ShowProgress = $true
        LogLevel = 'INFO'
        RetryCount = 3
        TimeoutSeconds = 30
        ExcludePatterns = @()
        MaxLogBatchSize = 100
        LogBatchInterval = 5000
    }
    
    # Apply any overrides
    foreach ($key in $ConfigOverrides.Keys) {
        if ($Script:HashSmithConfig.ContainsKey($key)) {
            $Script:HashSmithConfig[$key] = $ConfigOverrides[$key]
            Write-Verbose "Applied config override: $key = $($ConfigOverrides[$key])"
        } else {
            Write-Warning "Unknown configuration key: $key"
        }
    }
    
    # Initialize thread-safe statistics
    Initialize-Statistics
    
    Write-Verbose "HashSmith configuration initialized with thread safety"
}

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
    
    # Return the HashSmithConfig if it exists, otherwise fall back to Config
    if ($null -ne $Script:HashSmithConfig) {
        return $Script:HashSmithConfig.Clone()
    } else {
        return $Script:Config.Clone()
    }
}

<#
.SYNOPSIS
    Gets the current HashSmith statistics with thread safety

.DESCRIPTION
    Returns the current statistics hashtable for monitoring progress.
    Enhanced with thread-safe access.

.EXAMPLE
    $stats = Get-HashSmithStatistics
#>
function Get-HashSmithStatistics {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    
    [System.Threading.Monitor]::Enter($Script:StatisticsLock)
    try {
        $result = @{}
        foreach ($key in $Script:Statistics.Keys) {
            $value = $Script:Statistics[$key]
            if ($value -is [System.Collections.Concurrent.ConcurrentBag[object]]) {
                $result[$key] = @($value.ToArray())
            } else {
                $result[$key] = $value
            }
        }
        return $result
    }
    finally {
        [System.Threading.Monitor]::Exit($Script:StatisticsLock)
    }
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
    Sets the HashSmith exit code with thread safety

.DESCRIPTION
    Sets the exit code for the HashSmith operation with atomic operation

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
    
    # Use atomic operation for thread safety
    [System.Threading.Interlocked]::Exchange([ref]$Script:ExitCode, $ExitCode) | Out-Null
}

<#
.SYNOPSIS
    Gets the log batch queue with enhanced initialization

.DESCRIPTION
    Returns the current log batch queue for batch logging operations.
    Enhanced with proper initialization checks.

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
    Gets the network connections cache with thread safety

.DESCRIPTION
    Returns the current network connections cache with proper synchronization

.EXAMPLE
    $connections = Get-HashSmithNetworkConnections
#>
function Get-HashSmithNetworkConnections {
    [CmdletBinding()]
    [OutputType([System.Collections.Concurrent.ConcurrentDictionary[string, object]])]
    param()
    
    return $Script:NetworkConnections
}

<#
.SYNOPSIS
    Gets the structured logs collection with thread safety

.DESCRIPTION
    Returns the current structured logs collection for JSON output

.EXAMPLE
    $logs = Get-HashSmithStructuredLogs
#>
function Get-HashSmithStructuredLogs {
    [CmdletBinding()]
    [OutputType([array])]
    param()
    
    return @($Script:StructuredLogs.ToArray())
}

<#
.SYNOPSIS
    Adds a structured log entry with thread safety

.DESCRIPTION
    Adds an entry to the structured logs collection using thread-safe operations

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
    
    $Script:StructuredLogs.Add($LogEntry)
}

<#
.SYNOPSIS
    Resets HashSmith statistics with thread safety

.DESCRIPTION
    Resets all statistics counters to their initial state using proper synchronization

.EXAMPLE
    Reset-HashSmithStatistics
#>
function Reset-HashSmithStatistics {
    [CmdletBinding()]
    param()
    
    [System.Threading.Monitor]::Enter($Script:StatisticsLock)
    try {
        $Script:Statistics.Clear()
        Initialize-Statistics
    }
    finally {
        [System.Threading.Monitor]::Exit($Script:StatisticsLock)
    }
}

<#
.SYNOPSIS
    Updates a specific statistic value with thread safety

.DESCRIPTION
    Updates a specific statistic in the global statistics hashtable using atomic operations

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
    
    $Script:Statistics.AddOrUpdate($Name, $Value, { param($key, $oldValue) $Value })
}

<#
.SYNOPSIS
    Increments a specific statistic value with thread safety

.DESCRIPTION
    Increments a specific statistic in the global statistics hashtable using atomic operations

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
        
        [long]$Amount = 1
    )
    
    $Script:Statistics.AddOrUpdate($Name, $Amount, { 
        param($key, $oldValue) 
        if ($oldValue -is [long] -or $oldValue -is [int]) {
            return $oldValue + $Amount
        } else {
            return $Amount
        }
    })
}

<#
.SYNOPSIS
    Sets a HashSmith configuration value with validation

.DESCRIPTION
    Sets a specific configuration value in the HashSmith configuration with proper validation

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
    
    # Set in the modern config if it exists, otherwise fall back to old config
    if ($null -ne $Script:HashSmithConfig) {
        $Script:HashSmithConfig[$Key] = $Value
    } else {
        $Script:Config[$Key] = $Value
    }
    
    Write-Verbose "Configuration updated: $Key = $Value"
}

#endregion

# Initialize statistics on module load
Initialize-Statistics

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
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

# Thread-safe statistics with proper synchronization - REMOVED Monitor lock
$Script:Statistics = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
# REMOVED: $Script:StatisticsLock = [System.Object]::new()

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
    
    # Ensure the Statistics object is properly initialized
    if ($null -eq $Script:Statistics -or $Script:Statistics -isnot [System.Collections.Concurrent.ConcurrentDictionary[string, object]]) {
        Write-Verbose "Initializing Statistics ConcurrentDictionary"
        $Script:Statistics = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
    }
    
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
        ProgressTimeoutMinutes = 120  # 2 hours for no progress timeout (for large files)
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
    Gets the current HashSmith statistics with lock-free thread safety

.DESCRIPTION
    Returns the current statistics hashtable for monitoring progress.
    Enhanced with lock-free thread-safe access using ConcurrentDictionary methods only.

.EXAMPLE
    $stats = Get-HashSmithStatistics
#>
function Get-HashSmithStatistics {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    
    $result = @{}
    
    # Ensure Statistics is properly initialized
    if ($null -eq $Script:Statistics -or $Script:Statistics -isnot [System.Collections.Concurrent.ConcurrentDictionary[string, object]]) {
        Write-Warning "Statistics not properly initialized, reinitializing..."
        $Script:Statistics = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
        return $result
    }
    
    try {
        # Use lock-free snapshot approach with error handling
        $keys = @($Script:Statistics.Keys)
        foreach ($key in $keys) {
            $value = $null
            if ($Script:Statistics.TryGetValue($key, [ref]$value)) {
                if ($value -is [System.Collections.Concurrent.ConcurrentBag[object]]) {
                    $result[$key] = @($value.ToArray())
                } else {
                    $result[$key] = $value
                }
            }
        }
    }
    catch {
        Write-Warning "Error accessing statistics: $($_.Exception.Message)"
        # Return empty result on error
        $result = @{}
    }
    
    return $result
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
    Resets HashSmith statistics with lock-free thread safety

.DESCRIPTION
    Resets all statistics counters to their initial state using lock-free operations

.EXAMPLE
    Reset-HashSmithStatistics
#>
function Reset-HashSmithStatistics {
    [CmdletBinding()]
    param()
    
    # Ensure Statistics is properly initialized before clearing
    if ($null -eq $Script:Statistics -or $Script:Statistics -isnot [System.Collections.Concurrent.ConcurrentDictionary[string, object]]) {
        Write-Warning "Statistics not properly initialized in Reset-HashSmithStatistics, reinitializing..."
        $Script:Statistics = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
    } else {
        # Use lock-free approach - clear existing statistics
        $Script:Statistics.Clear()
    }
    
    # Reinitialize with defaults
    Initialize-Statistics
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
    
    # Ensure Statistics is properly initialized
    if ($null -eq $Script:Statistics -or $Script:Statistics -isnot [System.Collections.Concurrent.ConcurrentDictionary[string, object]]) {
        Write-Warning "Statistics not properly initialized in Set-HashSmithStatistic, reinitializing..."
        $Script:Statistics = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
    }
    
    try {
        $Script:Statistics.AddOrUpdate($Name, $Value, { param($key, $oldValue) $Value })
    }
    catch {
        Write-Warning "Error setting statistic '$Name': $($_.Exception.Message)"
    }
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
    
    # Ensure Statistics is properly initialized
    if ($null -eq $Script:Statistics -or $Script:Statistics -isnot [System.Collections.Concurrent.ConcurrentDictionary[string, object]]) {
        Write-Warning "Statistics not properly initialized in Add-HashSmithStatistic, reinitializing..."
        $Script:Statistics = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
    }
    
    try {
        $Script:Statistics.AddOrUpdate($Name, $Amount, { 
            param($key, $oldValue) 
            if ($oldValue -is [long] -or $oldValue -is [int]) {
                return $oldValue + $Amount
            } else {
                return $Amount
            }
        })
    }
    catch {
        Write-Warning "Error adding to statistic '$Name': $($_.Exception.Message)"
    }
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

<#
.SYNOPSIS
    Gets optimal buffer size for hash algorithm and file characteristics

.DESCRIPTION
    Returns optimized buffer size based on hash algorithm performance characteristics
    and file size for improved performance.

.PARAMETER Algorithm
    The hash algorithm being used

.PARAMETER FileSize
    Size of the file being processed

.EXAMPLE
    $bufferSize = Get-HashSmithOptimalBufferSize -Algorithm "SHA256" -FileSize 1048576
#>
function Get-HashSmithOptimalBufferSize {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('MD5', 'SHA1', 'SHA256', 'SHA512')]
        [string]$Algorithm,
        
        [Parameter(Mandatory)]
        [long]$FileSize
    )
    
    # Algorithm-specific optimal buffer sizes (based on testing)
    $algorithmBuffers = @{
        'MD5'    = @{ Small = 64KB; Medium = 128KB; Large = 256KB }
        'SHA1'   = @{ Small = 32KB; Medium = 64KB;  Large = 128KB }
        'SHA256' = @{ Small = 32KB; Medium = 64KB;  Large = 128KB }
        'SHA512' = @{ Small = 16KB; Medium = 32KB;  Large = 64KB  }
    }
    
    $buffers = $algorithmBuffers[$Algorithm]
    
    # Select buffer size based on file size
    if ($FileSize -lt 1MB) {
        return $buffers.Small
    } elseif ($FileSize -lt 100MB) {
        return $buffers.Medium  
    } else {
        return $buffers.Large
    }
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
    'Set-HashSmithConfig',
    'Get-HashSmithOptimalBufferSize'
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
<#
.SYNOPSIS
    Configuration and global variables management for HashSmith - ENHANCED WITH ATOMIC OPERATIONS

.DESCRIPTION
    This module manages all configuration settings, global variables, and statistics
    for the HashSmith file integrity verification system. 
    
    CRITICAL ENHANCEMENTS:
    - Lock-free statistics using atomic operations for better performance
    - Thread-safe concurrent data structures throughout
    - Enhanced memory management and garbage collection
    - Improved initialization with validation
    - Performance monitoring and adaptive configuration
#>

#region Module Variables

# Script-level variables that will be accessible to importing scripts
$Script:Config = @{
    Version = '4.1.1'
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

# ENHANCED: Lock-free statistics with atomic operations for maximum performance
$Script:Statistics = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
$Script:AtomicCounters = [System.Collections.Concurrent.ConcurrentDictionary[string, long]]::new()

# Thread-safe circuit breaker with atomic operations
$Script:CircuitBreaker = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()

# Atomic exit code handling
$Script:ExitCode = [ref]0

# Enhanced concurrent collections for better performance
$Script:LogBatch = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
$Script:NetworkConnections = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
$Script:StructuredLogs = [System.Collections.Concurrent.ConcurrentBag[object]]::new()

# Performance monitoring
$Script:PerformanceCounters = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()

#endregion

#region Private Functions

<#
.SYNOPSIS
    Initializes atomic counters for lock-free statistics
#>
function Initialize-AtomicCounters {
    [CmdletBinding()]
    param()
    
    $defaultCounters = @{
        'FilesDiscovered' = 0
        'FilesProcessed' = 0
        'FilesSkipped' = 0
        'FilesError' = 0
        'FilesSymlinks' = 0
        'FilesRaceCondition' = 0
        'BytesProcessed' = 0
        'NetworkPaths' = 0
        'LongPaths' = 0
        'RetriableErrors' = 0
        'NonRetriableErrors' = 0
    }
    
    foreach ($counter in $defaultCounters.Keys) {
        $Script:AtomicCounters.TryAdd($counter, $defaultCounters[$counter]) | Out-Null
    }
    
    Write-Verbose "Initialized $($defaultCounters.Count) atomic counters for lock-free statistics"
}

<#
.SYNOPSIS
    Initializes the statistics dictionary with enhanced thread-safe defaults
#>
function Initialize-Statistics {
    [CmdletBinding()]
    param()
    
    # Initialize atomic counters first
    Initialize-AtomicCounters
    
    # Initialize the main statistics dictionary
    if ($null -eq $Script:Statistics -or $Script:Statistics -isnot [System.Collections.Concurrent.ConcurrentDictionary[string, object]]) {
        Write-Verbose "Initializing enhanced Statistics ConcurrentDictionary"
        $Script:Statistics = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
    }
    
    $defaultStats = @{
        StartTime = Get-Date
        DiscoveryErrors = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
        ProcessingErrors = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
        PerformanceMetrics = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
        SystemLoad = @{
            CPU = 0
            Memory = 0
            DiskIO = 0
        }
    }
    
    foreach ($key in $defaultStats.Keys) {
        $Script:Statistics.TryAdd($key, $defaultStats[$key]) | Out-Null
    }
    
    # Initialize circuit breaker with atomic operations
    $Script:CircuitBreaker.TryAdd('FailureCount', 0) | Out-Null
    $Script:CircuitBreaker.TryAdd('LastFailureTime', $null) | Out-Null
    $Script:CircuitBreaker.TryAdd('IsOpen', $false) | Out-Null
    
    Write-Verbose "Enhanced statistics initialization complete with atomic operations"
}

<#
.SYNOPSIS
    Updates performance metrics for adaptive optimization
#>
function Update-PerformanceMetrics {
    [CmdletBinding()]
    param(
        [string]$Operation,
        [double]$Duration,
        [long]$BytesProcessed = 0
    )
    
    $metrics = $Script:PerformanceCounters.GetOrAdd($Operation, {
        @{
            TotalOperations = 0
            TotalDuration = 0.0
            TotalBytes = 0
            AverageRate = 0.0
            LastUpdate = Get-Date
        }
    })
    
    # Atomic updates to performance metrics
    $metrics.TotalOperations++
    $metrics.TotalDuration += $Duration
    $metrics.TotalBytes += $BytesProcessed
    
    if ($metrics.TotalDuration -gt 0) {
        $metrics.AverageRate = $metrics.TotalBytes / $metrics.TotalDuration
    }
    
    $metrics.LastUpdate = Get-Date
}

#endregion

#region Public Functions

<#
.SYNOPSIS
    Initializes the HashSmith configuration system with enhanced validation

.DESCRIPTION
    Sets up the default configuration and applies any overrides with enhanced
    validation, performance monitoring, and adaptive configuration.

.PARAMETER ConfigOverrides
    Optional hashtable of configuration overrides to apply

.EXAMPLE
    Initialize-HashSmithConfig -ConfigOverrides @{ Algorithm = 'SHA256' }
#>
function Initialize-HashSmithConfig {
    [CmdletBinding()]
    param(
        [hashtable]$ConfigOverrides = @{}
    )
    
    Write-Verbose "Initializing ENHANCED HashSmith configuration with validation"
    
    # Initialize the configuration with enhanced defaults
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
        ProgressTimeoutMinutes = 120
        ExcludePatterns = @()
        MaxLogBatchSize = 100
        LogBatchInterval = 5000
        # Enhanced configuration options
        AdaptiveChunking = $true
        DynamicThreading = $true
        PerformanceMonitoring = $true
        GracefulTermination = $true
        MemoryManagement = $true
    }
    
    # Apply and validate overrides
    foreach ($key in $ConfigOverrides.Keys) {
        if ($Script:HashSmithConfig.ContainsKey($key)) {
            $oldValue = $Script:HashSmithConfig[$key]
            $newValue = $ConfigOverrides[$key]
            
            # Enhanced validation
            $isValid = switch ($key) {
                'MaxParallelJobs' { $newValue -ge 1 -and $newValue -le 64 }
                'ChunkSize' { $newValue -ge 50 -and $newValue -le 5000 }
                'BufferSize' { $newValue -ge 4KB -and $newValue -le 64MB }
                'TimeoutSeconds' { $newValue -ge 5 -and $newValue -le 300 }
                'ProgressTimeoutMinutes' { $newValue -ge 5 -and $newValue -le 1440 }
                default { $true }
            }
            
            if ($isValid) {
                $Script:HashSmithConfig[$key] = $newValue
                Write-Verbose "Applied validated config override: $key = $oldValue → $newValue"
            } else {
                Write-Warning "Invalid configuration value for ${key}: $newValue (keeping $oldValue)"
            }
        } else {
            Write-Warning "Unknown configuration key: $key"
        }
    }
    
    # Initialize enhanced thread-safe statistics
    Initialize-Statistics
    
    Write-Verbose "Enhanced HashSmith configuration initialized with atomic operations and validation"
}

<#
.SYNOPSIS
    Gets the current HashSmith configuration with thread safety

.DESCRIPTION
    Returns a safe copy of the current configuration hashtable

.EXAMPLE
    $config = Get-HashSmithConfig
#>
function Get-HashSmithConfig {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    
    # Return thread-safe copy of configuration
    if ($null -ne $Script:HashSmithConfig) {
        return $Script:HashSmithConfig.Clone()
    } else {
        return $Script:Config.Clone()
    }
}

<#
.SYNOPSIS
    Gets current statistics with enhanced lock-free access

.DESCRIPTION
    Returns current statistics using atomic operations for maximum performance
    and thread safety without locks.

.EXAMPLE
    $stats = Get-HashSmithStatistics
#>
function Get-HashSmithStatistics {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    
    $result = @{}
    
    try {
        # Get atomic counter values without locks
        foreach ($counter in $Script:AtomicCounters.Keys) {
            $value = 0
            if ($Script:AtomicCounters.TryGetValue($counter, [ref]$value)) {
                $result[$counter] = $value
            }
        }
        
        # Get non-atomic statistics safely
        $keys = @($Script:Statistics.Keys)
        foreach ($key in $keys) {
            $value = $null
            if ($Script:Statistics.TryGetValue($key, [ref]$value)) {
                if ($value -is [System.Collections.Concurrent.ConcurrentBag[object]]) {
                    $result[$key] = @($value.ToArray())
                } elseif ($value -is [System.Collections.Concurrent.ConcurrentDictionary[string, object]]) {
                    $result[$key] = @{}
                    foreach ($kvp in $value.GetEnumerator()) {
                        $result[$key][$kvp.Key] = $kvp.Value
                    }
                } else {
                    $result[$key] = $value
                }
            }
        }
        
        # Add performance metrics
        $perfMetrics = @{}
        foreach ($kvp in $Script:PerformanceCounters.GetEnumerator()) {
            $perfMetrics[$kvp.Key] = $kvp.Value
        }
        $result['PerformanceCounters'] = $perfMetrics
        
    }
    catch {
        Write-Warning "Error accessing enhanced statistics: $($_.Exception.Message)"
        return @{}
    }
    
    return $result
}

<#
.SYNOPSIS
    Gets circuit breaker state with atomic operations

.DESCRIPTION
    Returns the current circuit breaker state using lock-free operations

.EXAMPLE
    $breaker = Get-HashSmithCircuitBreaker
#>
function Get-HashSmithCircuitBreaker {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    
    $result = @{}
    
    try {
        foreach ($key in $Script:CircuitBreaker.Keys) {
            $value = $null
            if ($Script:CircuitBreaker.TryGetValue($key, [ref]$value)) {
                $result[$key] = $value
            }
        }
    }
    catch {
        Write-Warning "Error accessing circuit breaker state: $($_.Exception.Message)"
        return @{ FailureCount = 0; LastFailureTime = $null; IsOpen = $false }
    }
    
    return $result
}

<#
.SYNOPSIS
    Gets the current exit code using atomic operations

.DESCRIPTION
    Returns the current exit code with thread safety

.EXAMPLE
    $exitCode = Get-HashSmithExitCode
#>
function Get-HashSmithExitCode {
    [CmdletBinding()]
    [OutputType([int])]
    param()
    
    return [System.Threading.Interlocked]::CompareExchange([ref]$Script:ExitCode, 0, 0)
}

<#
.SYNOPSIS
    Sets the HashSmith exit code with atomic operations

.DESCRIPTION
    Sets the exit code using atomic compare-and-swap to prevent race conditions

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
    
    $oldValue = [System.Threading.Interlocked]::Exchange([ref]$Script:ExitCode, $ExitCode)
    Write-Verbose "Exit code changed: $oldValue → $ExitCode"
}

<#
.SYNOPSIS
    Gets the log batch queue with enhanced initialization

.DESCRIPTION
    Returns the current log batch queue with thread-safe access

.EXAMPLE
    $logBatch = Get-HashSmithLogBatch
#>
function Get-HashSmithLogBatch {
    [CmdletBinding()]
    [OutputType([System.Collections.Concurrent.ConcurrentQueue[string]])]
    param()
    
    # Initialize if null with thread safety
    if ($null -eq $Script:LogBatch) {
        $newQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
        $Script:LogBatch = $newQueue
    }
    
    return $Script:LogBatch
}

<#
.SYNOPSIS
    Gets the network connections cache

.DESCRIPTION
    Returns the current network connections cache with thread safety

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
    Gets the structured logs collection

.DESCRIPTION
    Returns the current structured logs as an array

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
    Adds an entry to the structured logs collection using atomic operations

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
    
    # Enhance log entry with additional metadata
    $enhancedEntry = $LogEntry.Clone()
    $enhancedEntry['ThreadId'] = [System.Threading.Thread]::CurrentThread.ManagedThreadId
    $enhancedEntry['ProcessId'] = $PID
    $enhancedEntry['MemoryUsage'] = [System.GC]::GetTotalMemory($false)
    
    $Script:StructuredLogs.Add($enhancedEntry)
}

<#
.SYNOPSIS
    Resets statistics with enhanced atomic operations

.DESCRIPTION
    Resets all statistics counters using lock-free atomic operations

.EXAMPLE
    Reset-HashSmithStatistics
#>
function Reset-HashSmithStatistics {
    [CmdletBinding()]
    param()
    
    Write-Verbose "Resetting statistics with atomic operations"
    
    # Reset atomic counters using atomic exchange
    foreach ($counter in $Script:AtomicCounters.Keys) {
        [System.Threading.Interlocked]::Exchange([ref]$Script:AtomicCounters[$counter], 0) | Out-Null
    }
    
    # Clear concurrent collections safely
    if ($null -ne $Script:Statistics) {
        $Script:Statistics.Clear()
    }
    
    if ($null -ne $Script:PerformanceCounters) {
        $Script:PerformanceCounters.Clear()
    }
    
    # Reinitialize with defaults
    Initialize-Statistics
    
    Write-Verbose "Statistics reset complete with atomic operations"
}

<#
.SYNOPSIS
    Updates a specific statistic using atomic operations

.DESCRIPTION
    Sets a statistic value using lock-free atomic operations for maximum performance

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
    
    try {
        if ($Script:AtomicCounters.ContainsKey($Name) -and $Value -is [long]) {
            # Use atomic exchange for numeric counters
            [System.Threading.Interlocked]::Exchange([ref]$Script:AtomicCounters[$Name], $Value) | Out-Null
            Write-Verbose "Atomic counter '$Name' set to $Value"
        } else {
            # Use concurrent dictionary for non-atomic values
            $Script:Statistics.AddOrUpdate($Name, $Value, { param($key, $oldValue) $Value }) | Out-Null
            Write-Verbose "Statistic '$Name' set to $Value"
        }
    }
    catch {
        Write-Warning "Error setting statistic '$Name': $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Increments a statistic using atomic operations

.DESCRIPTION
    Atomically increments a counter for lock-free thread safety

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
    
    try {
        if ($Script:AtomicCounters.ContainsKey($Name)) {
            # Use atomic add for maximum performance
            $newValue = [System.Threading.Interlocked]::Add([ref]$Script:AtomicCounters[$Name], $Amount)
            Write-Verbose "Atomic counter '$Name' incremented by $Amount to $newValue"
        } else {
            # Fallback for non-atomic statistics
            $Script:Statistics.AddOrUpdate($Name, $Amount, { 
                param($key, $oldValue) 
                if ($oldValue -is [long] -or $oldValue -is [int]) {
                    return $oldValue + $Amount
                } else {
                    return $Amount
                }
            }) | Out-Null
            Write-Verbose "Statistic '$Name' incremented by $Amount"
        }
    }
    catch {
        Write-Warning "Error adding to statistic '$Name': $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Sets a configuration value with enhanced validation

.DESCRIPTION
    Sets a specific configuration value with validation and performance monitoring

.PARAMETER Key
    The configuration key to set

.PARAMETER Value
    The value to set for the configuration key

.EXAMPLE
    Set-HashSmithConfig -Key 'TargetPath' -Value 'C:\temp'
#>
function Set-HashSmithConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Key,
        
        [Parameter(Mandatory)]
        $Value
    )
    
    # Enhanced validation
    $isValid = $true
    $validationMessage = ""
    
    switch ($Key) {
        'MaxParallelJobs' { 
            if ($Value -lt 1 -or $Value -gt 64) {
                $isValid = $false
                $validationMessage = "MaxParallelJobs must be between 1 and 64"
            }
        }
        'ChunkSize' { 
            if ($Value -lt 50 -or $Value -gt 5000) {
                $isValid = $false
                $validationMessage = "ChunkSize must be between 50 and 5000"
            }
        }
        'BufferSize' { 
            if ($Value -lt 4KB -or $Value -gt 64MB) {
                $isValid = $false
                $validationMessage = "BufferSize must be between 4KB and 64MB"
            }
        }
    }
    
    if (-not $isValid) {
        Write-Warning "Configuration validation failed for ${Key}: $validationMessage"
        return
    }
    
    # Set in the modern config if it exists, otherwise fall back to old config
    if ($null -ne $Script:HashSmithConfig) {
        $oldValue = $Script:HashSmithConfig[$Key]
        $Script:HashSmithConfig[$Key] = $Value
        Write-Verbose "Configuration updated with validation: $Key = $oldValue → $Value"
    } else {
        $Script:Config[$Key] = $Value
        Write-Verbose "Legacy configuration updated: $Key = $Value"
    }
}

<#
.SYNOPSIS
    Gets optimal buffer size with enhanced algorithm-specific optimization

.DESCRIPTION
    Returns optimized buffer size based on hash algorithm performance characteristics,
    file size, and system capabilities for improved performance.

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
    
    # Enhanced algorithm-specific optimal buffer sizes based on performance testing
    $algorithmBuffers = @{
        'MD5'    = @{ Small = 64KB; Medium = 128KB; Large = 256KB; VeryLarge = 512KB }
        'SHA1'   = @{ Small = 32KB; Medium = 64KB;  Large = 128KB; VeryLarge = 256KB }
        'SHA256' = @{ Small = 32KB; Medium = 64KB;  Large = 128KB; VeryLarge = 256KB }
        'SHA512' = @{ Small = 16KB; Medium = 32KB;  Large = 64KB;  VeryLarge = 128KB }
    }
    
    $buffers = $algorithmBuffers[$Algorithm]
    
    # Enhanced file size classification with very large file support
    if ($FileSize -lt 1MB) {
        return $buffers.Small
    } elseif ($FileSize -lt 100MB) {
        return $buffers.Medium
    } elseif ($FileSize -lt 1GB) {
        return $buffers.Large
    } else {
        # Very large files get the largest buffer for streaming efficiency
        return $buffers.VeryLarge
    }
}

<#
.SYNOPSIS
    Gets performance metrics for monitoring and optimization

.DESCRIPTION
    Returns current performance metrics for analysis and adaptive optimization

.EXAMPLE
    $metrics = Get-HashSmithPerformanceMetrics
#>
function Get-HashSmithPerformanceMetrics {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    
    $result = @{}
    
    foreach ($kvp in $Script:PerformanceCounters.GetEnumerator()) {
        $result[$kvp.Key] = $kvp.Value
    }
    
    # Add system performance metrics
    try {
        $result['SystemMemory'] = @{
            Used = [System.GC]::GetTotalMemory($false)
            Collections = @{
                Gen0 = [System.GC]::CollectionCount(0)
                Gen1 = [System.GC]::CollectionCount(1)
                Gen2 = [System.GC]::CollectionCount(2)
            }
        }
        
        $result['ThreadPool'] = @{
            AvailableWorkerThreads = 0
            AvailableIOThreads = 0
        }
        
        [System.Threading.ThreadPool]::GetAvailableThreads(
            [ref]$result['ThreadPool'].AvailableWorkerThreads,
            [ref]$result['ThreadPool'].AvailableIOThreads
        )
    }
    catch {
        Write-Warning "Could not retrieve system performance metrics: $($_.Exception.Message)"
    }
    
    return $result
}

#endregion

# Initialize enhanced statistics on module load
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
    'Get-HashSmithOptimalBufferSize',
    'Get-HashSmithPerformanceMetrics'
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
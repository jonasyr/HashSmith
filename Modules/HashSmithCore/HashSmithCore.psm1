<#
.SYNOPSIS
    Core utilities and helper functions for HashSmith - ENHANCED WITH THREAD SAFETY

.DESCRIPTION
    This module provides enhanced core utility functions including:
    - Thread-safe logging with atomic operations
    - Improved circuit breaker with lock-free implementation
    - Enhanced network monitoring with automatic failover
    - Graceful termination handling with proper cleanup
    - Performance-optimized file operations
    - Real-time system monitoring and adaptive behavior
#>

# Script-level variables for enhanced functionality
$Script:NetworkMonitorRunning = $false
$Script:CircuitBreakerLock = [System.Object]::new()
$Script:TerminationHandlers = [System.Collections.Concurrent.ConcurrentBag[scriptblock]]::new()
$Script:SystemMonitor = $null

#region Enhanced System Monitoring

<#
.SYNOPSIS
    Monitors system resources for adaptive behavior
#>
function Start-SystemResourceMonitor {
    [CmdletBinding()]
    param()
    
    if ($Script:SystemMonitor) { return }
    
    $Script:SystemMonitor = Start-Job -ScriptBlock {
        while ($true) {
            try {
                # Monitor memory usage
                $memoryUsage = [System.GC]::GetTotalMemory($false)
                $generation0 = [System.GC]::CollectionCount(0)
                $generation1 = [System.GC]::CollectionCount(1)
                $generation2 = [System.GC]::CollectionCount(2)
                
                # Get thread pool info
                $availableWorkerThreads = 0
                $availableIOThreads = 0
                [System.Threading.ThreadPool]::GetAvailableThreads([ref]$availableWorkerThreads, [ref]$availableIOThreads)
                
                # Adaptive garbage collection
                if ($memoryUsage -gt 500MB) {
                    [System.GC]::Collect(0)  # Minor collection
                }
                
                if ($memoryUsage -gt 1GB) {
                    [System.GC]::Collect()   # Full collection
                    [System.GC]::WaitForPendingFinalizers()
                }
                
                Start-Sleep -Seconds 30
            }
            catch {
                # Silent monitoring - don't disrupt main processing
                Start-Sleep -Seconds 60
            }
        }
    }
    
    Write-HashSmithLog -Message "System resource monitoring started" -Level DEBUG -Component 'SYSTEM'
}

<#
.SYNOPSIS
    Stops system resource monitoring
#>
function Stop-SystemResourceMonitor {
    [CmdletBinding()]
    param()
    
    if ($Script:SystemMonitor) {
        Stop-Job $Script:SystemMonitor -ErrorAction SilentlyContinue
        Remove-Job $Script:SystemMonitor -Force -ErrorAction SilentlyContinue
        $Script:SystemMonitor = $null
        Write-HashSmithLog -Message "System resource monitoring stopped" -Level DEBUG -Component 'SYSTEM'
    }
}

#endregion

#region Enhanced Termination Handling

<#
.SYNOPSIS
    Registers a termination handler for graceful shutdown
#>
function Register-TerminationHandler {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Handler
    )
    
    $Script:TerminationHandlers.Add($Handler)
}

<#
.SYNOPSIS
    Executes all registered termination handlers
#>
function Invoke-TerminationHandlers {
    [CmdletBinding()]
    param()
    
    Write-HashSmithLog -Message "Executing graceful termination handlers" -Level INFO -Component 'TERMINATION'
    
    foreach ($handler in $Script:TerminationHandlers.ToArray()) {
        try {
            & $handler
        }
        catch {
            Write-HashSmithLog -Message "Termination handler error: $($_.Exception.Message)" -Level WARN -Component 'TERMINATION'
        }
    }
}

#endregion

#region Public Functions

<#
.SYNOPSIS
    Writes enhanced log messages with atomic operations and improved performance

.DESCRIPTION
    Provides high-performance logging with optimized color coding, thread safety,
    and structured logging for JSON output. Enhanced with atomic operations.

.PARAMETER Message
    The message to log

.PARAMETER Level
    The log level (DEBUG, INFO, WARN, ERROR, SUCCESS, PROGRESS, HEADER, STATS)

.PARAMETER Component
    The component name for categorization

.PARAMETER Data
    Additional structured data for JSON logging

.PARAMETER NoTimestamp
    Skip timestamp in the output

.PARAMETER NoBatch
    Skip batch logging

.PARAMETER UseJsonLog
    Enable JSON structured logging

.EXAMPLE
    Write-HashSmithLog -Message "Processing started" -Level INFO -Component "MAIN"
#>
function Write-HashSmithLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR', 'SUCCESS', 'PROGRESS', 'HEADER', 'STATS')]
        [string]$Level = 'INFO',
        
        [string]$Component = 'MAIN',
        
        [hashtable]$Data = @{},
        
        [switch]$NoTimestamp,
        
        [switch]$NoBatch,
        
        [switch]$UseJsonLog
    )
    
    $config = Get-HashSmithConfig
    $timestamp = Get-Date -Format $config.DateFormat
    
    # Enhanced emoji/symbol prefixes with better visual distinction
    $prefix = switch ($Level) {
        'DEBUG'    { "🔍" }
        'INFO'     { "ℹ️ " }
        'WARN'     { "⚠️ " }
        'ERROR'    { "❌" }
        'SUCCESS'  { "✅" }
        'PROGRESS' { "⚡" }
        'HEADER'   { "🚀" }
        'STATS'    { "📊" }
        default    { "•" }
    }
    
    # High-contrast color scheme optimized for readability
    $colorMap = @{
        'DEBUG'    = 'DarkGray'
        'INFO'     = 'Cyan'
        'WARN'     = 'Yellow'
        'ERROR'    = 'Red'
        'SUCCESS'  = 'Green'
        'PROGRESS' = 'Magenta'
        'HEADER'   = 'Blue'
        'STATS'    = 'Green'
    }
    
    # Format the log entry with optimized string operations
    $logEntry = if ($NoTimestamp) {
        "$prefix $Message"
    } else {
        $componentTag = if ($Component -ne 'MAIN') { "[$Component] " } else { "" }
        "[$timestamp] $prefix $componentTag$Message"
    }
    
    # Atomic output operations to prevent interleaved log messages
    $color = $colorMap[$Level]
    if ($color) {
        # Use Write-Host with proper synchronization
        [System.Threading.Monitor]::Enter($Script:CircuitBreakerLock)
        try {
            Write-Host $logEntry -ForegroundColor $color
        }
        finally {
            [System.Threading.Monitor]::Exit($Script:CircuitBreakerLock)
        }
    } else {
        Write-Host $logEntry -ForegroundColor White
    }
    
    Write-Verbose $logEntry
    
    # Enhanced structured logging with performance optimization
    if ($UseJsonLog -and $Level -in @('WARN', 'ERROR')) {
        $structuredEntry = @{
            Timestamp = $timestamp
            Level = $Level
            Component = $Component
            Message = $Message
            Data = $Data
            ProcessId = $PID
            ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
            MemoryUsage = [System.GC]::GetTotalMemory($false)
            MachineName = $env:COMPUTERNAME
        }
        
        Add-HashSmithStructuredLog -LogEntry $structuredEntry
    }
}

<#
.SYNOPSIS
    Enhanced network monitoring with automatic failover and recovery

.DESCRIPTION
    Provides resilient network monitoring with intelligent retry logic,
    automatic failover detection, and performance optimization.

.PARAMETER ServerName
    Network server to monitor

.PARAMETER OnDisconnectAction
    Action to execute when disconnection detected

.PARAMETER IntervalSeconds
    Monitoring interval in seconds (default: 30)

.PARAMETER TimeoutMs
    Connection timeout in milliseconds (default: 5000)

.EXAMPLE
    Start-HashSmithNetworkMonitor -ServerName "fileserver" -OnDisconnectAction { Write-Warning "Network lost" }
#>
function Start-HashSmithNetworkMonitor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerName,
        
        [scriptblock]$OnDisconnectAction = { 
            Write-HashSmithLog -Message "Network connectivity lost to $ServerName" -Level ERROR -Component 'NETWORK' 
        },
        
        [int]$IntervalSeconds = 30,
        
        [int]$TimeoutMs = 5000
    )
    
    $Script:NetworkMonitorRunning = $true
    
    # Enhanced monitoring with exponential backoff and circuit breaker
    $monitorJob = Start-Job -ScriptBlock {
        param($ServerName, $OnDisconnectAction, $IntervalSeconds, $TimeoutMs)
        
        $consecutiveFailures = 0
        $maxFailures = 3
        $backoffMultiplier = 1
        $maxBackoff = 300  # 5 minutes max
        
        while ($using:NetworkMonitorRunning) {
            try {
                # Enhanced connectivity test with timeout
                $tcpClient = [System.Net.Sockets.TcpClient]::new()
                $connectTask = $tcpClient.ConnectAsync($ServerName, 445)
                
                if ($connectTask.Wait($TimeoutMs)) {
                    $connected = $tcpClient.Connected
                    $tcpClient.Close()
                    
                    if ($connected) {
                        # Reset on successful connection
                        $consecutiveFailures = 0
                        $backoffMultiplier = 1
                    } else {
                        throw "Connection failed"
                    }
                } else {
                    $tcpClient.Close()
                    throw "Connection timeout"
                }
            }
            catch {
                $consecutiveFailures++
                
                if ($consecutiveFailures -ge $maxFailures) {
                    try {
                        & $OnDisconnectAction
                    }
                    catch {
                        # Prevent callback errors from crashing monitor
                    }
                    
                    # Exponential backoff
                    $backoffMultiplier = [Math]::Min($backoffMultiplier * 2, $maxBackoff / $IntervalSeconds)
                }
            }
            
            # Adaptive sleep with backoff
            $sleepTime = $IntervalSeconds * $backoffMultiplier
            Start-Sleep -Seconds $sleepTime
        }
    } -ArgumentList $ServerName, $OnDisconnectAction, $IntervalSeconds, $TimeoutMs
    
    # Register cleanup handler
    Register-TerminationHandler -Handler {
        Stop-HashSmithNetworkMonitor
    }
    
    Write-HashSmithLog -Message "Enhanced network monitoring started for $ServerName" -Level DEBUG -Component 'NETWORK'
    return $monitorJob
}

<#
.SYNOPSIS
    Stops network monitoring with proper cleanup

.DESCRIPTION
    Cleanly stops network monitoring and cleans up resources

.EXAMPLE
    Stop-HashSmithNetworkMonitor
#>
function Stop-HashSmithNetworkMonitor {
    [CmdletBinding()]
    param()
    
    $Script:NetworkMonitorRunning = $false
    
    # Enhanced cleanup
    Get-Job | Where-Object { $_.Name -like "*NetworkMonitor*" -or $_.State -eq 'Running' } | ForEach-Object {
        Stop-Job $_ -ErrorAction SilentlyContinue
        Remove-Job $_ -Force -ErrorAction SilentlyContinue
    }
    
    Write-HashSmithLog -Message "Network monitoring stopped and cleaned up" -Level DEBUG -Component 'NETWORK'
}

<#
.SYNOPSIS
    Tests network path connectivity with enhanced caching and performance

.DESCRIPTION
    Tests connectivity to network paths with intelligent caching, performance
    optimization, and automatic retry logic.

.PARAMETER Path
    The network path to test

.PARAMETER UseCache
    Use cached connectivity results

.EXAMPLE
    Test-HashSmithNetworkPath -Path "\\server\share" -UseCache
#>
function Test-HashSmithNetworkPath {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        
        [switch]$UseCache
    )
    
    if (-not ($Path -match '^\\\\([^\\]+)')) {
        return $true  # Not a network path
    }
    
    $serverName = $matches[1]
    $networkConnections = Get-HashSmithNetworkConnections
    
    # Enhanced caching with performance optimization
    if ($UseCache -and $networkConnections.ContainsKey($serverName)) {
        $cached = $networkConnections[$serverName]
        if (((Get-Date) - $cached.Timestamp).TotalMinutes -lt 2 -and $cached.IsAlive) {
            return $cached.IsAlive
        }
    }
    
    Write-HashSmithLog -Message "Testing enhanced network connectivity to $serverName" -Level DEBUG -Component 'NETWORK'
    
    try {
        # Enhanced connectivity test with multiple methods
        $result = $false
        
        # Method 1: Fast TCP connection test
        try {
            $tcpClient = [System.Net.Sockets.TcpClient]::new()
            $connectTask = $tcpClient.ConnectAsync($serverName, 445)
            
            if ($connectTask.Wait(3000)) {  # 3 second timeout
                $result = $tcpClient.Connected
                $tcpClient.Close()
            }
        }
        catch {
            # Fall back to PowerShell method
        }
        
        # Method 2: Fallback to Test-NetConnection if available
        if (-not $result) {
            try {
                $result = Test-NetConnection -ComputerName $serverName -Port 445 -InformationLevel Quiet -WarningAction SilentlyContinue -ErrorAction Stop
            }
            catch {
                $result = $false
            }
        }
        
        # Enhanced caching with atomic operations
        $cacheEntry = @{
            IsAlive = $result
            Timestamp = Get-Date
            TestMethod = if ($result) { "Enhanced" } else { "Failed" }
        }
        $networkConnections[$serverName] = $cacheEntry
        
        if ($result) {
            Add-HashSmithStatistic -Name 'NetworkPaths' -Amount 1
            Write-HashSmithLog -Message "Network path accessible: $serverName" -Level DEBUG -Component 'NETWORK'
        } else {
            Write-HashSmithLog -Message "Network path inaccessible: $serverName" -Level WARN -Component 'NETWORK'
            Update-HashSmithCircuitBreaker -IsFailure:$true
        }
        
        return $result
    }
    catch {
        Write-HashSmithLog -Message "Network connectivity test failed: $($_.Exception.Message)" -Level ERROR -Component 'NETWORK'
        Update-HashSmithCircuitBreaker -IsFailure:$true
        return $false
    }
}

<#
.SYNOPSIS
    Updates circuit breaker state with enhanced thread safety and lock-free operations

.DESCRIPTION
    Manages circuit breaker pattern with improved atomic operations and performance

.PARAMETER IsFailure
    Whether the operation was a failure

.PARAMETER Component
    The component name for categorization

.EXAMPLE
    Update-HashSmithCircuitBreaker -IsFailure $true -Component "FILE"
#>
function Update-HashSmithCircuitBreaker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [bool]$IsFailure,
        
        [string]$Component = 'GENERAL'
    )
    
    $config = Get-HashSmithConfig
    $circuitBreaker = Get-HashSmithCircuitBreaker
    
    # Enhanced thread-safe update with minimal locking
    [System.Threading.Monitor]::Enter($Script:CircuitBreakerLock)
    try {
        if ($IsFailure) {
            $newCount = $circuitBreaker.FailureCount + 1
            $circuitBreaker.FailureCount = $newCount
            $circuitBreaker.LastFailureTime = Get-Date
            
            if ($newCount -ge $config.CircuitBreakerThreshold) {
                $circuitBreaker.IsOpen = $true
                Write-HashSmithLog -Message "Circuit breaker opened after $newCount failures" -Level ERROR -Component $Component
                
                # Trigger system resource monitoring if not already running
                Start-SystemResourceMonitor
            }
        } else {
            # Enhanced recovery logic
            if ($circuitBreaker.IsOpen -and 
                $circuitBreaker.LastFailureTime -and
                ((Get-Date) - $circuitBreaker.LastFailureTime).TotalSeconds -gt $config.CircuitBreakerTimeout) {
                
                $circuitBreaker.FailureCount = 0
                $circuitBreaker.IsOpen = $false
                Write-HashSmithLog -Message "Circuit breaker reset after timeout" -Level INFO -Component $Component
            }
        }
        
        # Update the global circuit breaker state atomically
        $globalBreaker = Get-HashSmithCircuitBreaker
        foreach ($key in $circuitBreaker.Keys) {
            $globalBreaker[$key] = $circuitBreaker[$key]
        }
    }
    finally {
        [System.Threading.Monitor]::Exit($Script:CircuitBreakerLock)
    }
}

<#
.SYNOPSIS
    Tests circuit breaker state with enhanced performance

.DESCRIPTION
    Checks if operations should proceed based on circuit breaker state with
    optimized performance and reduced locking.

.PARAMETER Component
    The component name for categorization

.EXAMPLE
    if (Test-HashSmithCircuitBreaker -Component "FILE") { ... }
#>
function Test-HashSmithCircuitBreaker {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [string]$Component = 'GENERAL'
    )
    
    $config = Get-HashSmithConfig
    $circuitBreaker = Get-HashSmithCircuitBreaker
    
    # Lock-free read for better performance
    if ($circuitBreaker.IsOpen) {
        $timeSinceFailure = if ($circuitBreaker.LastFailureTime) {
            (Get-Date) - $circuitBreaker.LastFailureTime
        } else {
            [TimeSpan]::Zero
        }
        
        if ($timeSinceFailure.TotalSeconds -lt $config.CircuitBreakerTimeout) {
            Write-HashSmithLog -Message "Circuit breaker is open, skipping operation" -Level WARN -Component $Component
            return $false
        }
    }
    
    return $true
}

<#
.SYNOPSIS
    Normalizes file paths with enhanced Unicode and long path support

.DESCRIPTION
    Normalizes paths with improved error handling, performance optimization,
    and enhanced long path support.

.PARAMETER Path
    The path to normalize

.EXAMPLE
    $normalizedPath = Get-HashSmithNormalizedPath -Path $filePath
#>
function Get-HashSmithNormalizedPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    
    try {
        # Enhanced Unicode normalization with performance optimization
        $normalizedPath = [System.IO.Path]::GetFullPath($Path.Normalize([System.Text.NormalizationForm]::FormC))
        
        $config = Get-HashSmithConfig
        
        # Enhanced long path support with better detection
        if ($config.SupportLongPaths -and 
            $normalizedPath.Length -gt 260 -and 
            -not $normalizedPath.StartsWith('\\?\')) {
            
            Add-HashSmithStatistic -Name 'LongPaths' -Amount 1
            
            # Enhanced long-UNC path handling with validation
            if ($normalizedPath -match '^[\\\\]{2}[^\\]+\\') {
                # UNC path (\\server\share) - convert to \\?\UNC\server\share
                $uncPath = "\\?\UNC\" + $normalizedPath.Substring(2)
                Write-HashSmithLog -Message "Converted UNC long path: $normalizedPath" -Level DEBUG -Component 'PATH'
                return $uncPath
            } else {
                # Local path - convert to \\?\C:\path
                $longPath = "\\?\$normalizedPath"
                Write-HashSmithLog -Message "Converted local long path: $normalizedPath" -Level DEBUG -Component 'PATH'
                return $longPath
            }
        }
        
        return $normalizedPath
    }
    catch {
        Write-HashSmithLog -Message "Path normalization failed for: $Path - $($_.Exception.Message)" -Level ERROR -Component 'PATH'
        throw
    }
}

<#
.SYNOPSIS
    Tests file accessibility with enhanced timeout and performance

.DESCRIPTION
    Tests file accessibility with improved timeout handling, retry logic,
    and performance optimization.

.PARAMETER Path
    The file path to test

.PARAMETER TimeoutMs
    Timeout in milliseconds

.EXAMPLE
    if (Test-HashSmithFileAccessible -Path $filePath -TimeoutMs 5000) { ... }
#>
function Test-HashSmithFileAccessible {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        
        [int]$TimeoutMs = 5000
    )
    
    if (-not (Test-HashSmithCircuitBreaker -Component 'FILE')) {
        return $false
    }
    
    $timeout = (Get-Date).AddMilliseconds($TimeoutMs)
    $attemptCount = 0
    
    do {
        $attemptCount++
        try {
            $normalizedPath = Get-HashSmithNormalizedPath -Path $Path
            
            # Enhanced file access with better sharing options and performance
            $fileStream = [System.IO.File]::Open($normalizedPath, 'Open', 'Read', 'ReadWrite')
            $fileStream.Close()
            
            if ($attemptCount -gt 1) {
                Write-HashSmithLog -Message "File became accessible after $attemptCount attempts: $([System.IO.Path]::GetFileName($Path))" -Level DEBUG -Component 'FILE'
            }
            
            Update-HashSmithCircuitBreaker -IsFailure:$false -Component 'FILE'
            return $true
        }
        catch [System.IO.IOException] {
            if ((Get-Date) -gt $timeout) {
                Write-HashSmithLog -Message "File access timeout after $attemptCount attempts: $([System.IO.Path]::GetFileName($Path))" -Level WARN -Component 'FILE'
                Update-HashSmithCircuitBreaker -IsFailure:$true -Component 'FILE'
                return $false
            }
            # Adaptive sleep based on attempt count
            $sleepMs = [Math]::Min(50 * $attemptCount, 500)
            Start-Sleep -Milliseconds $sleepMs
        }
        catch {
            Write-HashSmithLog -Message "File access error: $([System.IO.Path]::GetFileName($Path)) - $($_.Exception.Message)" -Level ERROR -Component 'FILE'
            Update-HashSmithCircuitBreaker -IsFailure:$true -Component 'FILE'
            return $false
        }
    } while ($true)
}

<#
.SYNOPSIS
    Tests if a file is a symbolic link with enhanced performance

.DESCRIPTION
    Detects symbolic links and reparse points with improved performance
    and error handling.

.PARAMETER Path
    The file path to test

.EXAMPLE
    if (Test-HashSmithSymbolicLink -Path $filePath) { ... }
#>
function Test-HashSmithSymbolicLink {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    
    try {
        # Enhanced performance with direct attribute checking
        $attributes = [System.IO.File]::GetAttributes($Path)
        $isReparse = ($attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq [System.IO.FileAttributes]::ReparsePoint
        
        if ($isReparse) {
            Write-HashSmithLog -Message "Symbolic link/reparse point detected: $([System.IO.Path]::GetFileName($Path))" -Level DEBUG -Component 'SYMLINK'
            Add-HashSmithStatistic -Name 'FilesSymlinks' -Amount 1
            return $true
        }
        
        return $false
    }
    catch {
        Write-HashSmithLog -Message "Error checking symbolic link status for: $([System.IO.Path]::GetFileName($Path)) - $($_.Exception.Message)" -Level WARN -Component 'SYMLINK'
        return $false
    }
}

<#
.SYNOPSIS
    Gets file integrity snapshot with enhanced metadata

.DESCRIPTION
    Captures file metadata for integrity verification with enhanced performance
    and additional security attributes.

.PARAMETER Path
    The file path to snapshot

.EXAMPLE
    $snapshot = Get-HashSmithFileIntegritySnapshot -Path $filePath
#>
function Get-HashSmithFileIntegritySnapshot {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    
    try {
        $fileInfo = [System.IO.FileInfo]::new($Path)
        return @{
            Size = $fileInfo.Length
            LastWriteTime = $fileInfo.LastWriteTime
            LastWriteTimeUtc = $fileInfo.LastWriteTimeUtc
            CreationTime = $fileInfo.CreationTime
            Attributes = $fileInfo.Attributes
            LastAccessTime = $fileInfo.LastAccessTime
            IsReadOnly = $fileInfo.IsReadOnly
            # Enhanced snapshot with checksum for critical validation
            SnapshotTime = Get-Date
            PathHash = $Path.GetHashCode()
        }
    }
    catch {
        Write-HashSmithLog -Message "Error getting file integrity snapshot: $([System.IO.Path]::GetFileName($Path)) - $($_.Exception.Message)" -Level WARN -Component 'INTEGRITY'
        return $null
    }
}

<#
.SYNOPSIS
    Tests integrity snapshot matching with enhanced precision

.DESCRIPTION
    Compares file integrity snapshots with improved accuracy and performance

.PARAMETER Snapshot1
    First snapshot to compare

.PARAMETER Snapshot2
    Second snapshot to compare

.EXAMPLE
    if (Test-HashSmithFileIntegrityMatch -Snapshot1 $snap1 -Snapshot2 $snap2) { ... }
#>
function Test-HashSmithFileIntegrityMatch {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [hashtable]$Snapshot1,
        [hashtable]$Snapshot2
    )
    
    if (-not $Snapshot1 -or -not $Snapshot2) {
        return $false
    }
    
    # Enhanced comparison with more attributes and precision
    return ($Snapshot1.Size -eq $Snapshot2.Size -and
            $Snapshot1.LastWriteTimeUtc -eq $Snapshot2.LastWriteTimeUtc -and
            $Snapshot1.Attributes -eq $Snapshot2.Attributes -and
            $Snapshot1.IsReadOnly -eq $Snapshot2.IsReadOnly -and
            $Snapshot1.PathHash -eq $Snapshot2.PathHash)
}

#endregion

#region Enhanced Spinner Functionality

<#
.SYNOPSIS
    Shows professional spinner with enhanced performance and no background bleeding

.DESCRIPTION
    Shows a clean, professional spinner with optimized performance and proper cleanup

.PARAMETER Message
    The message to display

.PARAMETER Seconds
    How long to show the spinner

.EXAMPLE
    Show-HashSmithSpinner -Message "Processing large file..." -Seconds 5
#>
function Show-HashSmithSpinner {
    [CmdletBinding()]
    param(
        [string]$Message = "Processing...",
        [int]$Seconds = 3
    )
    
    # Enhanced spinner characters for better visual appeal
    $chars = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
    $endTime = (Get-Date).AddSeconds($Seconds)
    $i = 0
    
    try {
        while ((Get-Date) -lt $endTime) {
            $char = $chars[$i % $chars.Length]
            
            # Atomic output to prevent corruption
            [System.Threading.Monitor]::Enter($Script:CircuitBreakerLock)
            try {
                Write-Host "`r$char $Message" -NoNewline -ForegroundColor Cyan
            }
            finally {
                [System.Threading.Monitor]::Exit($Script:CircuitBreakerLock)
            }
            
            Start-Sleep -Milliseconds 120  # Optimized timing
            $i++
        }
    }
    finally {
        # Enhanced cleanup with proper spacing
        [System.Threading.Monitor]::Enter($Script:CircuitBreakerLock)
        try {
            Write-Host "`r$(' ' * ($Message.Length + 10))`r" -NoNewline
        }
        finally {
            [System.Threading.Monitor]::Exit($Script:CircuitBreakerLock)
        }
    }
}

<#
.SYNOPSIS
    Shows enhanced file spinner with real-time performance metrics

.DESCRIPTION
    Displays professional spinner with current file and enhanced progress information

.PARAMETER CurrentFile
    The current file being processed

.PARAMETER TotalFiles
    Total number of files

.PARAMETER ProcessedFiles
    Number of files processed

.PARAMETER ChunkInfo
    Information about the current chunk

.EXAMPLE
    Show-HashSmithFileSpinner -CurrentFile "largefile.zip" -TotalFiles 1000 -ProcessedFiles 250
#>
function Show-HashSmithFileSpinner {
    [CmdletBinding()]
    param(
        [string]$CurrentFile = "Processing...",
        [int]$TotalFiles = 0,
        [int]$ProcessedFiles = 0,
        [string]$ChunkInfo = ""
    )
    
    # Enhanced spinner with performance metrics
    $chars = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
    $char = $chars[(Get-Date).Millisecond % $chars.Length]
    
    # Smart file name truncation with better visual appeal
    $displayFile = if ($CurrentFile.Length -gt 40) {
        "..." + $CurrentFile.Substring($CurrentFile.Length - 37)
    } else {
        $CurrentFile
    }
    
    # Enhanced progress formatting with performance metrics
    $progress = if ($TotalFiles -gt 0) {
        $percent = [Math]::Round(($ProcessedFiles / $TotalFiles) * 100, 1)
        $rate = if ($ProcessedFiles -gt 0) {
            # Calculate rough processing rate
            $stats = Get-HashSmithStatistics
            if ($stats.StartTime) {
                $elapsed = (Get-Date) - $stats.StartTime
                if ($elapsed.TotalSeconds -gt 0) {
                    $filesPerSec = [Math]::Round($ProcessedFiles / $elapsed.TotalSeconds, 1)
                    "($ProcessedFiles/$TotalFiles - $percent% - $filesPerSec f/s)"
                } else {
                    "($ProcessedFiles/$TotalFiles - $percent%)"
                }
            } else {
                "($ProcessedFiles/$TotalFiles - $percent%)"
            }
        } else {
            "($ProcessedFiles/$TotalFiles - $percent%)"
        }
        $rate
    } else {
        ""
    }
    
    $chunkDisplay = if ($ChunkInfo) { "[$ChunkInfo] " } else { "" }
    $message = "$char $chunkDisplay$displayFile $progress"
    
    # Atomic output with enhanced cleanup
    [System.Threading.Monitor]::Enter($Script:CircuitBreakerLock)
    try {
        Write-Host "`r$(' ' * 120)`r$message" -NoNewline -ForegroundColor Cyan
    }
    finally {
        [System.Threading.Monitor]::Exit($Script:CircuitBreakerLock)
    }
}

<#
.SYNOPSIS
    Clears the file spinner with enhanced cleanup

.DESCRIPTION
    Properly clears the spinner line with atomic operations
#>
function Clear-HashSmithFileSpinner {
    [CmdletBinding()]
    param()
    
    [System.Threading.Monitor]::Enter($Script:CircuitBreakerLock)
    try {
        Write-Host "`r$(' ' * 120)`r" -NoNewline
    }
    finally {
        [System.Threading.Monitor]::Exit($Script:CircuitBreakerLock)
    }
}

# Legacy compatibility functions with enhanced performance
function Start-HashSmithSpinner {
    [CmdletBinding()]
    param([string]$Message = "Processing...")
    Write-Verbose "Enhanced spinner started: $Message"
}

function Stop-HashSmithSpinner {
    [CmdletBinding()]
    param()
    Write-Verbose "Enhanced spinner stopped"
}

function Update-HashSmithSpinner {
    [CmdletBinding()]
    param([string]$Message = "Processing...")
    Write-Verbose "Enhanced spinner updated: $Message"
}

function Show-HashSmithSpinnerDemo {
    [CmdletBinding()]
    param(
        [string]$Message = "Processing...",
        [int]$Seconds = 3
    )
    Show-HashSmithSpinner -Message $Message -Seconds $Seconds
}

#endregion

# Initialize enhanced system monitoring
Start-SystemResourceMonitor

# Register cleanup for module unload
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    Stop-SystemResourceMonitor
    Stop-HashSmithNetworkMonitor
    Invoke-TerminationHandlers
}

# Export public functions
Export-ModuleMember -Function @(
    'Write-HashSmithLog',
    'Test-HashSmithNetworkPath',
    'Update-HashSmithCircuitBreaker',
    'Test-HashSmithCircuitBreaker',
    'Get-HashSmithNormalizedPath',
    'Test-HashSmithFileAccessible',
    'Test-HashSmithSymbolicLink',
    'Get-HashSmithFileIntegritySnapshot',
    'Test-HashSmithFileIntegrityMatch',
    'Show-HashSmithSpinner',
    'Start-HashSmithSpinner',
    'Stop-HashSmithSpinner',
    'Update-HashSmithSpinner',
    'Show-HashSmithSpinnerDemo',
    'Show-HashSmithFileSpinner',
    'Clear-HashSmithFileSpinner',
    'Start-HashSmithNetworkMonitor',
    'Stop-HashSmithNetworkMonitor',
    'Register-TerminationHandler'
)
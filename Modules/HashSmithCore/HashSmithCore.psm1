<#
.SYNOPSIS
    Core utilities and helper functions for HashSmith - Simplified and Reliable

.DESCRIPTION
    This module provides core utility functions including:
    - Thread-safe logging with atomic operations
    - Simple circuit breaker implementation
    - Network monitoring with automatic failover
    - Graceful termination handling with proper cleanup
    - Performance-optimized file operations
#>

# Script-level variables
$Script:NetworkMonitorRunning = $false
$Script:CircuitBreakerLock = [System.Object]::new()
$Script:TerminationHandlers = [System.Collections.Concurrent.ConcurrentBag[scriptblock]]::new()

#region Termination Handling

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
    
    if (-not $global:HashSmithParallelMode) {
        Write-HashSmithLog -Message "Executing graceful termination handlers" -Level INFO -Component 'TERMINATION'
    }
    
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
    Writes log messages with atomic operations and improved performance

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
    
    # Suppress all logging in parallel mode except critical errors
    if ($global:HashSmithParallelMode -and $Level -ne 'ERROR') {
        return
    }
    
    $config = Get-HashSmithConfig
    $timestamp = Get-Date -Format $config.DateFormat
    
    # Emoji/symbol prefixes
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
    
    # Color scheme
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
    
    # Format the log entry
    $logEntry = if ($NoTimestamp) {
        "$prefix $Message"
    } else {
        $componentTag = if ($Component -ne 'MAIN') { "[$Component] " } else { "" }
        "[$timestamp] $prefix $componentTag$Message"
    }
    
    # Atomic output operations
    $color = $colorMap[$Level]
    if ($color) {
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
    
    # Structured logging
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
    Network monitoring with automatic failover and recovery

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
    
    # Simple monitoring with exponential backoff
    $monitorJob = Start-Job -ScriptBlock {
        param($ServerName, $OnDisconnectAction, $IntervalSeconds, $TimeoutMs)
        
        $consecutiveFailures = 0
        $maxFailures = 3
        $backoffMultiplier = 1
        $maxBackoff = 300
        
        while ($using:NetworkMonitorRunning) {
            try {
                # Simple connectivity test
                $tcpClient = [System.Net.Sockets.TcpClient]::new()
                $connectTask = $tcpClient.ConnectAsync($ServerName, 445)
                
                if ($connectTask.Wait($TimeoutMs)) {
                    $connected = $tcpClient.Connected
                    $tcpClient.Close()
                    
                    if ($connected) {
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
    
    Write-HashSmithLog -Message "Network monitoring started for $ServerName" -Level DEBUG -Component 'NETWORK'
    return $monitorJob
}

<#
.SYNOPSIS
    Stops network monitoring with proper cleanup

.EXAMPLE
    Stop-HashSmithNetworkMonitor
#>
function Stop-HashSmithNetworkMonitor {
    [CmdletBinding()]
    param()
    
    $Script:NetworkMonitorRunning = $false
    
    # Cleanup
    Get-Job | Where-Object { $_.Name -like "*NetworkMonitor*" -or $_.State -eq 'Running' } | ForEach-Object {
        Stop-Job $_ -ErrorAction SilentlyContinue
        Remove-Job $_ -Force -ErrorAction SilentlyContinue
    }
    
    if (-not $global:HashSmithParallelMode) {
        Write-HashSmithLog -Message "Network monitoring stopped and cleaned up" -Level DEBUG -Component 'NETWORK'
    }
}

<#
.SYNOPSIS
    Tests network path connectivity with caching and performance

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
    
    # Caching
    if ($UseCache -and $networkConnections.ContainsKey($serverName)) {
        $cached = $networkConnections[$serverName]
        if (((Get-Date) - $cached.Timestamp).TotalMinutes -lt 2 -and $cached.IsAlive) {
            return $cached.IsAlive
        }
    }
    
    Write-HashSmithLog -Message "Testing network connectivity to $serverName" -Level DEBUG -Component 'NETWORK'
    
    try {
        $result = $false
        
        # TCP connection test
        try {
            $tcpClient = [System.Net.Sockets.TcpClient]::new()
            $connectTask = $tcpClient.ConnectAsync($serverName, 445)
            
            if ($connectTask.Wait(3000)) {
                $result = $tcpClient.Connected
                $tcpClient.Close()
            }
        }
        catch {
            # Fall back to Test-NetConnection if available
        }
        
        # Fallback method
        if (-not $result) {
            try {
                $result = Test-NetConnection -ComputerName $serverName -Port 445 -InformationLevel Quiet -WarningAction SilentlyContinue -ErrorAction Stop
            }
            catch {
                $result = $false
            }
        }
        
        # Cache the result
        $cacheEntry = @{
            IsAlive = $result
            Timestamp = Get-Date
            TestMethod = if ($result) { "Success" } else { "Failed" }
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
    Updates circuit breaker state with thread safety

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
    
    # Thread-safe update
    [System.Threading.Monitor]::Enter($Script:CircuitBreakerLock)
    try {
        if ($IsFailure) {
            $newCount = $circuitBreaker.FailureCount + 1
            $circuitBreaker.FailureCount = $newCount
            $circuitBreaker.LastFailureTime = Get-Date
            
            if ($newCount -ge $config.CircuitBreakerThreshold) {
                $circuitBreaker.IsOpen = $true
                Write-HashSmithLog -Message "Circuit breaker opened after $newCount failures" -Level ERROR -Component $Component
            }
        } else {
            # Recovery logic
            if ($circuitBreaker.IsOpen -and 
                $circuitBreaker.LastFailureTime -and
                ((Get-Date) - $circuitBreaker.LastFailureTime).TotalSeconds -gt $config.CircuitBreakerTimeout) {
                
                $circuitBreaker.FailureCount = 0
                $circuitBreaker.IsOpen = $false
                Write-HashSmithLog -Message "Circuit breaker reset after timeout" -Level INFO -Component $Component
            }
        }
        
        # Update the global circuit breaker state
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
    Tests circuit breaker state

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
    
    # Lock-free read
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
    Normalizes file paths with Unicode and long path support

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
        # Unicode normalization
        $normalizedPath = [System.IO.Path]::GetFullPath($Path.Normalize([System.Text.NormalizationForm]::FormC))
        
        $config = Get-HashSmithConfig
        
        # Long path support
        if ($config.SupportLongPaths -and 
            $normalizedPath.Length -gt 260 -and 
            -not $normalizedPath.StartsWith('\\?\')) {
            
            Add-HashSmithStatistic -Name 'LongPaths' -Amount 1
            
            # Long-UNC path handling
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
    Tests file accessibility with timeout and performance

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
            
            # File access test
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
            # Adaptive sleep
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
    Tests if a file is a symbolic link

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
        # Direct attribute checking
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
    Gets file integrity snapshot

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
    Tests integrity snapshot matching

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
    
    # Compare key attributes
    return ($Snapshot1.Size -eq $Snapshot2.Size -and
            $Snapshot1.LastWriteTimeUtc -eq $Snapshot2.LastWriteTimeUtc -and
            $Snapshot1.Attributes -eq $Snapshot2.Attributes -and
            $Snapshot1.IsReadOnly -eq $Snapshot2.IsReadOnly -and
            $Snapshot1.PathHash -eq $Snapshot2.PathHash)
}

#endregion

#region Spinner Functionality

<#
.SYNOPSIS
    Shows professional spinner with proper console management

.PARAMETER Message
    The message to display

.PARAMETER Seconds
    How long to show the spinner

.PARAMETER UseProgress
    Show as progress rather than spinner

.EXAMPLE
    Show-HashSmithSpinner -Message "Processing large file..." -Seconds 5
#>
function Show-HashSmithSpinner {
    [CmdletBinding()]
    param(
        [string]$Message = "Processing...",
        [int]$Seconds = 3,
        [switch]$UseProgress
    )
    
    # Spinner characters
    $chars = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
    $endTime = (Get-Date).AddSeconds($Seconds)
    $i = 0
    
    try {
        while ((Get-Date) -lt $endTime) {
            $char = $chars[$i % $chars.Length]
            
            # Ensure message fits in console width
            $displayMessage = if ($Message.Length -gt 80) {
                $Message.Substring(0, 77) + "..."
            } else {
                $Message
            }
            
            # Atomic output with proper clearing
            [System.Threading.Monitor]::Enter($Script:CircuitBreakerLock)
            try {
                Write-Host ("`r" + (" " * 100) + "`r") -NoNewline
                Write-Host "$char $displayMessage" -NoNewline -ForegroundColor Cyan
            }
            finally {
                [System.Threading.Monitor]::Exit($Script:CircuitBreakerLock)
            }
            
            Start-Sleep -Milliseconds 120
            $i++
        }
    }
    finally {
        # Cleanup with proper clearing
        [System.Threading.Monitor]::Enter($Script:CircuitBreakerLock)
        try {
            Write-Host ("`r" + (" " * 100) + "`r") -NoNewline
        }
        finally {
            [System.Threading.Monitor]::Exit($Script:CircuitBreakerLock)
        }
    }
}

<#
.SYNOPSIS
    Shows file spinner with real-time performance metrics

.PARAMETER CurrentFile
    The current file being processed

.PARAMETER TotalFiles
    Total number of files

.PARAMETER ProcessedFiles
    Number of files processed

.PARAMETER ChunkInfo
    Information about the current chunk

.PARAMETER NoNewLine
    Don't add a newline, for continuous updates

.EXAMPLE
    Show-HashSmithFileSpinner -CurrentFile "largefile.zip" -TotalFiles 1000 -ProcessedFiles 250
#>
function Show-HashSmithFileSpinner {
    [CmdletBinding()]
    param(
        [string]$CurrentFile = "Processing...",
        [int]$TotalFiles = 0,
        [int]$ProcessedFiles = 0,
        [string]$ChunkInfo = "",
        [switch]$NoNewLine
    )
    
    # Spinner with performance metrics
    $chars = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
    $char = $chars[(Get-Date).Millisecond % $chars.Length]
    
    # Smart file name truncation
    $displayFile = if ($CurrentFile.Length -gt 35) {
        "..." + $CurrentFile.Substring($CurrentFile.Length - 32)
    } else {
        $CurrentFile
    }
    
    # Progress formatting
    $progress = if ($TotalFiles -gt 0) {
        $percent = [Math]::Round(($ProcessedFiles / $TotalFiles) * 100, 1)
        $rate = if ($ProcessedFiles -gt 0) {
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
    
    # Ensure the message fits in a reasonable width
    if ($message.Length -gt 100) {
        $message = $message.Substring(0, 97) + "..."
    }
    
    # Atomic output with proper clearing
    [System.Threading.Monitor]::Enter($Script:CircuitBreakerLock)
    try {
        # Clear the current line completely, then write new message
        Write-Host ("`r" + (" " * 120) + "`r") -NoNewline
        if ($NoNewLine) {
            Write-Host $message -NoNewline -ForegroundColor Cyan
        } else {
            Write-Host $message -ForegroundColor Cyan
        }
    }
    finally {
        [System.Threading.Monitor]::Exit($Script:CircuitBreakerLock)
    }
}

<#
.SYNOPSIS
    Clears the file spinner and any console artifacts

.PARAMETER Force
    Force clear multiple lines if needed

.EXAMPLE
    Clear-HashSmithFileSpinner
#>
function Clear-HashSmithFileSpinner {
    [CmdletBinding()]
    param(
        [switch]$Force
    )
    
    [System.Threading.Monitor]::Enter($Script:CircuitBreakerLock)
    try {
        if ($Force) {
            # Clear multiple lines for complex displays
            Write-Host ("`r" + (" " * 120) + "`r") -NoNewline
            Write-Host ("`r" + (" " * 120) + "`r") -NoNewline
            Write-Host ("`r" + (" " * 120) + "`r") -NoNewline
        } else {
            # Standard single line clear
            Write-Host ("`r" + (" " * 120) + "`r") -NoNewline
        }
    }
    finally {
        [System.Threading.Monitor]::Exit($Script:CircuitBreakerLock)
    }
}

#region Console Output Coordination

<#
.SYNOPSIS
    Safely writes progress information without interfering with other output

.PARAMETER Message
    The progress message to display

.PARAMETER NoSpinner
    Don't show spinner character

.PARAMETER Color
    Text color

.PARAMETER UseNewLine
    Use a new line instead of overwriting current line

.EXAMPLE
    Write-HashSmithProgress -Message "Processing file 10/100" -Color Yellow
#>
function Write-HashSmithProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [switch]$NoSpinner,
        
        [string]$Color = 'Cyan',
        
        [switch]$UseNewLine
    )
    
    $displayMessage = if (-not $NoSpinner) {
        $chars = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
        $char = $chars[(Get-Date).Millisecond % $chars.Length]
        "$char $Message"
    } else {
        "   $Message"
    }
    
    # Ensure message fits in console width
    if ($displayMessage.Length -gt 100) {
        $displayMessage = $displayMessage.Substring(0, 97) + "..."
    }
    
    # Atomic output with proper line management
    [System.Threading.Monitor]::Enter($Script:CircuitBreakerLock)
    try {
        if ($UseNewLine) {
            Write-Host $displayMessage -ForegroundColor $Color
        } else {
            # Clear line, write message
            Write-Host ("`r" + (" " * 120) + "`r") -NoNewline
            Write-Host $displayMessage -NoNewline -ForegroundColor $Color
        }
    }
    finally {
        [System.Threading.Monitor]::Exit($Script:CircuitBreakerLock)
    }
}

<#
.SYNOPSIS
    Clears any progress messages from console

.PARAMETER Lines
    Number of lines to clear (default: 1)

.EXAMPLE
    Clear-HashSmithProgress
#>
function Clear-HashSmithProgress {
    [CmdletBinding()]
    param(
        [int]$Lines = 1
    )
    
    [System.Threading.Monitor]::Enter($Script:CircuitBreakerLock)
    try {
        for ($i = 0; $i -lt $Lines; $i++) {
            Write-Host ("`r" + (" " * 120) + "`r") -NoNewline
        }
    }
    finally {
        [System.Threading.Monitor]::Exit($Script:CircuitBreakerLock)
    }
}

<#
.SYNOPSIS
    Forces a new line after any progress output

.EXAMPLE
    Complete-HashSmithProgress
#>
function Complete-HashSmithProgress {
    [CmdletBinding()]
    param()
    
    [System.Threading.Monitor]::Enter($Script:CircuitBreakerLock)
    try {
        Write-Host ("`r" + (" " * 120) + "`r") -NoNewline
        Write-Host ""  # Force new line
    }
    finally {
        [System.Threading.Monitor]::Exit($Script:CircuitBreakerLock)
    }
}

#endregion

#endregion

# Register cleanup for module unload
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    if (-not $global:HashSmithParallelMode) {
        Stop-HashSmithNetworkMonitor
        Invoke-TerminationHandlers
    }
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
    'Register-TerminationHandler',
    'Write-HashSmithProgress',
    'Clear-HashSmithProgress',
    'Complete-HashSmithProgress'
)
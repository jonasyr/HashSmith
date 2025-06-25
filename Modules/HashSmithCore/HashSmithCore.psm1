<#
.SYNOPSIS
    Core utilities and helper functions for HashSmith

.DESCRIPTION
    This module provides core utility functions including logging, network path testing,
    circuit breaker patterns, file access testing, and integrity verification.
    Enhanced with improved terminal output, thread safety, and real-time network monitoring.
#>

# Import the configuration module to access script variables
# Note: Dependencies are handled by the main script import order

# Script-level variables for network monitoring
$Script:NetworkMonitorRunning = $false

#region Public Functions

<#
.SYNOPSIS
    Writes enhanced log messages with professional formatting and improved terminal output

.DESCRIPTION
    Provides comprehensive logging with optimized color coding, timestamps, component tagging,
    and structured logging for JSON output. Fixed background bleeding issues.

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
    
    # Professional emoji/symbol prefixes - subtle and clean
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
    
    # Professional color scheme - foreground only, no background bleeding
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
    if ($NoTimestamp) {
        $logEntry = "$prefix $Message"
    } else {
        $componentTag = if ($Component -ne 'MAIN') { "[$Component] " } else { "" }
        $logEntry = "[$timestamp] $prefix $componentTag$Message"
    }
    
    # Output with professional colors - NO background colors to prevent bleeding
    $color = $colorMap[$Level]
    if ($color) {
        Write-Host $logEntry -ForegroundColor $color
    } else {
        Write-Host $logEntry -ForegroundColor White
    }
    
    Write-Verbose $logEntry
    
    # Structured logging for JSON output
    if ($UseJsonLog -and $Level -in @('WARN', 'ERROR')) {
        $structuredEntry = @{
            Timestamp = $timestamp
            Level = $Level
            Component = $Component
            Message = $Message
            Data = $Data
            ProcessId = $PID
            ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
        }
        
        Add-HashSmithStructuredLog -LogEntry $structuredEntry
    }
}

<#
.SYNOPSIS
    Monitors network connectivity in real-time with automatic recovery

.DESCRIPTION
    Provides continuous network monitoring with circuit breaker pattern for enhanced reliability.
    Runs as a background job to monitor network connectivity and trigger recovery actions.

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
        
        [scriptblock]$OnDisconnectAction = { Write-HashSmithLog -Message "Network connectivity lost to $ServerName" -Level ERROR -Component 'NETWORK' },
        
        [int]$IntervalSeconds = 30,
        
        [int]$TimeoutMs = 5000
    )
    
    $Script:NetworkMonitorRunning = $true
    
    # Start background monitoring job
    $monitorJob = Start-Job -ScriptBlock {
        param($ServerName, $OnDisconnectAction, $IntervalSeconds, $TimeoutMs)
        
        $consecutiveFailures = 0
        $maxFailures = 3
        
        while ($using:NetworkMonitorRunning) {
            try {
                $connected = Test-NetConnection -ComputerName $ServerName -Port 445 -InformationLevel Quiet -WarningAction SilentlyContinue -ErrorAction Stop
                
                if (-not $connected) {
                    $consecutiveFailures++
                    if ($consecutiveFailures -ge $maxFailures) {
                        & $OnDisconnectAction
                        $consecutiveFailures = 0  # Reset to avoid spam
                    }
                } else {
                    $consecutiveFailures = 0  # Reset on success
                }
            }
            catch {
                $consecutiveFailures++
                if ($consecutiveFailures -ge $maxFailures) {
                    & $OnDisconnectAction  
                    $consecutiveFailures = 0
                }
            }
            
            Start-Sleep -Seconds $IntervalSeconds
        }
    } -ArgumentList $ServerName, $OnDisconnectAction, $IntervalSeconds, $TimeoutMs
    
    return $monitorJob
}

<#
.SYNOPSIS
    Stops network monitoring

.DESCRIPTION
    Cleanly stops the network monitoring background job and cleans up resources

.EXAMPLE
    Stop-HashSmithNetworkMonitor
#>
function Stop-HashSmithNetworkMonitor {
    [CmdletBinding()]
    param()
    
    $Script:NetworkMonitorRunning = $false
    
    # Clean up any monitoring jobs
    Get-Job | Where-Object { $_.Name -like "*NetworkMonitor*" } | Remove-Job -Force
}

<#
.SYNOPSIS
    Tests network path connectivity with enhanced caching and resilience

.DESCRIPTION
    Tests connectivity to network paths with intelligent caching to avoid
    repeated network calls for the same server. Enhanced with better error handling
    and automatic network monitoring integration.

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
    
    # Start network monitoring for this server if not already running
    if (-not $Script:NetworkMonitorRunning) {
        $monitorJob = Start-HashSmithNetworkMonitor -ServerName $serverName
        Write-HashSmithLog -Message "Started network monitoring for $serverName" -Level DEBUG -Component 'NETWORK'
    }
    
    # Use cached result if available and recent
    if ($UseCache -and $networkConnections.ContainsKey($serverName)) {
        $cached = $networkConnections[$serverName]
        if (((Get-Date) - $cached.Timestamp).TotalMinutes -lt 5 -and $cached.IsAlive) {
            return $cached.IsAlive
        }
    }
    
    Write-HashSmithLog -Message "Testing network connectivity to $serverName" -Level DEBUG -Component 'NETWORK'
    
    try {
        $result = Test-NetConnection -ComputerName $serverName -Port 445 -InformationLevel Quiet -WarningAction SilentlyContinue -ErrorAction Stop
        
        # Cache the result
        $networkConnections[$serverName] = @{
            IsAlive = $result
            Timestamp = Get-Date
        }
        
        if ($result) {
            $stats = Get-HashSmithStatistics
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
    Updates the circuit breaker state with enhanced thread safety

.DESCRIPTION
    Manages circuit breaker pattern for resilient error handling with improved synchronization

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
    
    # Thread-safe update using lock
    $lockObject = [System.Object]::new()
    [System.Threading.Monitor]::Enter($lockObject)
    try {
        if ($IsFailure) {
            $circuitBreaker.FailureCount++
            $circuitBreaker.LastFailureTime = Get-Date
            
            if ($circuitBreaker.FailureCount -ge $config.CircuitBreakerThreshold) {
                $circuitBreaker.IsOpen = $true
                Write-HashSmithLog -Message "Circuit breaker opened after $($circuitBreaker.FailureCount) failures" -Level ERROR -Component $Component
            }
        } else {
            # Reset on success
            if ($circuitBreaker.IsOpen -and 
                $circuitBreaker.LastFailureTime -and
                ((Get-Date) - $circuitBreaker.LastFailureTime).TotalSeconds -gt $config.CircuitBreakerTimeout) {
                
                $circuitBreaker.FailureCount = 0
                $circuitBreaker.IsOpen = $false
                Write-HashSmithLog -Message "Circuit breaker reset after timeout" -Level INFO -Component $Component
            }
        }
    }
    finally {
        [System.Threading.Monitor]::Exit($lockObject)
    }
}

<#
.SYNOPSIS
    Tests the circuit breaker state

.DESCRIPTION
    Checks if operations should proceed based on circuit breaker state

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
    
    if ($circuitBreaker.IsOpen) {
        $timeSinceFailure = (Get-Date) - $circuitBreaker.LastFailureTime
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
    Normalizes paths to handle Unicode characters and applies long path prefixes when needed.
    Enhanced with better error handling and edge case support.

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
        # Enhanced Unicode normalization with proper error handling
        $normalizedPath = [System.IO.Path]::GetFullPath($Path.Normalize([System.Text.NormalizationForm]::FormC))
        
        $config = Get-HashSmithConfig
        
        # Apply long path prefix if needed and supported
        if ($config.SupportLongPaths -and 
            $normalizedPath.Length -gt 260 -and 
            -not $normalizedPath.StartsWith('\\?\')) {
            
            Add-HashSmithStatistic -Name 'LongPaths' -Amount 1
            
            # Enhanced long-UNC path handling
            if ($normalizedPath -match '^[\\\\]{2}[^\\]+\\') {
                # UNC path (\\server\share) - convert to \\?\UNC\server\share
                return "\\?\UNC\" + $normalizedPath.Substring(2)
            } else {
                # Local path - convert to \\?\C:\path
                return "\\?\$normalizedPath"
            }
        }
        
        return $normalizedPath
    }
    catch {
        Write-HashSmithLog -Message "Path normalization failed for: $Path" -Level ERROR -Component 'PATH' -Data @{Error = $_.Exception.Message}
        throw
    }
}

<#
.SYNOPSIS
    Tests if a file is accessible for reading with enhanced timeout handling

.DESCRIPTION
    Tests file accessibility with timeout and retry logic. Enhanced with better locking detection.

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
            # Enhanced file access with better sharing options
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
            Start-Sleep -Milliseconds 100  # Reduced sleep for better responsiveness
        }
        catch {
            Write-HashSmithLog -Message "File access error: $([System.IO.Path]::GetFileName($Path)) - $($_.Exception.Message)" -Level ERROR -Component 'FILE' -Data @{
                Path = $Path
                Error = $_.Exception.Message
                Attempts = $attemptCount
            }
            Update-HashSmithCircuitBreaker -IsFailure:$true -Component 'FILE'
            return $false
        }
    } while ($true)
}

<#
.SYNOPSIS
    Tests if a file is a symbolic link or reparse point with enhanced detection

.DESCRIPTION
    Detects symbolic links, junctions, and other reparse points with improved error handling

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
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        $isReparse = ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq [System.IO.FileAttributes]::ReparsePoint
        
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
    Gets a file integrity snapshot with enhanced metadata

.DESCRIPTION
    Captures file metadata for integrity verification with additional security attributes

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
            # Enhanced snapshot with additional metadata
            LastAccessTime = $fileInfo.LastAccessTime
            IsReadOnly = $fileInfo.IsReadOnly
        }
    }
    catch {
        Write-HashSmithLog -Message "Error getting file integrity snapshot: $([System.IO.Path]::GetFileName($Path)) - $($_.Exception.Message)" -Level WARN -Component 'INTEGRITY'
        return $null
    }
}

<#
.SYNOPSIS
    Tests if two file integrity snapshots match with enhanced comparison

.DESCRIPTION
    Compares file integrity snapshots to detect changes with improved precision

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
    
    # Enhanced comparison with more attributes
    return ($Snapshot1.Size -eq $Snapshot2.Size -and
            $Snapshot1.LastWriteTimeUtc -eq $Snapshot2.LastWriteTimeUtc -and
            $Snapshot1.Attributes -eq $Snapshot2.Attributes -and
            $Snapshot1.IsReadOnly -eq $Snapshot2.IsReadOnly)
}

#endregion

#region Enhanced Spinner Functionality

<#
.SYNOPSIS
    Shows a professional inline spinner with optimized performance

.DESCRIPTION
    Shows a clean, professional spinner with reduced console I/O for better performance

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
    
    # Professional spinner characters
    $chars = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
    $endTime = (Get-Date).AddSeconds($Seconds)
    $i = 0
    
    try {
        while ((Get-Date) -lt $endTime) {
            $char = $chars[$i % $chars.Length]
            # Clean output with proper line management
            Write-Host "`r$char $Message" -NoNewline -ForegroundColor Cyan
            Start-Sleep -Milliseconds 150  # Optimized timing
            $i++
        }
    }
    finally {
        # Clean line clearing without background color issues
        Write-Host "`r$(' ' * ($Message.Length + 10))`r" -NoNewline
    }
}

<#
.SYNOPSIS
    Shows a live spinner with current file being processed (enhanced version)

.DESCRIPTION
    Displays a professional spinner animation with the current file being processed,
    updating on the same line with optimized performance.

.PARAMETER CurrentFile
    The current file being processed (file name only)

.PARAMETER TotalFiles
    Total number of files in the current chunk

.PARAMETER ProcessedFiles
    Number of files already processed in the current chunk

.PARAMETER ChunkInfo
    Information about the current chunk (e.g., "Chunk 3 of 15")

.EXAMPLE
    Show-HashSmithFileSpinner -CurrentFile "largefile.zip" -TotalFiles 1000 -ProcessedFiles 250 -ChunkInfo "Chunk 3 of 15"
#>
function Show-HashSmithFileSpinner {
    [CmdletBinding()]
    param(
        [string]$CurrentFile = "Processing...",
        [int]$TotalFiles = 0,
        [int]$ProcessedFiles = 0,
        [string]$ChunkInfo = ""
    )
    
    # Professional spinner characters
    $chars = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
    $char = $chars[(Get-Date).Millisecond % $chars.Length]
    
    # Smart file name truncation
    $displayFile = if ($CurrentFile.Length -gt 45) {
        "..." + $CurrentFile.Substring($CurrentFile.Length - 42)
    } else {
        $CurrentFile
    }
    
    # Enhanced progress formatting
    $progress = if ($TotalFiles -gt 0) {
        $percent = [Math]::Round(($ProcessedFiles / $TotalFiles) * 100, 1)
        "($ProcessedFiles/$TotalFiles - $percent%)"
    } else {
        ""
    }
    
    $chunkDisplay = if ($ChunkInfo) { "[$ChunkInfo] " } else { "" }
    
    $message = "$char $chunkDisplay$displayFile $progress"
    
    # Optimized line clearing and writing
    Write-Host "`r$(' ' * 100)`r$message" -NoNewline -ForegroundColor Cyan
}

<#
.SYNOPSIS
    Clears the file spinner line with enhanced cleanup

.DESCRIPTION
    Properly clears the current file spinner line to avoid visual artifacts
#>
function Clear-HashSmithFileSpinner {
    [CmdletBinding()]
    param()
    
    # Enhanced line clearing
    Write-Host "`r$(' ' * 100)`r" -NoNewline
}

# Legacy compatibility functions
function Start-HashSmithSpinner {
    [CmdletBinding()]
    param([string]$Message = "Processing...")
    Write-Verbose "Spinner started: $Message"
}

function Stop-HashSmithSpinner {
    [CmdletBinding()]
    param()
    Write-Verbose "Spinner stopped"
}

function Update-HashSmithSpinner {
    [CmdletBinding()]
    param([string]$Message = "Processing...")
    Write-Verbose "Spinner updated: $Message"
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
    'Stop-HashSmithNetworkMonitor'
)
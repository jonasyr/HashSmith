<#
.SYNOPSIS
    Core utilities and helper functions for HashSmith

.DESCRIPTION
    This module provides core utility functions including logging, network path testing,
    circuit breaker patterns, file access testing, and integrity verification.
#>

# Import the configuration module to access script variables
# Note: Dependencies are handled by the main script import order

#region Public Functions

<#
.SYNOPSIS
    Writes enhanced log messages with formatting and structured logging support

.DESCRIPTION
    Provides comprehensive logging with color coding, timestamps, component tagging,
    and structured logging for JSON output.

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
    
    # Enhanced emoji/symbol prefixes
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
    
    # Enhanced color scheme
    $colors = @{
        'DEBUG' = @{ Fore = 'DarkGray'; Back = 'Black' }
        'INFO' = @{ Fore = 'Cyan'; Back = 'Black' }
        'WARN' = @{ Fore = 'Yellow'; Back = 'DarkRed' }
        'ERROR' = @{ Fore = 'White'; Back = 'Red' }
        'SUCCESS' = @{ Fore = 'Black'; Back = 'Green' }
        'PROGRESS' = @{ Fore = 'Magenta'; Back = 'Black' }
        'HEADER' = @{ Fore = 'White'; Back = 'Blue' }
        'STATS' = @{ Fore = 'Green'; Back = 'Black' }
    }
    
    # Format the log entry
    if ($NoTimestamp) {
        $logEntry = "$prefix $Message"
    } else {
        $componentTag = if ($Component -ne 'MAIN') { "[$Component] " } else { "" }
        $logEntry = "[$timestamp] $prefix $componentTag$Message"
    }
    
    # Output with enhanced colors
    $colorConfig = $colors[$Level]
    if ($colorConfig) {
        Write-Host $logEntry -ForegroundColor $colorConfig.Fore -BackgroundColor $colorConfig.Back
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
    Tests network path connectivity with caching

.DESCRIPTION
    Tests connectivity to network paths with intelligent caching to avoid
    repeated network calls for the same server.

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
            $stats.NetworkPaths++
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
    Updates the circuit breaker state

.DESCRIPTION
    Manages circuit breaker pattern for resilient error handling

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
    Normalizes file paths with Unicode and long path support

.DESCRIPTION
    Normalizes paths to handle Unicode characters and applies long path prefixes when needed

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
        # Normalize Unicode and resolve path
        $normalizedPath = [System.IO.Path]::GetFullPath($Path.Normalize([System.Text.NormalizationForm]::FormC))
        
        $config = Get-HashSmithConfig
        $stats = Get-HashSmithStatistics
        
        # Apply long path prefix if needed and supported
        if ($config.SupportLongPaths -and 
            $normalizedPath.Length -gt 260 -and 
            -not $normalizedPath.StartsWith('\\?\')) {
            
            $stats.LongPaths++
            
            # Correct long-UNC normalisation
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
    Tests if a file is accessible for reading

.DESCRIPTION
    Tests file accessibility with timeout and retry logic

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
            # Use FileShare.Read instead of ReadWrite for better locked file access
            $fileStream = [System.IO.File]::Open($normalizedPath, 'Open', 'Read', 'Read')
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
            Start-Sleep -Milliseconds 200
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
    Tests if a file is a symbolic link or reparse point

.DESCRIPTION
    Detects symbolic links, junctions, and other reparse points

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
            $stats = Get-HashSmithStatistics
            $stats.FilesSymlinks++
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
    Gets a file integrity snapshot

.DESCRIPTION
    Captures file metadata for integrity verification

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
        }
    }
    catch {
        Write-HashSmithLog -Message "Error getting file integrity snapshot: $([System.IO.Path]::GetFileName($Path)) - $($_.Exception.Message)" -Level WARN -Component 'INTEGRITY'
        return $null
    }
}

<#
.SYNOPSIS
    Tests if two file integrity snapshots match

.DESCRIPTION
    Compares file integrity snapshots to detect changes

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
    
    return ($Snapshot1.Size -eq $Snapshot2.Size -and
            $Snapshot1.LastWriteTimeUtc -eq $Snapshot2.LastWriteTimeUtc -and
            $Snapshot1.Attributes -eq $Snapshot2.Attributes)
}

#endregion

#region Spinner Functionality

<#
.SYNOPSIS
    Shows a simple inline spinner for a specific duration

.DESCRIPTION
    Shows a visible spinner using manual animation - guaranteed to work

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
    
    $chars = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
    $endTime = (Get-Date).AddSeconds($Seconds)
    $i = 0
    
    try {
        while ((Get-Date) -lt $endTime) {
            $char = $chars[$i % $chars.Length]
            Write-Host "`r$char $Message" -NoNewline -ForegroundColor Yellow
            Start-Sleep -Milliseconds 100
            $i++
        }
    }
    finally {
        Write-Host "`r$(' ' * ($Message.Length + 10))`r" -NoNewline  # Clear line
    }
}

<#
.SYNOPSIS
    Legacy function names for compatibility

.DESCRIPTION
    These are kept for compatibility but just call Show-HashSmithSpinner
#>
function Start-HashSmithSpinner {
    [CmdletBinding()]
    param([string]$Message = "Processing...")
    
    # This is now just a placeholder - the actual spinner is manual
    Write-Verbose "Spinner started: $Message"
}

function Stop-HashSmithSpinner {
    [CmdletBinding()]
    param()
    
    # This is now just a placeholder
    Write-Verbose "Spinner stopped"
}

function Update-HashSmithSpinner {
    [CmdletBinding()]
    param([string]$Message = "Processing...")
    
    # This is now just a placeholder
    Write-Verbose "Spinner updated: $Message"
}

# Keep the demo function for testing
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
    'Show-HashSmithSpinnerDemo'
)

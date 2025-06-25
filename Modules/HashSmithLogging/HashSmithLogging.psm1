<#
.SYNOPSIS
    Enhanced log management for HashSmith

.DESCRIPTION
    This module provides comprehensive logging capabilities including atomic writes,
    batch processing, existing entry parsing, and structured log management.
#>

# Import required modules
# Note: Dependencies are handled by the main script import order

# Script-level variables
$Script:LogBatch = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()

#region Private Functions

<#
.SYNOPSIS
    Gets the global log batch queue

.DESCRIPTION
    Returns the script-level log batch queue, initializing it if necessary.

.EXAMPLE
    $batch = Get-HashSmithLogBatch
#>
function Get-HashSmithLogBatch {
    [CmdletBinding()]
    param()
    
    if ($null -eq $Script:LogBatch) {
        try {
            $Script:LogBatch = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
        } catch {
            Write-Warning "Failed to create LogBatch queue: $($_.Exception.Message)"
            return $null
        }
    }
    
    return $Script:LogBatch
}

#endregion Private Functions

#region Public Functions

<#
.SYNOPSIS
    Initializes a HashSmith log file with comprehensive header

.DESCRIPTION
    Creates a new log file with detailed header information including configuration,
    discovery statistics, and format documentation.

.PARAMETER LogPath
    Path to the log file to initialize

.PARAMETER Algorithm
    Hash algorithm being used

.PARAMETER SourcePath
    Source directory being processed

.PARAMETER DiscoveryStats
    Statistics from file discovery

.PARAMETER Configuration
    Configuration hashtable with processing options

.EXAMPLE
    Initialize-HashSmithLogFile -LogPath $logPath -Algorithm "MD5" -SourcePath $source -DiscoveryStats $stats -Configuration $config
#>
function Initialize-HashSmithLogFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LogPath,
        
        [Parameter(Mandatory)]
        [string]$Algorithm,
        
        [Parameter(Mandatory)]
        [string]$SourcePath,
        
        [Parameter(Mandatory)]
        [hashtable]$DiscoveryStats,
        
        [Parameter(Mandatory)]
        [hashtable]$Configuration
    )
    
    Write-HashSmithLog -Message "Initializing enhanced log file: $LogPath" -Level INFO -Component 'LOG'
    
    # Create directory if needed
    $logDir = Split-Path $LogPath -Parent
    if ($logDir -and -not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }
    
    $config = Get-HashSmithConfig
    
    # Create log file with comprehensive header
    $header = @(
        "# File Integrity Log - HashSmith v$($config.Version)",
        "# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "# Algorithm: $Algorithm",
        "# Source: $SourcePath",
        "# Files Discovered: $($DiscoveryStats.TotalFound)",
        "# Files Skipped: $($DiscoveryStats.TotalSkipped)",
        "# Symbolic Links: $($DiscoveryStats.TotalSymlinks)",
        "# Discovery Errors: $($DiscoveryStats.TotalErrors)",
        "# Discovery Time: $($DiscoveryStats.DiscoveryTime.ToString('F2'))s",
        "# Configuration:",
        "#   Include Hidden: $($Configuration.IncludeHidden)",
        "#   Include Symlinks: $($Configuration.IncludeSymlinks)",
        "#   Verify Integrity: $($Configuration.VerifyIntegrity)",
        "#   Strict Mode: $($Configuration.StrictMode)",
        "#   Max Threads: $($Configuration.MaxThreads)",
        "#   Chunk Size: $($Configuration.ChunkSize)",
        "# Format: RelativePath = Hash, Size: Bytes, Modified: Timestamp, Flags: [S=Symlink,R=RaceCondition,I=IntegrityVerified]",
        ""
    )
    
    $header | Set-Content -Path $LogPath -Encoding UTF8
    Write-HashSmithLog -Message "Enhanced log file initialized with comprehensive header" -Level SUCCESS -Component 'LOG'
}

<#
.SYNOPSIS
    Writes a hash entry to the log file

.DESCRIPTION
    Writes file hash information or error details to the log file with support
    for batch processing and atomic operations.

.PARAMETER LogPath
    Path to the log file

.PARAMETER FilePath
    The file path being logged

.PARAMETER Hash
    The computed hash (for successful entries)

.PARAMETER Size
    File size in bytes

.PARAMETER Modified
    File modification timestamp

.PARAMETER ErrorMessage
    Error message (for failed entries)

.PARAMETER BasePath
    Base path for creating relative paths

.PARAMETER ErrorCategory
    Category of error for failed entries

.PARAMETER IsSymlink
    Whether the file is a symbolic link

.PARAMETER RaceConditionDetected
    Whether a race condition was detected

.PARAMETER IntegrityVerified
    Whether integrity verification was performed

.PARAMETER UseBatching
    Use batch processing for better performance

.EXAMPLE
    Write-HashSmithHashEntry -LogPath $logPath -FilePath $file -Hash $hash -Size $size -Modified $modified -UseBatching
#>
function Write-HashSmithHashEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LogPath,
        
        [Parameter(Mandatory)]
        [string]$FilePath,
        
        [string]$Hash,
        
        [Parameter(Mandatory)]
        [long]$Size,
        
        [Parameter(Mandatory)]
        [DateTime]$Modified,
        
        [string]$ErrorMessage,
        
        [string]$BasePath,
        
        [string]$ErrorCategory = 'Unknown',
        
        [bool]$IsSymlink = $false,
        
        [bool]$RaceConditionDetected = $false,
        
        [bool]$IntegrityVerified = $false,
        
        [switch]$UseBatching
    )
    
    # Create relative path for cleaner logs
    $relativePath = $FilePath
    if ($BasePath -and $FilePath.StartsWith($BasePath)) {
        $relativePath = $FilePath.Substring($BasePath.Length).TrimStart('\', '/')
    }
    
    # Build flags
    $flags = @()
    if ($IsSymlink) { $flags += 'S' }
    if ($RaceConditionDetected) { $flags += 'R' }
    if ($IntegrityVerified) { $flags += 'I' }
    $flagString = if ($flags.Count -gt 0) { " [$(($flags -join ','))]" } else { "" }
    
    # Format entry
    if ($ErrorMessage) {
        $logEntry = "$relativePath = ERROR($ErrorCategory): $ErrorMessage, Size: $Size, Modified: $($Modified.ToString('yyyy-MM-dd HH:mm:ss'))$flagString"
    } else {
        $logEntry = "$relativePath = $Hash, Size: $Size, Modified: $($Modified.ToString('yyyy-MM-dd HH:mm:ss'))$flagString"
    }
    
    if ($UseBatching) {
        # Add to batch queue
        $logBatch = Get-HashSmithLogBatch
        if ($null -ne $logBatch) {
            $logBatch.Enqueue($logEntry)
            
            # Flush batch if it gets too large
            if ($logBatch.Count -ge 100) {
                Clear-HashSmithLogBatch -LogPath $LogPath
            }
        } else {
            # Fallback to direct write if batch is null
            Write-HashSmithLogEntryAtomic -LogPath $LogPath -Entry $logEntry
        }
    } else {
        # Write immediately with atomic operation
        Write-HashSmithLogEntryAtomic -LogPath $LogPath -Entry $logEntry
    }
}

<#
.SYNOPSIS
    Writes a log entry atomically to prevent corruption

.DESCRIPTION
    Performs atomic write operations to the log file using file locking
    to prevent corruption during concurrent access.

.PARAMETER LogPath
    Path to the log file

.PARAMETER Entry
    The log entry to write

.EXAMPLE
    Write-HashSmithLogEntryAtomic -LogPath $logPath -Entry $logEntry
#>
function Write-HashSmithLogEntryAtomic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LogPath,
        
        [Parameter(Mandatory)]
        [string]$Entry
    )
    
    $maxAttempts = 5
    $attempt = 0
    
    do {
        $attempt++
        try {
            $lockFile = "$LogPath.lock"
            $lockStream = [System.IO.File]::Create($lockFile)
            
            try {
                # Write to main log
                Add-Content -Path $LogPath -Value $Entry -Encoding UTF8
                return
            } finally {
                $lockStream.Close()
                Remove-Item -Path $lockFile -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
            if ($attempt -ge $maxAttempts) {
                Write-HashSmithLog -Message "Failed to write log entry after $maxAttempts attempts: $($_.Exception.Message)" -Level ERROR -Component 'LOG'
                throw
            }
            Start-Sleep -Milliseconds (100 * $attempt)
        }
    } while ($attempt -lt $maxAttempts)
}

<#
.SYNOPSIS
    Flushes the log batch queue to the log file

.DESCRIPTION
    Writes all queued log entries to the log file in a single atomic operation
    for improved performance and consistency.

.PARAMETER LogPath
    Path to the log file

.EXAMPLE
    Clear-HashSmithLogBatch -LogPath $logPath
#>
function Clear-HashSmithLogBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LogPath
    )
    
    $logBatch = Get-HashSmithLogBatch
    
    if ($logBatch.Count -eq 0) {
        return
    }
    
    $entries = @()
    $entry = $null
    while ($logBatch.TryDequeue([ref]$entry)) {
        $entries += $entry
    }
    
    if ($entries.Count -gt 0) {
        try {
            $entries | Add-Content -Path $LogPath -Encoding UTF8
            Write-HashSmithLog -Message "Flushed $($entries.Count) log entries" -Level DEBUG -Component 'LOG'
        }
        catch {
            Write-HashSmithLog -Message "Failed to flush log batch: $($_.Exception.Message)" -Level ERROR -Component 'LOG'
            # Re-queue failed entries
            foreach ($entry in $entries) {
                $logBatch.Enqueue($entry)
            }
            throw
        }
    }
}

<#
.SYNOPSIS
    Loads existing entries from a log file

.DESCRIPTION
    Parses an existing log file to extract processed and failed entries
    for resume and error recovery operations.

.PARAMETER LogPath
    Path to the log file to parse

.EXAMPLE
    $entries = Get-HashSmithExistingEntries -LogPath $logPath
#>
function Get-HashSmithExistingEntries {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$LogPath
    )
    
    $entries = @{
        Processed = @{}
        Failed = @{}
        Statistics = @{
            ProcessedCount = 0
            FailedCount = 0
            SymlinkCount = 0
            RaceConditionCount = 0
            IntegrityVerifiedCount = 0
        }
    }
    
    if (-not (Test-Path $LogPath)) {
        return $entries
    }
    
    Write-HashSmithLog -Message "Loading existing log entries from: $LogPath" -Level INFO -Component 'LOG'
    
    try {
        $lines = Get-Content $LogPath -Encoding UTF8
        
        foreach ($line in $lines) {
            # Skip comments and empty lines
            if ($line.StartsWith('#') -or [string]::IsNullOrWhiteSpace($line)) {
                continue
            }
            
            # Parse successful entries with flags: path = hash, size: bytes, modified: timestamp [flags]
            if ($line -match '^(.+?)\s*=\s*([a-fA-F0-9]+)\s*,\s*Size:\s*(\d+)\s*,\s*Modified:\s*(.+?)(?:\s*\[([^\]]+)\])?$') {
                $path = $matches[1]
                $hash = $matches[2]
                $size = [long]$matches[3]
                $modified = [DateTime]::ParseExact($matches[4], 'yyyy-MM-dd HH:mm:ss', $null)
                $flags = if ($matches[5]) { $matches[5].Split(',') } else { @() }
                
                $entries.Processed[$path] = @{
                    Hash = $hash
                    Size = $size
                    Modified = $modified
                    IsSymlink = $flags -contains 'S'
                    RaceConditionDetected = $flags -contains 'R'
                    IntegrityVerified = $flags -contains 'I'
                }
                
                $entries.Statistics.ProcessedCount++
                if ($flags -contains 'S') { $entries.Statistics.SymlinkCount++ }
                if ($flags -contains 'R') { $entries.Statistics.RaceConditionCount++ }
                if ($flags -contains 'I') { $entries.Statistics.IntegrityVerifiedCount++ }
            }
            # Parse error entries with category: path = ERROR(category): message, size: bytes, modified: timestamp [flags]
            elseif ($line -match '^(.+?)\s*=\s*ERROR\(([^)]+)\):\s*(.+?)\s*,\s*Size:\s*(\d+)\s*,\s*Modified:\s*(.+?)(?:\s*\[([^\]]+)\])?$') {
                $path = $matches[1]
                $category = $matches[2]
                $errorMessage = $matches[3]
                $size = [long]$matches[4]
                $modified = [DateTime]::ParseExact($matches[5], 'yyyy-MM-dd HH:mm:ss', $null)
                $flags = if ($matches[6]) { $matches[6].Split(',') } else { @() }
                
                $entries.Failed[$path] = @{
                    Error = $errorMessage
                    ErrorCategory = $category
                    Size = $size
                    Modified = $modified
                    IsSymlink = $flags -contains 'S'
                    RaceConditionDetected = $flags -contains 'R'
                }
                
                $entries.Statistics.FailedCount++
            }
        }
        
        Write-HashSmithLog -Message "Loaded $($entries.Statistics.ProcessedCount) processed entries and $($entries.Statistics.FailedCount) failed entries" -Level SUCCESS -Component 'LOG'
        Write-HashSmithLog -Message "Special entries: $($entries.Statistics.SymlinkCount) symlinks, $($entries.Statistics.RaceConditionCount) race conditions, $($entries.Statistics.IntegrityVerifiedCount) integrity verified" -Level INFO -Component 'LOG'
        
    }
    catch {
        Write-HashSmithLog -Message "Error reading existing log file: $($_.Exception.Message)" -Level ERROR -Component 'LOG'
        throw
    }
    
    return $entries
}

#endregion

# Export public functions
Export-ModuleMember -Function @(
    'Initialize-HashSmithLogFile',
    'Write-HashSmithHashEntry',
    'Write-HashSmithLogEntryAtomic',
    'Clear-HashSmithLogBatch',
    'Get-HashSmithExistingEntries'
)

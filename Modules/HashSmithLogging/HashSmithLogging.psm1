<#
.SYNOPSIS
    Enhanced log management for HashSmith - Simplified and Reliable

.DESCRIPTION
    This module provides fast logging capabilities with:
    - High-performance batch processing without timer complications
    - Thread-safe atomic write operations
    - Memory-efficient log parsing for large files
    - Enhanced error recovery and corruption detection
    - Simple, reliable architecture
#>

# Script-level variables for performance
$Script:LogBatch = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
$Script:BatchFlushSize = 500
$Script:LogWriteLock = [System.Object]::new()

#region Simple Batch Processing

<#
.SYNOPSIS
    Simple batch processor without timer complications
#>
function Add-ToBatch {
    [CmdletBinding()]
    param(
        [string]$LogPath,
        [string]$Entry
    )
    
    $Script:LogBatch.Enqueue($Entry)
    
    # Simple threshold-based flushing
    if ($Script:LogBatch.Count -ge $Script:BatchFlushSize) {
        Flush-LogBatch -LogPath $LogPath
    }
}

<#
.SYNOPSIS
    Flushes the log batch safely
#>
function Flush-LogBatch {
    [CmdletBinding()]
    param(
        [string]$LogPath
    )
    
    if ($Script:LogBatch.Count -eq 0) { return }
    
    $entries = [System.Collections.Generic.List[string]]::new()
    $entry = ""
    
    # Collect all queued entries
    while ($Script:LogBatch.TryDequeue([ref]$entry) -and $entries.Count -lt 1000) {
        $entries.Add($entry)
    }
    
    if ($entries.Count -eq 0) { return }
    
    # Thread-safe write
    [System.Threading.Monitor]::Enter($Script:LogWriteLock)
    try {
        $content = $entries -join [Environment]::NewLine
        if ($content) {
            $content += [Environment]::NewLine
            [System.IO.File]::AppendAllText($LogPath, $content, [System.Text.Encoding]::UTF8)
        }
        Write-Verbose "Batch flushed: $($entries.Count) entries"
    }
    catch {
        # Re-queue failed entries
        foreach ($failedEntry in $entries) {
            $Script:LogBatch.Enqueue($failedEntry)
        }
        Write-Warning "Batch flush failed: $($_.Exception.Message)"
        throw
    }
    finally {
        [System.Threading.Monitor]::Exit($Script:LogWriteLock)
    }
}

#endregion

#region Public Functions

<#
.SYNOPSIS
    Initializes a HashSmith log file with header information

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
    
    Write-HashSmithLog -Message "Initializing log file: $LogPath" -Level INFO -Component 'LOG'
    
    # Create directory if needed
    $logDir = Split-Path $LogPath -Parent
    if ($logDir -and -not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }
    
    $config = Get-HashSmithConfig
    
    # Create log file header
    $header = @(
        "# HashSmith v$($config.Version) - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "# Algorithm: $Algorithm | Source: $SourcePath",
        "# Discovery: $($DiscoveryStats.TotalFound) files found, $($DiscoveryStats.TotalSkipped) skipped, $($DiscoveryStats.TotalSymlinks) symlinks",
        "# Performance: $($DiscoveryStats.DiscoveryTime.ToString('F2'))s discovery, $($DiscoveryStats.FilesPerSecond) files/sec",
        "# Configuration: Threads=$($Configuration.MaxParallelJobs), ChunkSize=$($Configuration.ChunkSize)",
        ""
    )
    
    # Write header
    try {
        $headerText = $header -join "`n"
        [System.IO.File]::WriteAllText($LogPath, $headerText, [System.Text.Encoding]::UTF8)
        Write-HashSmithLog -Message "Log file initialized successfully" -Level SUCCESS -Component 'LOG'
    }
    catch {
        Write-HashSmithLog -Message "Failed to initialize log file: $($_.Exception.Message)" -Level ERROR -Component 'LOG'
        throw
    }
}

<#
.SYNOPSIS
    Writes hash entry with batch processing

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
    Use batch processing for better performance (default: true)

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
    
    # Use full path as specified
    $loggedPath = $FilePath
    
    # Format entry
    $logEntry = if ($ErrorMessage) {
        "$loggedPath = ERROR($ErrorCategory): $ErrorMessage, size: $Size"
    } else {
        "$loggedPath = $Hash, size: $Size"
    }
    
    if ($UseBatching) {
        Add-ToBatch -LogPath $LogPath -Entry $logEntry
    } else {
        Write-HashSmithLogEntryAtomic -LogPath $LogPath -Entry $logEntry
    }
}

<#
.SYNOPSIS
    Writes log entry atomically

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
    
    $maxAttempts = 3
    $attempt = 0
    
    do {
        $attempt++
        try {
            [System.Threading.Monitor]::Enter($Script:LogWriteLock)
            try {
                $entryWithNewline = $Entry + [Environment]::NewLine
                [System.IO.File]::AppendAllText($LogPath, $entryWithNewline, [System.Text.Encoding]::UTF8)
                return
            }
            finally {
                [System.Threading.Monitor]::Exit($Script:LogWriteLock)
            }
        }
        catch [System.IO.IOException] {
            if ($attempt -ge $maxAttempts) {
                Write-HashSmithLog -Message "Failed to write log entry after $maxAttempts attempts: $($_.Exception.Message)" -Level ERROR -Component 'LOG'
                throw
            }
            
            $delay = 50 * $attempt
            Start-Sleep -Milliseconds $delay
        }
        catch {
            Write-HashSmithLog -Message "Unexpected error writing log entry: $($_.Exception.Message)" -Level ERROR -Component 'LOG'
            throw
        }
    } while ($attempt -lt $maxAttempts)
}

<#
.SYNOPSIS
    Flushes log batch

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
    
    try {
        Flush-LogBatch -LogPath $LogPath
        Write-Verbose "Manual batch flush completed"
    }
    catch {
        Write-HashSmithLog -Message "Failed to flush log batch: $($_.Exception.Message)" -Level ERROR -Component 'LOG'
        throw
    }
}

<#
.SYNOPSIS
    Loads existing entries with optimized parsing

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
        Processed = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
        Failed = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
        Statistics = @{
            ProcessedCount = 0
            FailedCount = 0
            ParseTime = 0
            LinesPerSecond = 0
        }
    }
    
    if (-not (Test-Path $LogPath)) {
        return $entries
    }
    
    Write-HashSmithLog -Message "Loading existing log entries: $LogPath" -Level INFO -Component 'LOG'
    
    $parseStart = Get-Date
    
    try {
        $fileInfo = Get-Item $LogPath
        $fileSize = $fileInfo.Length
        Write-Host "📖 Parsing log file ($([Math]::Round($fileSize / 1MB, 2)) MB)..." -ForegroundColor Cyan
        
        # Use appropriate parser based on file size
        if ($fileSize -gt 50MB) {
            Read-LogFileStreaming -LogPath $LogPath -Entries $entries
        } else {
            Read-LogFileOptimized -LogPath $LogPath -Entries $entries
        }
        
        $parseTime = (Get-Date) - $parseStart
        $entries.Statistics.ParseTime = $parseTime.TotalSeconds
        
        $totalLines = $entries.Statistics.ProcessedCount + $entries.Statistics.FailedCount
        if ($parseTime.TotalSeconds -gt 0) {
            $entries.Statistics.LinesPerSecond = [Math]::Round($totalLines / $parseTime.TotalSeconds, 0)
        }
        
        Write-Host "✅ Parsing completed in $($parseTime.TotalSeconds.ToString('F1'))s" -ForegroundColor Green
        Write-Host "   📊 Performance: $($entries.Statistics.LinesPerSecond) lines/second" -ForegroundColor Gray
        
        Write-HashSmithLog -Message "Parsing: $($entries.Statistics.ProcessedCount) processed, $($entries.Statistics.FailedCount) failed in $($parseTime.TotalSeconds.ToString('F2'))s" -Level SUCCESS -Component 'LOG'
        
    }
    catch {
        Write-HashSmithLog -Message "Log parsing failed: $($_.Exception.Message)" -Level ERROR -Component 'LOG'
        throw
    }
    
    return $entries
}

<#
.SYNOPSIS
    Optimized log file reader for medium files
#>
function Read-LogFileOptimized {
    [CmdletBinding()]
    param(
        [string]$LogPath,
        [hashtable]$Entries
    )
    
    $allLines = [System.IO.File]::ReadAllLines($LogPath, [System.Text.Encoding]::UTF8)
    $lineCount = 0
    
    foreach ($line in $allLines) {
        $lineCount++
        
        # Progress update every 5000 lines
        if ($lineCount % 5000 -eq 0) {
            $percent = [Math]::Round(($lineCount / $allLines.Count) * 100, 1)
            Write-Host "`r   Processing: $lineCount lines ($percent%)" -NoNewline -ForegroundColor Gray
        }
        
        # Skip comments and empty lines
        if ($line.StartsWith('#') -or [string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        
        Parse-LogLine -Line $line -Entries $Entries
    }
    
    Write-Host "`r$(' ' * 50)`r" -NoNewline  # Clear progress
}

<#
.SYNOPSIS
    Streaming log file reader for large files
#>
function Read-LogFileStreaming {
    [CmdletBinding()]
    param(
        [string]$LogPath,
        [hashtable]$Entries
    )
    
    $reader = [System.IO.StreamReader]::new($LogPath, [System.Text.Encoding]::UTF8, $true, 65536)
    $lineCount = 0
    
    try {
        while (($line = $reader.ReadLine()) -ne $null) {
            $lineCount++
            
            # Progress update
            if ($lineCount % 10000 -eq 0) {
                $bytesRead = $reader.BaseStream.Position
                $fileSize = $reader.BaseStream.Length
                $percent = if ($fileSize -gt 0) { [Math]::Round(($bytesRead / $fileSize) * 100, 1) } else { 0 }
                Write-Host "`r   Streaming: $lineCount lines ($percent%)" -NoNewline -ForegroundColor Gray
            }
            
            # Skip comments and empty lines
            if ($line.StartsWith('#') -or [string]::IsNullOrWhiteSpace($line)) {
                continue
            }
            
            Parse-LogLine -Line $line -Entries $Entries
        }
    }
    finally {
        $reader.Close()
        $reader.Dispose()
        Write-Host "`r$(' ' * 50)`r" -NoNewline  # Clear progress
    }
}

<#
.SYNOPSIS
    Fast log line parser
#>
function Parse-LogLine {
    [CmdletBinding()]
    param(
        [string]$Line,
        [hashtable]$Entries
    )
    
    if ($Line -match '^(.+?)\s*=\s*([a-fA-F0-9]+)\s*,\s*size:\s*(\d+)$') {
        # Successful entry
        $path = $matches[1]
        $hash = $matches[2]
        $size = [long]$matches[3]
        
        $entry = @{
            Hash = $hash
            Size = $size
            Modified = [DateTime]::MinValue
            IsSymlink = $false
            RaceConditionDetected = $false
            IntegrityVerified = $false
        }
        
        $Entries.Processed.TryAdd($path, $entry) | Out-Null
        [System.Threading.Interlocked]::Increment([ref]$Entries.Statistics.ProcessedCount) | Out-Null
    }
    elseif ($Line -match '^(.+?)\s*=\s*ERROR\(([^)]+)\):\s*(.+?)\s*,\s*size:\s*(\d+)$') {
        # Error entry
        $path = $matches[1]
        $category = $matches[2]
        $errorMessage = $matches[3]
        $size = [long]$matches[4]
        
        $entry = @{
            Error = $errorMessage
            ErrorCategory = $category
            Size = $size
            Modified = [DateTime]::MinValue
            IsSymlink = $false
            RaceConditionDetected = $false
        }
        
        $Entries.Failed.TryAdd($path, $entry) | Out-Null
        [System.Threading.Interlocked]::Increment([ref]$Entries.Statistics.FailedCount) | Out-Null
    }
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
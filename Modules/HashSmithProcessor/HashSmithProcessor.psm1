<#
.SYNOPSIS
    Main file processing orchestration for HashSmith

.DESCRIPTION
    This module orchestrates the main file processing workflow with parallel execution,
    progress tracking, error handling, and comprehensive result management.
#>

# Import required modules
# Note: Dependencies are handled by the main script import order

#region Public Functions

<#
.SYNOPSIS
    Processes files with enhanced parallel execution and error handling

.DESCRIPTION
    Orchestrates the main file processing workflow with chunked processing,
    parallel execution (PowerShell 7+), progress tracking, and comprehensive
    error handling and recovery.

.PARAMETER Files
    Array of FileInfo objects to process

.PARAMETER LogPath
    Path to the log file for results

.PARAMETER Algorithm
    Hash algorithm to use

.PARAMETER ExistingEntries
    Previously processed entries for resume operations

.PARAMETER BasePath
    Base path for creating relative paths

.PARAMETER StrictMode
    Enable strict mode with maximum validation

.PARAMETER VerifyIntegrity
    Enable integrity verification

.PARAMETER MaxThreads
    Maximum number of parallel threads

.PARAMETER ChunkSize
    Number of files to process per chunk

.PARAMETER RetryCount
    Number of retry attempts

.PARAMETER TimeoutSeconds
    Timeout for file operations

.PARAMETER ShowProgress
    Show progress information

.PARAMETER UseParallel
    Use parallel processing (PowerShell 7+ only)

.EXAMPLE
    $hashes = Start-HashSmithFileProcessing -Files $files -LogPath $log -Algorithm "SHA256" -BasePath $base
#>
function Start-HashSmithFileProcessing {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo[]]$Files,
        
        [Parameter(Mandatory)]
        [string]$LogPath,
        
        [Parameter(Mandatory)]
        [ValidateSet('MD5', 'SHA1', 'SHA256', 'SHA512')]
        [string]$Algorithm,
        
        [hashtable]$ExistingEntries = @{},
        
        [string]$BasePath,
        
        [switch]$StrictMode,
        
        [switch]$VerifyIntegrity,
        
        [ValidateRange(1, 64)]
        [int]$MaxThreads = [Environment]::ProcessorCount,
        
        [ValidateRange(100, 5000)]
        [int]$ChunkSize = 1000,
        
        [ValidateRange(1, 10)]
        [int]$RetryCount = 3,
        
        [ValidateRange(10, 300)]
        [int]$TimeoutSeconds = 30,
        
        [switch]$ShowProgress,
        
        [switch]$UseParallel
    )
    
    Write-HashSmithLog -Message "Starting enhanced file processing with $($Files.Count) files" -Level INFO -Component 'PROCESS'
    Write-HashSmithLog -Message "Algorithm: $Algorithm, Strict Mode: $StrictMode, Verify Integrity: $VerifyIntegrity" -Level INFO -Component 'PROCESS'
    
    # Log parallel processing status (only once)
    $safeThreads = if ($UseParallel -and $PSVersionTable.PSVersion.Major -ge 7) {
        $threads = [Math]::Round([Environment]::ProcessorCount * 0.7)
        if ($threads -lt 1) { $threads = 1 }
        [Math]::Min($MaxThreads, $threads)
    } else {
        1
    }
    
    if ($UseParallel -and $PSVersionTable.PSVersion.Major -ge 7) {
        Write-HashSmithLog -Message "Parallel processing enabled: $safeThreads threads (reduced from $MaxThreads for stability)" -Level INFO -Component 'PROCESS'
    } elseif ($UseParallel) {
        Write-HashSmithLog -Message "Parallel processing requested but using sequential processing (PowerShell 5.1)" -Level WARNING -Component 'PROCESS'
    } else {
        Write-HashSmithLog -Message "Sequential processing (parallel disabled)" -Level INFO -Component 'PROCESS'
    }
    
    $processedCount = 0
    $errorCount = 0
    $totalBytes = 0
    $fileHashes = @{}
    $lastProgressUpdate = Get-Date
    $stats = Get-HashSmithStatistics
    
    # Get configuration values for parallel processing
    $config = Get-HashSmithConfig
    
    # Process files in chunks for memory efficiency
    for ($i = 0; $i -lt $Files.Count; $i += $ChunkSize) {
        $endIndex = [Math]::Min($i + $ChunkSize - 1, $Files.Count - 1)
        $chunk = $Files[$i..$endIndex]
        $chunkNumber = [Math]::Floor($i / $ChunkSize) + 1
        $totalChunks = [Math]::Ceiling($Files.Count / $ChunkSize)
        
        Write-HashSmithLog -Message "Processing chunk $chunkNumber of $totalChunks ($($chunk.Count) files)" -Level PROGRESS -Component 'PROCESS'
        
        # Initialize chunk timing for all processing paths
        $chunkStartTime = Get-Date
        
        # Test network connectivity before processing chunk
        if (-not (Test-HashSmithNetworkPath -Path $BasePath -UseCache)) {
            Write-HashSmithLog -Message "Network connectivity lost, aborting chunk processing" -Level ERROR -Component 'PROCESS'
            break
        }
        
        # Guard parallel processing behind PowerShell version check
        if ($UseParallel -and $PSVersionTable.PSVersion.Major -ge 7) {
            # Initialize progress tracking variables
            $totalChunkFiles = $chunk.Count
            $lastProgressCount = 0
            $lastProgressTime = Get-Date
            
            # Process files with parallel jobs and show live progress
            $chunkResults = $chunk | ForEach-Object -Parallel {
                # Import required variables into parallel runspace
                $Algorithm = $using:Algorithm
                $RetryCount = $using:RetryCount
                
                # Process single file with minimal complexity
                $file = $_
                $result = @{
                    Path = $file.FullName
                    Size = $file.Length
                    Modified = $file.LastWriteTime
                    Success = $false
                    Hash = $null
                    Error = $null
                    ErrorCategory = 'Unknown'
                    Duration = 0
                    IsSymlink = $false
                    RaceConditionDetected = $false
                    IntegrityVerified = $false
                    Attempts = 1
                    FileName = $file.Name
                }
                
                $startTime = Get-Date
                
                try {
                    # Simple hash computation without complex retry logic
                    $hashAlgorithm = [System.Security.Cryptography.HashAlgorithm]::Create($Algorithm)
                    try {
                        $fileBytes = [System.IO.File]::ReadAllBytes($file.FullName)
                        $hashBytes = $hashAlgorithm.ComputeHash($fileBytes)
                        $result.Hash = [System.BitConverter]::ToString($hashBytes) -replace '-', ''
                        $result.Hash = $result.Hash.ToLower()
                        $result.Success = $true
                        
                        # Small delay to reduce system strain and prevent freezes
                        Start-Sleep -Milliseconds 75
                    }
                    finally {
                        if ($hashAlgorithm) { $hashAlgorithm.Dispose() }
                    }
                }
                catch {
                    $result.Error = $_.Exception.Message
                    $result.ErrorCategory = 'ProcessingError'
                }
                
                $result.Duration = (Get-Date) - $startTime
                return $result
                
            } -ThrottleLimit $safeThreads -AsJob
            
            # Show real-time progress while jobs are running
            $spinChars = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
            $spinIndex = 0
            
            # Monitor the parallel jobs and show progress with smart timeout
            while ($chunkResults.State -eq 'Running') {
                $char = $spinChars[$spinIndex % $spinChars.Length]
                $elapsed = (Get-Date) - $chunkStartTime
                $elapsedStr = if ($elapsed.TotalMinutes -gt 1) { 
                    "$([Math]::Floor($elapsed.TotalMinutes))m $([Math]::Floor($elapsed.Seconds))s" 
                } else { 
                    "$([Math]::Floor($elapsed.TotalSeconds))s" 
                }
                
                # Try to estimate progress by checking completed results
                $currentResults = @()
                try {
                    $currentResults = @(Receive-Job $chunkResults -Keep -ErrorAction SilentlyContinue)
                } catch {
                    # Ignore errors when checking job progress
                }
                
                $completedCount = $currentResults.Count
                $progressPercent = if ($totalChunkFiles -gt 0) { 
                    [Math]::Round(($completedCount / $totalChunkFiles) * 100, 1) 
                } else { 0 }
                
                # Smart timeout logic - check for progress, not just time
                $timeSinceLastProgress = (Get-Date) - $lastProgressTime
                if ($completedCount -gt $lastProgressCount) {
                    $lastProgressCount = $completedCount
                    $lastProgressTime = Get-Date
                } elseif ($timeSinceLastProgress.TotalMinutes -gt 20) {
                    # Only timeout if no progress for 20 minutes
                    Write-Host "`r⚠️  No progress for 20 minutes, stopping chunk..." -ForegroundColor Red
                    Stop-Job $chunkResults -ErrorAction SilentlyContinue
                    break
                }
                
                # Create a more compact progress message
                $progressMsg = "$char Chunk $chunkNumber/$totalChunks | $completedCount/$totalChunkFiles ($progressPercent%) | $elapsedStr"
                Write-Host "`r$progressMsg$(' ' * 10)" -NoNewline -ForegroundColor Yellow
                
                Start-Sleep -Milliseconds 200
                $spinIndex++
            }
            
            # Get the final results
            try {
                $chunkResults = Receive-Job $chunkResults -Wait -ErrorAction Stop
                Remove-Job $chunkResults -Force -ErrorAction SilentlyContinue
            }
            catch {
                Write-HashSmithLog -Message "Error retrieving parallel job results: $($_.Exception.Message)" -Level ERROR -Component 'PROCESS'
                $chunkResults = @()
            }
            
            # Clear the progress line
            Write-Host "`r$(' ' * 80)`r" -NoNewline
        } else {
            # Process chunk sequentially (PowerShell 5.1 or parallel disabled)
            $chunkResults = @()
            $chunkFileCount = 0
            foreach ($file in $chunk) {
                $chunkFileCount++
                
                # Show spinner with current file being processed
                $fileName = Split-Path $file.FullName -Leaf
                $chunkInfo = "Chunk $chunkNumber of $totalChunks"
                Show-HashSmithFileSpinner -CurrentFile $fileName -TotalFiles $chunk.Count -ProcessedFiles $chunkFileCount -ChunkInfo $chunkInfo
                
                $result = Get-HashSmithFileHashSafe -Path $file.FullName -Algorithm $Algorithm -RetryCount $RetryCount -TimeoutSeconds $TimeoutSeconds -VerifyIntegrity:$VerifyIntegrity -StrictMode:$StrictMode -PreIntegritySnapshot $file.IntegritySnapshot
                
                # Add additional properties expected by the result processor and fix property mapping
                $result.Path = $file.FullName
                $result.Size = $file.Length
                $result.Modified = $file.LastWriteTime
                $result.IsSymlink = Test-HashSmithSymbolicLink -Path $file.FullName
                
                # Map hash function result properties to expected processor properties
                if (-not $result.ContainsKey('IntegrityVerified')) {
                    $result.IntegrityVerified = if ($result.ContainsKey('Integrity')) { [bool]$result.Integrity } else { $false }
                }
                
                $chunkResults += $result
                
                # Add small delay to reduce system load and prevent freezes
                Start-Sleep -Milliseconds 50
            }
            
            # Clear the spinner line after chunk completion
            Clear-HashSmithFileSpinner
        }
        
        # Write results and update statistics
        foreach ($result in $chunkResults) {
            $processedCount++
            
            if ($result.Success) {
                # Write to log with error handling
                try {
                    Write-HashSmithHashEntry -LogPath $LogPath -FilePath $result.Path -Hash $result.Hash -Size $result.Size -Modified $result.Modified -BasePath $BasePath -IsSymlink $result.IsSymlink -RaceConditionDetected $result.RaceConditionDetected -IntegrityVerified $result.IntegrityVerified -UseBatching
                }
                catch {
                    Write-HashSmithLog -Message "Failed to write log entry for $($result.Path): $($_.Exception.Message)" -Level WARN -Component 'PROCESS'
                }
                
                # Store for directory hash
                $fileHashes[$result.Path] = @{
                    Hash = $result.Hash
                    Size = $result.Size
                    IsSymlink = $result.IsSymlink
                    RaceConditionDetected = $result.RaceConditionDetected
                    IntegrityVerified = $result.IntegrityVerified
                }
                
                $totalBytes += $result.Size
                Add-HashSmithStatistic -Name 'FilesProcessed' -Amount 1
                Add-HashSmithStatistic -Name 'BytesProcessed' -Amount $result.Size
                
                if ($result.RaceConditionDetected) {
                    Add-HashSmithStatistic -Name 'FilesRaceCondition' -Amount 1
                }
            } else {
                # Write error to log with error handling
                try {
                    Write-HashSmithHashEntry -LogPath $LogPath -FilePath $result.Path -Size $result.Size -Modified $result.Modified -ErrorMessage $result.Error -ErrorCategory $result.ErrorCategory -BasePath $BasePath -IsSymlink $result.IsSymlink -RaceConditionDetected $result.RaceConditionDetected -UseBatching
                }
                catch {
                    Write-HashSmithLog -Message "Failed to write error log entry for $($result.Path): $($_.Exception.Message)" -Level WARN -Component 'PROCESS'
                }
                
                $errorCount++
                Add-HashSmithStatistic -Name 'FilesError' -Amount 1
                
                # Categorize errors
                if ($result.ErrorCategory -in @('IO', 'Unknown')) {
                    Add-HashSmithStatistic -Name 'RetriableErrors' -Amount 1
                } else {
                    Add-HashSmithStatistic -Name 'NonRetriableErrors' -Amount 1
                }
            }
            
            # Update progress with enhanced single-line display
            if ($ShowProgress -and ((Get-Date) - $lastProgressUpdate).TotalSeconds -ge 1) {
                $percent = [Math]::Round(($processedCount / $Files.Count) * 100, 1)
                
                $throughput = if ($totalBytes -gt 0) { ($totalBytes / 1MB) / ((Get-Date) - $stats.StartTime).TotalSeconds } else { 0 }
                $eta = if ($percent -gt 0) { 
                    $elapsed = ((Get-Date) - $stats.StartTime).TotalSeconds
                    $remaining = ($elapsed / $percent) * (100 - $percent)
                    if ($remaining -gt 60) { "$([Math]::Floor($remaining / 60))m $([Math]::Floor($remaining % 60))s" } else { "$([Math]::Floor($remaining))s" }
                } else { "calculating..." }
                
                $progressMessage = "⚡ Processing: $($processedCount)/$($Files.Count) files ($($percent)%) | $($throughput.ToString('F1')) MB/s | ETA: $eta | Errors: $errorCount"
                Write-Host "`r$progressMessage" -NoNewline -ForegroundColor Green
                
                $lastProgressUpdate = Get-Date
            }
        }
        
        # Flush log batch periodically
        Clear-HashSmithLogBatch -LogPath $LogPath
        
        # Add a brief pause between chunks to reduce system load and prevent freezes
        if ($chunkNumber -lt $totalChunks) {
            $chunkElapsed = (Get-Date) - $chunkStartTime
            $filesPerSecond = if ($chunkElapsed.TotalSeconds -gt 0) { $chunk.Count / $chunkElapsed.TotalSeconds } else { 0 }
            
            # Only show detailed log for first and every 10th chunk to reduce clutter
            if ($chunkNumber -eq 1 -or $chunkNumber % 10 -eq 0) {
                Write-HashSmithLog -Message "✅ Chunk $chunkNumber completed in $($chunkElapsed.TotalSeconds.ToString('F1'))s ($($filesPerSecond.ToString('F1')) files/sec)" -Level INFO -Component 'PROCESS'
                
                # Show overall progress summary every 10 chunks
                if ($chunkNumber % 10 -eq 0) {
                    $overallPercent = [Math]::Round(($chunkNumber / $totalChunks) * 100, 1)
                    $overallElapsed = (Get-Date) - $stats.StartTime
                    $eta = if ($overallPercent -gt 0) {
                        $totalEstimated = ($overallElapsed.TotalMinutes / $overallPercent) * 100
                        $remaining = $totalEstimated - $overallElapsed.TotalMinutes
                        if ($remaining -gt 60) { "$([Math]::Floor($remaining / 60))h $([Math]::Floor($remaining % 60))m" } else { "$([Math]::Floor($remaining))m" }
                    } else { "calculating..." }
                    Write-HashSmithLog -Message "📊 Overall Progress: $overallPercent% ($chunkNumber/$totalChunks chunks) | ETA: $eta" -Level INFO -Component 'PROCESS'
                }
            }
            
            # Always show the brief progress update  
            Write-Host "✅ Chunk $chunkNumber/$totalChunks completed | Rate: $($filesPerSecond.ToString('F1')) files/sec" -ForegroundColor Green
            Start-Sleep -Milliseconds 750  # Increased pause to prevent system freezes
        }
        
        # Check if we should stop due to too many errors
        if ($errorCount -gt ($Files.Count * 0.5) -and $Files.Count -gt 100) {
            Write-HashSmithLog -Message "Stopping processing due to high error rate: $errorCount errors out of $processedCount files" -Level ERROR -Component 'PROCESS'
            Set-HashSmithExitCode -ExitCode 3
            break
        }
    }
    
    # Final log batch flush
    Clear-HashSmithLogBatch -LogPath $LogPath
    
    if ($ShowProgress) {
        Write-Host "`r$(' ' * 120)`r" -NoNewline  # Clear progress line
        Write-Host "✅ File processing completed!" -ForegroundColor Green
    }
    
    Write-HashSmithLog -Message "Enhanced file processing completed" -Level SUCCESS -Component 'PROCESS'
    Write-HashSmithLog -Message "Files processed successfully: $($processedCount - $errorCount)" -Level INFO -Component 'PROCESS'
    Write-HashSmithLog -Message "Files failed: $errorCount" -Level INFO -Component 'PROCESS'
    $stats = Get-HashSmithStatistics  # Get fresh statistics
    Write-HashSmithLog -Message "Race conditions detected: $($stats.FilesRaceCondition)" -Level INFO -Component 'PROCESS'
    Write-HashSmithLog -Message "Total bytes processed: $('{0:N2} GB' -f ($totalBytes / 1GB))" -Level INFO -Component 'PROCESS'
    Write-HashSmithLog -Message "Average throughput: $('{0:N1} MB/s' -f (($totalBytes / 1MB) / ((Get-Date) - $stats.StartTime).TotalSeconds))" -Level INFO -Component 'PROCESS'
    
    return $fileHashes
}

#endregion

# Export public functions
Export-ModuleMember -Function @(
    'Start-HashSmithFileProcessing'
)

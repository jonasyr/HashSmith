<#
.SYNOPSIS
    Main file processing orchestration for HashSmith

.DESCRIPTION
    This module orchestrates the main file processing workflow with parallel execution,
    progress tracking, error handling, and comprehensive result management.
    Enhanced with professional output and optimized performance.
#>

# Import required modules
# Note: Dependencies are handled by the main script import order

#region Public Functions

<#
.SYNOPSIS
    Processes files with enhanced parallel execution and professional output

.DESCRIPTION
    Orchestrates the main file processing workflow with chunked processing,
    parallel execution (PowerShell 7+), professional progress tracking, and comprehensive
    error handling and recovery. Enhanced with optimized terminal output.

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
    
    # Calculate optimal thread count for stability
    $safeThreads = if ($UseParallel -and $PSVersionTable.PSVersion.Major -ge 7) {
        $threads = [Math]::Round([Environment]::ProcessorCount * 0.80)  # Use 80% of cores for optimal performance
        if ($threads -lt 1) { $threads = 1 }
        [Math]::Min($MaxThreads, $threads)
    } else {
        1
    }
    
    # Log processing mode once
    if ($UseParallel -and $PSVersionTable.PSVersion.Major -ge 7) {
        Write-HashSmithLog -Message "Parallel processing enabled: $safeThreads threads (optimized for performance)" -Level INFO -Component 'PROCESS'
    } elseif ($UseParallel) {
        Write-HashSmithLog -Message "Parallel processing requested but using sequential (PowerShell 5.1)" -Level INFO -Component 'PROCESS'
    } else {
        Write-HashSmithLog -Message "Sequential processing mode" -Level INFO -Component 'PROCESS'
    }
    
    # Initialize processing variables
    $processedCount = 0
    $errorCount = 0
    $totalBytes = 0
    $fileHashes = @{}
    $lastProgressUpdate = Get-Date
    $stats = Get-HashSmithStatistics
    
    # Get configuration values
    $config = Get-HashSmithConfig
    
    # Process files in chunks for memory efficiency
    $totalChunks = [Math]::Ceiling($Files.Count / $ChunkSize)
    
    for ($i = 0; $i -lt $Files.Count; $i += $ChunkSize) {
        $endIndex = [Math]::Min($i + $ChunkSize - 1, $Files.Count - 1)
        $chunk = $Files[$i..$endIndex]
        $chunkNumber = [Math]::Floor($i / $ChunkSize) + 1
        
        # Professional chunk header
        Write-Host ""
        Write-Host "⚡ Processing Chunk $chunkNumber of $totalChunks" -ForegroundColor Cyan
        Write-Host "   Files: $($chunk.Count) | Range: $($i + 1) - $($endIndex + 1)" -ForegroundColor Gray
        
        $chunkStartTime = Get-Date
        
        # Test network connectivity before processing chunk
        if (-not (Test-HashSmithNetworkPath -Path $BasePath -UseCache)) {
            Write-HashSmithLog -Message "Network connectivity lost, aborting chunk processing" -Level ERROR -Component 'PROCESS'
            break
        }
        
        # Enhanced parallel processing with professional output
        if ($UseParallel -and $PSVersionTable.PSVersion.Major -ge 7) {
            # Initialize progress variables
            $totalChunkFiles = $chunk.Count
            $lastProgressCount = 0
            $lastProgressTime = Get-Date
            
            # Professional progress header
            Write-Host "   🚀 Parallel execution with $safeThreads threads" -ForegroundColor Green
            
            # Process files with optimized parallel jobs
            $chunkResults = $chunk | ForEach-Object -Parallel {
                # Import required variables into parallel runspace
                $Algorithm = $using:Algorithm
                $RetryCount = $using:RetryCount
                
                # Process single file with optimized approach
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
                    # Optimized streaming hash computation
                    $hashAlgorithm = [System.Security.Cryptography.HashAlgorithm]::Create($Algorithm)
                    try {
                        # Enhanced file stream with optimal buffer size
                        $fileStream = [System.IO.File]::OpenRead($file.FullName)
                        try {
                            $hashBytes = $hashAlgorithm.ComputeHash($fileStream)
                            $result.Hash = [System.BitConverter]::ToString($hashBytes) -replace '-', ''
                            $result.Hash = $result.Hash.ToLower()
                            $result.Success = $true
                            
                            # Reduced delay to improve performance
                            Start-Sleep -Milliseconds 25
                        }
                        finally {
                            if ($fileStream) { $fileStream.Dispose() }
                        }
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
            
            # Professional progress monitoring
            $spinChars = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
            $spinIndex = 0
            
            # Monitor jobs with enhanced timeout handling
            while ($chunkResults.State -eq 'Running') {
                $char = $spinChars[$spinIndex % $spinChars.Length]
                $elapsed = (Get-Date) - $chunkStartTime
                $elapsedStr = if ($elapsed.TotalMinutes -gt 1) { 
                    "$([Math]::Floor($elapsed.TotalMinutes))m $([Math]::Floor($elapsed.Seconds))s" 
                } else { 
                    "$([Math]::Floor($elapsed.TotalSeconds))s" 
                }
                
                # Enhanced progress estimation
                $currentResults = @()
                try {
                    $currentResults = @(Receive-Job $chunkResults -Keep -ErrorAction SilentlyContinue)
                } catch {
                    # Silently handle progress check errors
                }
                
                $completedCount = $currentResults.Count
                $progressPercent = if ($totalChunkFiles -gt 0) { 
                    [Math]::Round(($completedCount / $totalChunkFiles) * 100, 1) 
                } else { 0 }
                
                # Smart timeout with progress tracking
                $timeSinceLastProgress = (Get-Date) - $lastProgressTime
                if ($completedCount -gt $lastProgressCount) {
                    $lastProgressCount = $completedCount
                    $lastProgressTime = Get-Date
                } elseif ($timeSinceLastProgress.TotalMinutes -gt 15) {
                    # Timeout after 15 minutes of no progress
                    Write-Host "`r   ⚠️  No progress for 15 minutes, stopping chunk..." -ForegroundColor Red
                    Stop-Job $chunkResults -ErrorAction SilentlyContinue
                    break
                }
                
                # Professional progress display
                $progressMsg = "   $char Processing: $completedCount/$totalChunkFiles ($progressPercent%) | $elapsedStr"
                Write-Host "`r$progressMsg$(' ' * 10)" -NoNewline -ForegroundColor Yellow
                
                Start-Sleep -Milliseconds 150
                $spinIndex++
            }
            
            # Get final results with error handling
            try {
                $chunkResults = Receive-Job $chunkResults -Wait -ErrorAction Stop
                Remove-Job $chunkResults -Force -ErrorAction SilentlyContinue
            }
            catch {
                Write-HashSmithLog -Message "Error retrieving parallel job results: $($_.Exception.Message)" -Level ERROR -Component 'PROCESS'
                $chunkResults = @()
            }
            
            # Clear progress line
            Write-Host "`r$(' ' * 80)`r" -NoNewline
        } else {
            # Enhanced sequential processing
            Write-Host "   ⚙️  Sequential processing mode" -ForegroundColor Gray
            $chunkResults = @()
            $chunkFileCount = 0
            
            foreach ($file in $chunk) {
                $chunkFileCount++
                
                # Professional file progress with clean formatting
                $fileName = Split-Path $file.FullName -Leaf
                $progressPercent = [Math]::Round(($chunkFileCount / $chunk.Count) * 100, 1)
                
                # Clean single-line progress update
                Write-Host "`r   🔄 Processing: $fileName ($progressPercent%)" -NoNewline -ForegroundColor Cyan
                
                $result = Get-HashSmithFileHashSafe -Path $file.FullName -Algorithm $Algorithm -RetryCount $RetryCount -TimeoutSeconds $TimeoutSeconds -VerifyIntegrity:$VerifyIntegrity -StrictMode:$StrictMode -PreIntegritySnapshot $file.IntegritySnapshot
                
                # Enhanced result mapping
                $result.Path = $file.FullName
                $result.Size = $file.Length
                $result.Modified = $file.LastWriteTime
                $result.IsSymlink = Test-HashSmithSymbolicLink -Path $file.FullName
                
                # Map hash function result properties
                if (-not $result.ContainsKey('IntegrityVerified')) {
                    $result.IntegrityVerified = if ($result.ContainsKey('Integrity')) { [bool]$result.Integrity } else { $false }
                }
                
                $chunkResults += $result
                
                # Optimized delay for system load management
                Start-Sleep -Milliseconds 10
            }
            
            # Clear progress line
            Write-Host "`r$(' ' * 80)`r" -NoNewline
        }
        
        # Process results with enhanced error handling and logging
        $chunkSuccessCount = 0
        $chunkErrorCount = 0
        
        foreach ($result in $chunkResults) {
            $processedCount++
            
            if ($result.Success) {
                $chunkSuccessCount++
                
                # Write to log with enhanced error handling
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
                $chunkErrorCount++
                
                # Write error to log with enhanced handling
                try {
                    Write-HashSmithHashEntry -LogPath $LogPath -FilePath $result.Path -Size $result.Size -Modified $result.Modified -ErrorMessage $result.Error -ErrorCategory $result.ErrorCategory -BasePath $BasePath -IsSymlink $result.IsSymlink -RaceConditionDetected $result.RaceConditionDetected -UseBatching
                }
                catch {
                    Write-HashSmithLog -Message "Failed to write error log entry for $($result.Path): $($_.Exception.Message)" -Level WARN -Component 'PROCESS'
                }
                
                $errorCount++
                Add-HashSmithStatistic -Name 'FilesError' -Amount 1
                
                # Enhanced error categorization
                if ($result.ErrorCategory -in @('IO', 'Unknown')) {
                    Add-HashSmithStatistic -Name 'RetriableErrors' -Amount 1
                } else {
                    Add-HashSmithStatistic -Name 'NonRetriableErrors' -Amount 1
                }
            }
        }
        
        # Professional chunk completion summary
        $chunkElapsed = (Get-Date) - $chunkStartTime
        $filesPerSecond = if ($chunkElapsed.TotalSeconds -gt 0) { $chunk.Count / $chunkElapsed.TotalSeconds } else { 0 }
        
        Write-Host "   ✅ Chunk completed: $chunkSuccessCount success, $chunkErrorCount errors" -ForegroundColor Green
        Write-Host "   ⏱️  Time: $($chunkElapsed.TotalSeconds.ToString('F1'))s | Rate: $($filesPerSecond.ToString('F1')) files/sec" -ForegroundColor Blue
        
        # Enhanced overall progress display (every 5 chunks or at end)
        if ($chunkNumber % 5 -eq 0 -or $chunkNumber -eq $totalChunks) {
            $overallPercent = [Math]::Round(($chunkNumber / $totalChunks) * 100, 1)
            $overallElapsed = (Get-Date) - $stats.StartTime
            $eta = if ($overallPercent -gt 5) {
                $totalEstimated = ($overallElapsed.TotalMinutes / $overallPercent) * 100
                $remaining = $totalEstimated - $overallElapsed.TotalMinutes
                if ($remaining -gt 60) { 
                    "$([Math]::Floor($remaining / 60))h $([Math]::Floor($remaining % 60))m" 
                } else { 
                    "$([Math]::Floor($remaining))m" 
                }
            } else { 
                "calculating..." 
            }
            
            Write-Host ""
            Write-Host "📊 Overall Progress: $overallPercent% | ETA: $eta | Errors: $errorCount" -ForegroundColor Magenta
        }
        
        # Flush log batch periodically for data safety
        Clear-HashSmithLogBatch -LogPath $LogPath
        
        # Enhanced system load management
        if ($chunkNumber -lt $totalChunks) {
            Start-Sleep -Milliseconds 500  # Brief pause between chunks
        }
        
        # Safety check for excessive errors
        if ($errorCount -gt ($Files.Count * 0.5) -and $Files.Count -gt 100) {
            Write-HashSmithLog -Message "Stopping processing due to high error rate: $errorCount errors out of $processedCount files" -Level ERROR -Component 'PROCESS'
            Set-HashSmithExitCode -ExitCode 3
            break
        }
    }
    
    # Final log batch flush
    Clear-HashSmithLogBatch -LogPath $LogPath
    
    # Professional completion summary
    Write-Host ""
    Write-Host "🎉 File processing completed!" -ForegroundColor Green
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
    
    $finalStats = Get-HashSmithStatistics
    $throughputMBps = if ($finalStats.StartTime) {
        ($totalBytes / 1MB) / ((Get-Date) - $finalStats.StartTime).TotalSeconds
    } else { 0 }
    
    Write-HashSmithLog -Message "Enhanced file processing completed" -Level SUCCESS -Component 'PROCESS'
    Write-HashSmithLog -Message "Files processed successfully: $($processedCount - $errorCount)" -Level INFO -Component 'PROCESS'
    Write-HashSmithLog -Message "Files failed: $errorCount" -Level INFO -Component 'PROCESS'
    Write-HashSmithLog -Message "Race conditions detected: $($finalStats.FilesRaceCondition)" -Level INFO -Component 'PROCESS'
    Write-HashSmithLog -Message "Total bytes processed: $('{0:N2} GB' -f ($totalBytes / 1GB))" -Level INFO -Component 'PROCESS'
    Write-HashSmithLog -Message "Average throughput: $('{0:N1} MB/s' -f $throughputMBps)" -Level INFO -Component 'PROCESS'
    
    # Ensure we return only the hashtable, not an array
    return ,$fileHashes
}

#endregion

# Export public functions
Export-ModuleMember -Function @(
    'Start-HashSmithFileProcessing'
)
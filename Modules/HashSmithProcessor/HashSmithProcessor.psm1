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
    
    # Log parallel processing status
    if ($UseParallel -and $PSVersionTable.PSVersion.Major -ge 7) {
        Write-HashSmithLog -Message "Parallel processing enabled with $MaxThreads threads (PowerShell 7+)" -Level INFO -Component 'PROCESS'
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
    $bufferSize = $config.BufferSize
    
    # Process files in chunks for memory efficiency
    for ($i = 0; $i -lt $Files.Count; $i += $ChunkSize) {
        $endIndex = [Math]::Min($i + $ChunkSize - 1, $Files.Count - 1)
        $chunk = $Files[$i..$endIndex]
        $chunkNumber = [Math]::Floor($i / $ChunkSize) + 1
        $totalChunks = [Math]::Ceiling($Files.Count / $ChunkSize)
        
        Write-HashSmithLog -Message "Processing chunk $chunkNumber of $totalChunks ($($chunk.Count) files)" -Level PROGRESS -Component 'PROCESS'
        
        # Test network connectivity before processing chunk
        if (-not (Test-HashSmithNetworkPath -Path $BasePath -UseCache)) {
            Write-HashSmithLog -Message "Network connectivity lost, aborting chunk processing" -Level ERROR -Component 'PROCESS'
            break
        }
        
        # Guard parallel processing behind PowerShell version check
        if ($UseParallel -and $PSVersionTable.PSVersion.Major -ge 7) {
            # Process chunk with parallel processing (PowerShell 7+) - simplified to avoid stack overflow
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
                
            } -ThrottleLimit $MaxThreads
        } else {
            # Process chunk sequentially (PowerShell 5.1 or parallel disabled)
            $chunkResults = @()
            foreach ($file in $chunk) {
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
            }
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

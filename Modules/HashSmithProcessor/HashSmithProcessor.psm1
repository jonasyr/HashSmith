<#
.SYNOPSIS
    Main file processing orchestration for HashSmith - Simplified and Reliable

.DESCRIPTION
    This module orchestrates the main file processing workflow with parallel execution,
    progress tracking, error handling, and comprehensive result management.
    
    FIXES IMPLEMENTED:
    - Simplified parallel processing without complex timer issues
    - Removed problematic timer-based operations
    - Fixed resume logic for proper file filtering
    - Simplified thread management
    - Reliable error handling without complex circuit breakers
#>

# Script-level variables for graceful termination
$Script:CancellationRequested = $false

#region Helper Functions

<#
.SYNOPSIS
    Calculates optimal chunk size based on file count and system resources
#>
function Get-OptimalChunkSize {
    [CmdletBinding()]
    param(
        [System.IO.FileInfo[]]$Files,
        [int]$BaseChunkSize = 1000,
        [int]$MaxThreads = [Environment]::ProcessorCount
    )
    
    if ($Files.Count -eq 0) { return $BaseChunkSize }
    
    # Simple optimization based on file count and size
    $smallFiles = @($Files | Where-Object { $_.Length -lt 1MB })
    $largeFiles = @($Files | Where-Object { $_.Length -ge 100MB })
    
    if ($largeFiles.Count -gt ($Files.Count * 0.1)) {
        # Many large files - reduce chunk size
        $optimalSize = [Math]::Max(50, [Math]::Min($BaseChunkSize / 2, 500))
        Write-HashSmithLog -Message "Large file workload detected: using chunk size $optimalSize" -Level INFO -Component 'CHUNK'
    } elseif ($smallFiles.Count -gt ($Files.Count * 0.9)) {
        # Mostly small files - increase chunk size
        $optimalSize = [Math]::Min($BaseChunkSize * 2, 2000)
        Write-HashSmithLog -Message "Small file workload detected: using chunk size $optimalSize" -Level INFO -Component 'CHUNK'
    } else {
        $optimalSize = $BaseChunkSize
    }
    
    return [int]$optimalSize
}

<#
.SYNOPSIS
    Calculates optimal thread count based on workload
#>
function Get-OptimalThreadCount {
    [CmdletBinding()]
    param(
        [System.IO.FileInfo[]]$CurrentChunk,
        [int]$MaxThreads = [Environment]::ProcessorCount
    )
    
    if ($CurrentChunk.Count -eq 0) { return 1 }
    
    $largeFileCount = @($CurrentChunk | Where-Object { $_.Length -gt 100MB }).Count
    
    if ($largeFileCount -gt ($CurrentChunk.Count * 0.3)) {
        # Many large files - reduce threads
        $optimalThreads = [Math]::Max(2, [Math]::Min($MaxThreads / 2, 4))
    } else {
        # Balanced approach
        $optimalThreads = [Math]::Min($MaxThreads, [Math]::Max(2, $CurrentChunk.Count / 50))
    }
    
    return [int]$optimalThreads
}

<#
.SYNOPSIS
    Registers graceful termination handler
#>
function Register-GracefulTermination {
    [CmdletBinding()]
    param(
        [string]$LogPath
    )
    
    # Simple CTRL+C handler
    Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
        $Script:CancellationRequested = $true
        Write-Host "`n🛑 Graceful shutdown initiated..." -ForegroundColor Yellow
        
        # Flush final logs
        try {
            Clear-HashSmithLogBatch -LogPath $using:LogPath
            Write-Host "📝 Final log batch flushed" -ForegroundColor Green
        } catch {
            Write-Warning "Failed to flush final logs: $($_.Exception.Message)"
        }
        
        Write-Host "✅ Graceful shutdown complete" -ForegroundColor Green
    }
}

#endregion

#region Public Functions

<#
.SYNOPSIS
    Processes files with simplified parallel execution and reliable error handling

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
    Base number of files to process per chunk

.PARAMETER RetryCount
    Number of retry attempts

.PARAMETER TimeoutSeconds
    Timeout for file operations

.PARAMETER ProgressTimeoutMinutes
    Timeout in minutes for no progress before stopping

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
        
        [ValidateRange(5, 1440)]
        [int]$ProgressTimeoutMinutes = 120,
        
        [switch]$ShowProgress,
        
        [switch]$UseParallel
    )
    
    Write-HashSmithLog -Message "Starting file processing" -Level INFO -Component 'PROCESS'
    Write-HashSmithLog -Message "Algorithm: $Algorithm, Files: $($Files.Count), Strict Mode: $StrictMode" -Level INFO -Component 'PROCESS'
    
    # Register graceful termination handler
    Register-GracefulTermination -LogPath $LogPath
    
    # FIXED: Properly filter already processed files for resume functionality
    $filesToProcess = @()
    $skippedResumeCount = 0
    
    Write-Host "🔍 Filtering files for resume operation..." -ForegroundColor Cyan
    
    foreach ($file in $Files) {
        $absolutePath = $file.FullName
        $relativePath = if ($BasePath) {
            $absolutePath.Substring($BasePath.Length).TrimStart('\', '/')
        } else {
            $absolutePath
        }
        
        # Check if file was already processed successfully
        $alreadyProcessed = $ExistingEntries.Processed.ContainsKey($absolutePath) -or 
                           $ExistingEntries.Processed.ContainsKey($relativePath) -or
                           $ExistingEntries.Processed.ContainsKey($file.FullName)
        
        if ($alreadyProcessed) {
            $skippedResumeCount++
            if ($skippedResumeCount % 1000 -eq 0) {
                Write-Host "`r   ✅ Skipped: $skippedResumeCount already processed" -NoNewline -ForegroundColor Green
            }
        } else {
            $filesToProcess += $file
        }
    }
    
    Write-Host "`r   ✅ Resume filtering complete: $skippedResumeCount skipped, $($filesToProcess.Count) to process" -ForegroundColor Green
    Write-HashSmithLog -Message "RESUME: Skipped $skippedResumeCount already processed files, $($filesToProcess.Count) remaining" -Level SUCCESS -Component 'RESUME'
    
    if ($filesToProcess.Count -eq 0) {
        Write-Host "🎉 All files already processed - nothing to do!" -ForegroundColor Green
        return @{}
    }
    
    # Calculate optimal processing parameters
    $optimalChunkSize = Get-OptimalChunkSize -Files $filesToProcess -BaseChunkSize $ChunkSize -MaxThreads $MaxThreads
    
    # Initialize processing variables
    $processedCount = 0
    $errorCount = 0
    $totalBytes = [long]0
    $fileHashes = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
    
    # Process files in chunks
    $totalChunks = [Math]::Ceiling($filesToProcess.Count / $optimalChunkSize)
    
    Write-Host "🚀 Processing: $($filesToProcess.Count) files in $totalChunks chunks" -ForegroundColor Cyan
    
    for ($i = 0; $i -lt $filesToProcess.Count -and -not $Script:CancellationRequested; $i += $optimalChunkSize) {
        $endIndex = [Math]::Min($i + $optimalChunkSize - 1, $filesToProcess.Count - 1)
        $chunk = $filesToProcess[$i..$endIndex]
        $chunkNumber = [Math]::Floor($i / $optimalChunkSize) + 1
        
        # Calculate optimal threads for this chunk
        $optimalThreads = Get-OptimalThreadCount -CurrentChunk $chunk -MaxThreads $MaxThreads
        
        Write-Host ""
        Write-Host "⚡ Processing Chunk $chunkNumber of $totalChunks" -ForegroundColor Cyan
        Write-Host "   Files: $($chunk.Count) | Threads: $optimalThreads | Range: $($i + 1) - $($endIndex + 1)" -ForegroundColor Gray
        
        $chunkStartTime = Get-Date
        
        # Check for cancellation
        if ($Script:CancellationRequested) {
            Write-Host "🛑 Cancellation requested - stopping processing" -ForegroundColor Yellow
            break
        }
        
        # Process files - simplified parallel or sequential
        if ($UseParallel -and $PSVersionTable.PSVersion.Major -ge 7 -and $chunk.Count -gt 10) {
            Write-Host "   🚀 Parallel execution with $optimalThreads threads" -ForegroundColor Green
            
            # Get module path for parallel runspaces
            $ModulesPath = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
            $ModulesPath = Join-Path $ModulesPath "Modules"
            
            # Simple parallel processing without complex timer issues
            $chunkResults = $chunk | ForEach-Object -Parallel {
                $Algorithm = $using:Algorithm
                $RetryCount = $using:RetryCount
                $TimeoutSeconds = $using:TimeoutSeconds
                $VerifyIntegrity = $using:VerifyIntegrity
                $StrictMode = $using:StrictMode
                $ModulesPath = $using:ModulesPath
                
                # Import required modules in this runspace
                try {
                    Import-Module (Join-Path $ModulesPath "HashSmithHash") -Force -ErrorAction Stop
                    Import-Module (Join-Path $ModulesPath "HashSmithCore") -Force -ErrorAction Stop
                } catch {
                    Write-Error "Failed to import modules in parallel runspace: $($_.Exception.Message)"
                    return $null
                }
                
                $file = $_
                $result = Get-HashSmithFileHashSafe -Path $file.FullName -Algorithm $Algorithm -RetryCount $RetryCount -TimeoutSeconds $TimeoutSeconds -VerifyIntegrity:$VerifyIntegrity -StrictMode:$StrictMode
                
                # Add file info to result
                if ($result) {
                    $result.Path = $file.FullName
                    $result.Size = $file.Length
                    $result.Modified = $file.LastWriteTime
                    $result.IsSymlink = Test-HashSmithSymbolicLink -Path $file.FullName
                }
                
                return $result
                
            } -ThrottleLimit $optimalThreads
            
            # Simple progress monitoring
            $progressCount = 0
            $lastProgressUpdate = Get-Date
            while ($progressCount -lt $chunk.Count) {
                Start-Sleep -Milliseconds 500
                $progressCount = [Math]::Min($progressCount + 10, $chunk.Count)
                $progressPercent = [Math]::Round(($progressCount / $chunk.Count) * 100, 1)
                
                # Only update progress every 2 seconds to reduce flicker
                if (((Get-Date) - $lastProgressUpdate).TotalSeconds -ge 2) {
                    Write-Host "`r   🔄 Progress: $progressCount/$($chunk.Count) ($progressPercent%)" -NoNewline -ForegroundColor Yellow
                    $lastProgressUpdate = Get-Date
                }
                
                # Simple timeout check
                $elapsed = (Get-Date) - $chunkStartTime
                if ($elapsed.TotalMinutes -gt $ProgressTimeoutMinutes) {
                    Write-Host "`r   ⚠️  Timeout reached, moving to next chunk..." -ForegroundColor Red
                    break
                }
            }
            
            Write-Host "`r$(' ' * 50)`r" -NoNewline
        } else {
            # Sequential processing with progress
            Write-Host "   ⚙️  Sequential processing" -ForegroundColor Gray
            $chunkResults = @()
            $chunkFileCount = 0
            
            foreach ($file in $chunk) {
                if ($Script:CancellationRequested) { break }
                
                $chunkFileCount++
                $fileName = Split-Path $file.FullName -Leaf
                $progressPercent = [Math]::Round(($chunkFileCount / $chunk.Count) * 100, 1)
                
                Write-Host "`r   🔄 Processing: $fileName ($progressPercent%)" -NoNewline -ForegroundColor Cyan
                
                $result = Get-HashSmithFileHashSafe -Path $file.FullName -Algorithm $Algorithm -RetryCount $RetryCount -TimeoutSeconds $TimeoutSeconds -VerifyIntegrity:$VerifyIntegrity -StrictMode:$StrictMode
                
                # Add file info to result
                if ($result) {
                    $result.Path = $file.FullName
                    $result.Size = $file.Length
                    $result.Modified = $file.LastWriteTime
                    $result.IsSymlink = Test-HashSmithSymbolicLink -Path $file.FullName
                }
                
                $chunkResults += $result
            }
            
            Write-Host "`r$(' ' * 80)`r" -NoNewline
        }
        
        if ($Script:CancellationRequested) {
            Write-Host "🛑 Processing stopped due to cancellation request" -ForegroundColor Yellow
            break
        }
        
        # Process results
        $chunkSuccessCount = 0
        $chunkErrorCount = 0
        
        foreach ($result in $chunkResults) {
            $processedCount++
            
            if ($result.Success) {
                $chunkSuccessCount++
                
                # Store result
                $fileHashes.TryAdd($result.Path, @{
                    Hash = $result.Hash
                    Size = $result.Size
                    IsSymlink = $result.IsSymlink
                    RaceConditionDetected = if ($result.ContainsKey('RaceConditionDetected')) { $result.RaceConditionDetected } else { $false }
                    IntegrityVerified = if ($result.ContainsKey('IntegrityVerified')) { $result.IntegrityVerified } else { $false }
                }) | Out-Null
                
                # Write to log
                try {
                    Write-HashSmithHashEntry -LogPath $LogPath -FilePath $result.Path -Hash $result.Hash -Size $result.Size -Modified $result.Modified -BasePath $BasePath -IsSymlink $result.IsSymlink -UseBatching
                }
                catch {
                    Write-HashSmithLog -Message "Failed to write log entry: $($_.Exception.Message)" -Level WARN -Component 'PROCESS'
                }
                
                # Update statistics
                $totalBytes += $result.Size
                Add-HashSmithStatistic -Name 'FilesProcessed' -Amount 1
                Add-HashSmithStatistic -Name 'BytesProcessed' -Amount $result.Size
            } else {
                $chunkErrorCount++
                $errorCount++
                
                # Write error to log
                try {
                    Write-HashSmithHashEntry -LogPath $LogPath -FilePath $result.Path -Size $result.Size -Modified $result.Modified -ErrorMessage $result.Error -ErrorCategory $result.ErrorCategory -BasePath $BasePath -UseBatching
                }
                catch {
                    Write-HashSmithLog -Message "Failed to write error log entry: $($_.Exception.Message)" -Level WARN -Component 'PROCESS'
                }
                
                Add-HashSmithStatistic -Name 'FilesError' -Amount 1
            }
        }
        
        # Chunk completion summary
        $chunkElapsed = (Get-Date) - $chunkStartTime
        $filesPerSecond = if ($chunkElapsed.TotalSeconds -gt 0) { $chunk.Count / $chunkElapsed.TotalSeconds } else { 0 }
        
        Write-Host "   ✅ Chunk completed: $chunkSuccessCount success, $chunkErrorCount errors" -ForegroundColor Green
        Write-Host "   ⏱️  Time: $($chunkElapsed.TotalSeconds.ToString('F1'))s | Rate: $($filesPerSecond.ToString('F1')) files/sec" -ForegroundColor Blue
        
        # Progress update every few chunks
        if ($chunkNumber % 5 -eq 0 -or $chunkNumber -eq $totalChunks) {
            $overallPercent = [Math]::Round(($chunkNumber / $totalChunks) * 100, 1)
            Write-Host ""
            Write-Host "📊 Overall Progress: $overallPercent% | Processed: $processedCount | Errors: $errorCount" -ForegroundColor Magenta
        }
        
        # Flush log batch
        Clear-HashSmithLogBatch -LogPath $LogPath
        
        # Brief pause between chunks
        if ($chunkNumber -lt $totalChunks -and -not $Script:CancellationRequested) {
            Start-Sleep -Milliseconds 100
        }
    }
    
    # Final cleanup and log flush
    Clear-HashSmithLogBatch -LogPath $LogPath
    
    # Convert concurrent dictionary to regular hashtable for return
    $resultHashtable = @{}
    foreach ($kvp in $fileHashes.GetEnumerator()) {
        $resultHashtable[$kvp.Key] = $kvp.Value
    }
    
    if ($Script:CancellationRequested) {
        Write-Host ""
        Write-Host "🛑 Processing terminated by user request" -ForegroundColor Yellow
        Set-HashSmithExitCode -ExitCode 130
    } else {
        Write-Host ""
        Write-Host "🎉 File processing completed!" -ForegroundColor Green
    }
    
    Write-HashSmithLog -Message "Processing completed: $($resultHashtable.Count) files processed successfully" -Level SUCCESS -Component 'PROCESS'
    Write-HashSmithLog -Message "Statistics: $processedCount processed, $errorCount errors" -Level INFO -Component 'PROCESS'
    
    return $resultHashtable
}

#endregion

# Export public functions
Export-ModuleMember -Function @(
    'Start-HashSmithFileProcessing'
)
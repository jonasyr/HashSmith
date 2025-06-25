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
            # Process chunk with parallel processing (PowerShell 7+)
            $chunkResults = $chunk | ForEach-Object -Parallel {
                # Import required variables and functions into parallel runspace
                $Algorithm = $using:Algorithm
                $RetryCount = $using:RetryCount
                $TimeoutSeconds = $using:TimeoutSeconds
                $VerifyIntegrity = $using:VerifyIntegrity
                $StrictMode = $using:StrictMode
                $BufferSize = $using:bufferSize
                
                # Re-create essential functions for parallel execution
                function Get-NormalizedPath {
                    param([string]$Path)
                    try {
                        $normalizedPath = [System.IO.Path]::GetFullPath($Path.Normalize([System.Text.NormalizationForm]::FormC))
                        if ($normalizedPath.Length -gt 260 -and -not $normalizedPath.StartsWith('\\?\')) {
                            if ($normalizedPath -match '^[\\\\]{2}[^\\]+\\') {
                                return "\\?\UNC\" + $normalizedPath.Substring(2)
                            } else {
                                return "\\?\$normalizedPath"
                            }
                        }
                        return $normalizedPath
                    }
                    catch { throw }
                }
                
                function Test-FileAccessible {
                    param([string]$Path, [int]$TimeoutMs = 5000)
                    $timeout = (Get-Date).AddMilliseconds($TimeoutMs)
                    do {
                        try {
                            $normalizedPath = Get-NormalizedPath -Path $Path
                            $fileStream = [System.IO.File]::Open($normalizedPath, 'Open', 'Read', 'Read')
                            $fileStream.Close()
                            return $true
                        }
                        catch [System.IO.IOException] {
                            if ((Get-Date) -gt $timeout) { return $false }
                            Start-Sleep -Milliseconds 200
                        }
                        catch { return $false }
                    } while ($true)
                }
                
                function Get-FileIntegritySnapshot {
                    param([string]$Path)
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
                    catch { return $null }
                }
                
                function Test-FileIntegrityMatch {
                    param([hashtable]$Snapshot1, [hashtable]$Snapshot2)
                    if (-not $Snapshot1 -or -not $Snapshot2) { return $false }
                    return ($Snapshot1.Size -eq $Snapshot2.Size -and
                            $Snapshot1.LastWriteTimeUtc -eq $Snapshot2.LastWriteTimeUtc -and
                            $Snapshot1.Attributes -eq $Snapshot2.Attributes)
                }
                
                function Test-SymbolicLink {
                    param([string]$Path)
                    try {
                        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
                        return ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq [System.IO.FileAttributes]::ReparsePoint
                    }
                    catch { return $false }
                }
                
                # Process single file
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
                    Attempts = 0
                }
                
                $startTime = Get-Date
                
                # Check if file is a symbolic link
                $result.IsSymlink = Test-SymbolicLink -Path $file.FullName
                
                # Get initial integrity snapshot
                $preSnapshot = $null
                if ($StrictMode -or $VerifyIntegrity) {
                    # Use stored snapshot if available (from discovery)
                    if ($file.PSObject.Properties['IntegritySnapshot']) {
                        $preSnapshot = $file.IntegritySnapshot
                    } else {
                        $preSnapshot = Get-FileIntegritySnapshot -Path $file.FullName
                    }
                }
                
                # Process file with retry logic
                for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
                    $result.Attempts = $attempt
                    
                    try {
                        $normalizedPath = Get-NormalizedPath -Path $file.FullName
                        
                        if (-not (Test-Path -LiteralPath $normalizedPath)) {
                            throw [System.IO.FileNotFoundException]::new("File not found: $($file.FullName)")
                        }
                        
                        if (-not (Test-FileAccessible -Path $normalizedPath -TimeoutMs ($TimeoutSeconds * 1000))) {
                            throw [System.IO.IOException]::new("File is locked or inaccessible: $($file.FullName)")
                        }
                        
                        # Race condition detection
                        if ($preSnapshot) {
                            $currentSnapshot = Get-FileIntegritySnapshot -Path $normalizedPath
                            if (-not (Test-FileIntegrityMatch -Snapshot1 $preSnapshot -Snapshot2 $currentSnapshot)) {
                                $result.RaceConditionDetected = $true
                                if ($StrictMode) {
                                    throw [System.InvalidOperationException]::new("File modified between discovery and processing")
                                }
                                # Update snapshot for post-processing check
                                $preSnapshot = $currentSnapshot
                            }
                        }
                        
                        # Compute hash
                        $hashAlgorithm = [System.Security.Cryptography.HashAlgorithm]::Create($Algorithm)
                        $fileStream = $null
                        
                        try {
                            $fileStream = [System.IO.File]::Open($normalizedPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read, 4096, [System.IO.FileOptions]::SequentialScan)
                            $currentFileInfo = [System.IO.FileInfo]::new($normalizedPath)
                            
                            # Handle zero-byte files explicitly
                            if ($currentFileInfo.Length -eq 0) {
                                $hashBytes = $hashAlgorithm.ComputeHash([byte[]]::new(0))
                            } else {
                                # Stream-based hash computation
                                $buffer = [byte[]]::new($BufferSize)
                                $totalRead = 0
                                
                                while ($totalRead -lt $currentFileInfo.Length) {
                                    $bytesRead = $fileStream.Read($buffer, 0, $buffer.Length)
                                    if ($bytesRead -eq 0) { break }
                                    
                                    if ($totalRead + $bytesRead -eq $currentFileInfo.Length) {
                                        $hashAlgorithm.TransformFinalBlock($buffer, 0, $bytesRead) | Out-Null
                                    } else {
                                        $hashAlgorithm.TransformBlock($buffer, 0, $bytesRead, $null, 0) | Out-Null
                                    }
                                    
                                    $totalRead += $bytesRead
                                    
                                    if ($totalRead -gt $currentFileInfo.Length) {
                                        throw [System.InvalidDataException]::new("Read more bytes than expected")
                                    }
                                }
                                
                                $hashBytes = $hashAlgorithm.Hash
                            }
                            
                            $result.Hash = [System.BitConverter]::ToString($hashBytes) -replace '-', ''
                            $result.Hash = $result.Hash.ToLower()
                            
                            # Post-processing integrity check
                            if ($StrictMode -or $VerifyIntegrity) {
                                $postSnapshot = Get-FileIntegritySnapshot -Path $normalizedPath
                                if ($preSnapshot -and (Test-FileIntegrityMatch -Snapshot1 $preSnapshot -Snapshot2 $postSnapshot)) {
                                    $result.IntegrityVerified = $true
                                } elseif ($StrictMode) {
                                    throw [System.InvalidOperationException]::new("File integrity verification failed")
                                }
                            }
                            
                            $result.Success = $true
                            break
                            
                        } finally {
                            if ($fileStream) { $fileStream.Dispose() }
                            if ($hashAlgorithm) { $hashAlgorithm.Dispose() }
                        }
                    }
                    catch [System.IO.FileNotFoundException] {
                        $result.Error = $_.Exception.Message
                        $result.ErrorCategory = 'FileNotFound'
                        break
                    }
                    catch [System.IO.DirectoryNotFoundException] {
                        $result.Error = $_.Exception.Message
                        $result.ErrorCategory = 'DirectoryNotFound'
                        break
                    }
                    catch [System.InvalidOperationException] {
                        $result.Error = $_.Exception.Message
                        $result.ErrorCategory = 'Integrity'
                        break
                    }
                    catch [System.UnauthorizedAccessException] {
                        $result.Error = $_.Exception.Message
                        $result.ErrorCategory = 'AccessDenied'
                        break
                    }
                    catch [System.IO.IOException] {
                        $result.Error = $_.Exception.Message
                        $result.ErrorCategory = 'IO'
                    }
                    catch {
                        $result.Error = $_.Exception.Message
                        $result.ErrorCategory = 'Unknown'
                    }
                    
                    # Retry logic for retriable errors
                    if ($attempt -lt $RetryCount -and $result.ErrorCategory -in @('IO', 'Unknown')) {
                        $delay = [Math]::Min(500 * [Math]::Pow(2, $attempt - 1), 5000)
                        Start-Sleep -Milliseconds $delay
                    }
                }
                
                $result.Duration = (Get-Date) - $startTime
                return $result
                
            } -ThrottleLimit $MaxThreads
        } else {
            # Process chunk sequentially (PowerShell 5.1 or parallel disabled)
            $chunkResults = @()
            foreach ($file in $chunk) {
                $result = Get-HashSmithFileHashSafe -Path $file.FullName -Algorithm $Algorithm -RetryCount $RetryCount -TimeoutSeconds $TimeoutSeconds -VerifyIntegrity:$VerifyIntegrity -StrictMode:$StrictMode -PreIntegritySnapshot $file.IntegritySnapshot
                
                # Add additional properties expected by the result processor
                $result.Path = $file.FullName
                $result.Size = $file.Length
                $result.Modified = $file.LastWriteTime
                $result.IsSymlink = Test-HashSmithSymbolicLink -Path $file.FullName
                
                $chunkResults += $result
            }
        }
        
        # Write results and update statistics
        foreach ($result in $chunkResults) {
            $processedCount++
            
            if ($result.Success) {
                # Write to log
                Write-HashSmithHashEntry -LogPath $LogPath -FilePath $result.Path -Hash $result.Hash -Size $result.Size -Modified $result.Modified -BasePath $BasePath -IsSymlink $result.IsSymlink -RaceConditionDetected $result.RaceConditionDetected -IntegrityVerified $result.IntegrityVerified -UseBatching
                
                # Store for directory hash
                $fileHashes[$result.Path] = @{
                    Hash = $result.Hash
                    Size = $result.Size
                    IsSymlink = $result.IsSymlink
                    RaceConditionDetected = $result.RaceConditionDetected
                    IntegrityVerified = $result.IntegrityVerified
                }
                
                $totalBytes += $result.Size
                $stats.FilesProcessed++
                $stats.BytesProcessed += $result.Size
                
                if ($result.RaceConditionDetected) {
                    $stats.FilesRaceCondition++
                }
            } else {
                # Write error to log
                Write-HashSmithHashEntry -LogPath $LogPath -FilePath $result.Path -Size $result.Size -Modified $result.Modified -ErrorMessage $result.Error -ErrorCategory $result.ErrorCategory -BasePath $BasePath -IsSymlink $result.IsSymlink -RaceConditionDetected $result.RaceConditionDetected -UseBatching
                
                $errorCount++
                $stats.FilesError++
                
                # Categorize errors
                if ($result.ErrorCategory -in @('IO', 'Unknown')) {
                    $stats.RetriableErrors++
                } else {
                    $stats.NonRetriableErrors++
                }
            }
            
            # Update progress with enhanced display
            if ($ShowProgress -and ((Get-Date) - $lastProgressUpdate).TotalSeconds -ge 2) {
                $percent = [Math]::Round(($processedCount / $Files.Count) * 100, 1)
                $progressBar = "█" * [Math]::Floor($percent / 2) + "░" * (50 - [Math]::Floor($percent / 2))
                
                $throughput = if ($totalBytes -gt 0) { " • $('{0:N1} MB/s' -f (($totalBytes / 1MB) / ((Get-Date) - $stats.StartTime).TotalSeconds))" } else { "" }
                $eta = if ($percent -gt 0) { 
                    $elapsed = ((Get-Date) - $stats.StartTime).TotalSeconds
                    $remaining = ($elapsed / $percent) * (100 - $percent)
                    " • ETA: $('{0:N0}s' -f $remaining)"
                } else { "" }
                
                Write-Host "`r⚡ Processing: [" -NoNewline -ForegroundColor Magenta
                Write-Host $progressBar -NoNewline -ForegroundColor $(if($percent -lt 50){'Yellow'}elseif($percent -lt 80){'Cyan'}else{'Green'})
                Write-Host "] $percent% ($processedCount/$($Files.Count))$throughput$eta" -NoNewline -ForegroundColor White
                
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
        Write-Host "`r" + " " * 120 + "`r" -NoNewline  # Clear progress line
    }
    
    Write-HashSmithLog -Message "Enhanced file processing completed" -Level SUCCESS -Component 'PROCESS'
    Write-HashSmithLog -Message "Files processed successfully: $($processedCount - $errorCount)" -Level INFO -Component 'PROCESS'
    Write-HashSmithLog -Message "Files failed: $errorCount" -Level INFO -Component 'PROCESS'
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

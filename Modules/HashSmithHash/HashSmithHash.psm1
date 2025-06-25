<#
.SYNOPSIS
    Hash computation engine for HashSmith

.DESCRIPTION
    This module provides secure and resilient hash computation capabilities with
    integrity verification, race condition detection, and comprehensive error handling.
    Enhanced with chunked processing for large files to prevent memory exhaustion.
#>

# Import required modules
# Note: Dependencies are handled by the main script import order

#region Public Functions

<#
.SYNOPSIS
    Computes hash using chunked streaming for memory efficiency

.DESCRIPTION
    Processes large files in chunks to prevent memory exhaustion and improve
    performance for files >100MB. Uses streaming hash computation with
    TransformBlock/TransformFinalBlock pattern.

.PARAMETER FileStream
    The file stream to process

.PARAMETER HashAlgorithm  
    The hash algorithm instance

.PARAMETER ChunkSizeMB
    Chunk size in megabytes (default: 64MB)

.EXAMPLE
    $hash = Get-HashSmithStreamingHash -FileStream $stream -HashAlgorithm $hasher
#>
function Get-HashSmithStreamingHash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileStream]$FileStream,
        
        [Parameter(Mandatory)]
        [System.Security.Cryptography.HashAlgorithm]$HashAlgorithm,
        
        [ValidateRange(1, 512)]
        [int]$ChunkSizeMB = 64
    )
    
    $chunkSize = $ChunkSizeMB * 1MB
    $buffer = [byte[]]::new($chunkSize)
    $totalRead = 0
    $fileSize = $FileStream.Length
    
    try {
        while ($totalRead -lt $fileSize) {
            $bytesToRead = [Math]::Min($chunkSize, $fileSize - $totalRead)
            $bytesRead = $FileStream.Read($buffer, 0, $bytesToRead)
            
            if ($bytesRead -eq 0) { break }
            
            if ($totalRead + $bytesRead -eq $fileSize) {
                # Final block
                $HashAlgorithm.TransformFinalBlock($buffer, 0, $bytesRead) | Out-Null
            } else {
                # Intermediate block  
                $HashAlgorithm.TransformBlock($buffer, 0, $bytesRead, $null, 0) | Out-Null
            }
            
            $totalRead += $bytesRead
            
            # Yield CPU every 256MB to prevent monopolization
            if ($totalRead % (256MB) -eq 0) {
                Start-Sleep -Milliseconds 1
            }
        }
        
        return $HashAlgorithm.Hash
    }
    catch {
        Write-HashSmithLog -Message "Streaming hash error: $($_.Exception.Message)" -Level ERROR -Component 'HASH'
        throw
    }
}

<#
.SYNOPSIS
    Computes file hash with comprehensive error handling and integrity verification

.DESCRIPTION
    Safely computes cryptographic hashes for files with retry logic, race condition
    detection, integrity verification, and circuit breaker pattern for resilience.
    Enhanced with chunked processing for large files and dynamic buffer optimization.

.PARAMETER Path
    The file path to compute hash for

.PARAMETER Algorithm
    The hash algorithm to use (MD5, SHA1, SHA256, SHA512)

.PARAMETER RetryCount
    Number of retry attempts for transient failures

.PARAMETER TimeoutSeconds
    Timeout for file operations in seconds

.PARAMETER VerifyIntegrity
    Verify file integrity before and after processing

.PARAMETER StrictMode
    Enable strict mode with maximum validation

.PARAMETER PreIntegritySnapshot
    Pre-computed integrity snapshot for race condition detection

.EXAMPLE
    $result = Get-HashSmithFileHashSafe -Path $filePath -Algorithm "SHA256" -VerifyIntegrity
#>
function Get-HashSmithFileHashSafe {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        
        [ValidateSet('MD5', 'SHA1', 'SHA256', 'SHA512')]
        [string]$Algorithm = 'MD5',
        
        [ValidateRange(1, 10)]
        [int]$RetryCount = 3,
        
        [ValidateRange(10, 300)]
        [int]$TimeoutSeconds = 30,
        
        [switch]$VerifyIntegrity,
        
        [switch]$StrictMode,
        
        [hashtable]$PreIntegritySnapshot
    )
    
    $result = @{
        Success = $false
        Hash = $null
        Size = 0
        Error = $null
        Attempts = 0
        Duration = 0
        Integrity = $null
        ErrorCategory = 'Unknown'
        RaceConditionDetected = $false
    }
    
    $startTime = Get-Date
    $config = Get-HashSmithConfig
    
    # Pre-process integrity check
    if ($StrictMode -or $VerifyIntegrity) {
        if (-not $PreIntegritySnapshot) {
            $PreIntegritySnapshot = Get-HashSmithFileIntegritySnapshot -Path $Path
        }
        
        if (-not $PreIntegritySnapshot) {
            $result.Error = "Could not get initial file integrity snapshot"
            $result.ErrorCategory = 'Integrity'
            return $result
        }
    }
    
    for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
        $result.Attempts = $attempt
        
        # Check circuit breaker
        if (-not (Test-HashSmithCircuitBreaker -Component 'HASH')) {
            $result.Error = "Circuit breaker is open"
            $result.ErrorCategory = 'CircuitBreaker'
            break
        }
        
        try {
            Write-HashSmithLog -Message "Computing $Algorithm hash (attempt $attempt): $([System.IO.Path]::GetFileName($Path))" -Level DEBUG -Component 'HASH'
            
            # Normalize path
            $normalizedPath = Get-HashSmithNormalizedPath -Path $Path
            
            # Verify file exists and is accessible
            if (-not (Test-Path -LiteralPath $normalizedPath)) {
                throw [System.IO.FileNotFoundException]::new("File not found: $Path")
            }
            
            # Test file accessibility with timeout
            if (-not (Test-HashSmithFileAccessible -Path $normalizedPath -TimeoutMs ($TimeoutSeconds * 1000))) {
                throw [System.IO.IOException]::new("File is locked or inaccessible: $Path")
            }
            
            # Get current file info
            $currentFileInfo = [System.IO.FileInfo]::new($normalizedPath)
            $result.Size = $currentFileInfo.Length
            
            # Race condition detection
            if ($PreIntegritySnapshot) {
                $currentSnapshot = Get-HashSmithFileIntegritySnapshot -Path $normalizedPath
                if (-not (Test-HashSmithFileIntegrityMatch -Snapshot1 $PreIntegritySnapshot -Snapshot2 $currentSnapshot)) {
                    $result.RaceConditionDetected = $true
                    Add-HashSmithStatistic -Name 'FilesRaceCondition' -Amount 1
                    
                    if ($StrictMode) {
                        throw [System.InvalidOperationException]::new("File modified between discovery and processing (race condition detected)")
                    } else {
                        Write-HashSmithLog -Message "Race condition detected but continuing: $([System.IO.Path]::GetFileName($Path))" -Level WARN -Component 'HASH'
                        # Update the snapshot for post-processing check
                        $PreIntegritySnapshot = $currentSnapshot
                    }
                }
            }
            
            # Compute hash using streaming approach with dynamic buffer optimization
            $hashAlgorithm = [System.Security.Cryptography.HashAlgorithm]::Create($Algorithm)
            $fileStream = $null
            $showSpinner = $currentFileInfo.Length -gt (10MB)  # Lower threshold to show spinner sooner
            
            try {
                # Show spinner for large files using simple approach
                if ($showSpinner) {
                    $fileName = [System.IO.Path]::GetFileName($Path)
                    $sizeText = "$('{0:N1} MB' -f ($currentFileInfo.Length / 1MB))"
                    
                    # Estimate processing time and show spinner
                    $estimatedSeconds = [Math]::Max(2, [Math]::Min(10, ($currentFileInfo.Length / 100MB) * 3))
                    Show-HashSmithSpinner -Message "Processing large file: $fileName ($sizeText)" -Seconds $estimatedSeconds
                }
                
                # Use FileShare.Read and FileOptions.SequentialScan for better performance and locked file access
                $fileStream = [System.IO.FileStream]::new($normalizedPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read, 4096, [System.IO.FileOptions]::SequentialScan)
                
                # Use chunked processing for large files (>100MB)
                if ($currentFileInfo.Length -gt 100MB) {
                    Write-HashSmithLog -Message "Using chunked processing for large file: $([System.IO.Path]::GetFileName($Path))" -Level DEBUG -Component 'HASH'
                    $hashBytes = Get-HashSmithStreamingHash -FileStream $fileStream -HashAlgorithm $hashAlgorithm -ChunkSizeMB 64
                } else {
                    # Standard processing for smaller files with dynamic buffer optimization
                    $bufferSize = Get-HashSmithOptimalBufferSize -Algorithm $Algorithm -FileSize $currentFileInfo.Length
                    $buffer = [byte[]]::new($bufferSize)
                    $totalRead = 0
                    $lastSpinnerUpdate = Get-Date
                    $readOperations = 0
                    
                    # Initialize hash computation
                    if ($currentFileInfo.Length -eq 0) {
                        # Handle zero-byte files explicitly
                        $hashBytes = $hashAlgorithm.ComputeHash([byte[]]::new(0))
                    } else {
                        # Stream-based hash computation with system load reduction
                        while ($totalRead -lt $currentFileInfo.Length) {
                            $bytesRead = $fileStream.Read($buffer, 0, $buffer.Length)
                            if ($bytesRead -eq 0) { break }
                            
                            if ($totalRead + $bytesRead -eq $currentFileInfo.Length) {
                                # Final block
                                $hashAlgorithm.TransformFinalBlock($buffer, 0, $bytesRead) | Out-Null
                            } else {
                                # Intermediate block
                                $hashAlgorithm.TransformBlock($buffer, 0, $bytesRead, $null, 0) | Out-Null
                            }
                            
                            $totalRead += $bytesRead
                            $readOperations++
                            
                            # Add small delay every few operations to reduce system strain
                            if ($readOperations % 50 -eq 0 -and $currentFileInfo.Length -gt 100MB) {
                                Start-Sleep -Milliseconds 10
                            }
                            
                            # Update spinner message for very large files
                            if ($showSpinner -and ((Get-Date) - $lastSpinnerUpdate).TotalSeconds -ge 2) {
                                $progress = ($totalRead / $currentFileInfo.Length) * 100
                                $fileName = [System.IO.Path]::GetFileName($Path)
                                $sizeText = "$('{0:N1} MB' -f ($currentFileInfo.Length / 1MB))"
                                Update-HashSmithSpinner -Message "Processing large file: $fileName ($sizeText) - $($progress.ToString('F1'))%"
                                $lastSpinnerUpdate = Get-Date
                            }
                            
                            # Verify we haven't read more than expected (corruption detection)
                            if ($totalRead -gt $currentFileInfo.Length) {
                                throw [System.InvalidDataException]::new("Read more bytes than file size indicates - possible corruption")
                            }
                        }
                        
                        $hashBytes = $hashAlgorithm.Hash
                    }
                }
                
                # Hash computation completed - no spinner cleanup needed since it's already done
                $result.Hash = [System.BitConverter]::ToString($hashBytes) -replace '-', ''
                $result.Hash = $result.Hash.ToLower()
                
                # Post-process integrity check
                if ($StrictMode -or $VerifyIntegrity) {
                    $postSnapshot = Get-HashSmithFileIntegritySnapshot -Path $normalizedPath
                    if ($PreIntegritySnapshot -and -not (Test-HashSmithFileIntegrityMatch -Snapshot1 $PreIntegritySnapshot -Snapshot2 $postSnapshot)) {
                        throw [System.InvalidOperationException]::new("File integrity verification failed - file changed during processing")
                    }
                    $result.Integrity = $true
                }
                
                $result.Success = $true
                Update-HashSmithCircuitBreaker -IsFailure:$false -Component 'HASH'
                break
                
            } finally {
                # Spinner is self-cleaning, no cleanup needed
                if ($fileStream) { $fileStream.Dispose() }
                if ($hashAlgorithm) { $hashAlgorithm.Dispose() }
            }
            
        }
        catch [System.IO.FileNotFoundException] {
            $result.Error = $_.Exception.Message
            $result.ErrorCategory = 'FileNotFound'
            Add-HashSmithStatistic -Name 'NonRetriableErrors' -Amount 1
            break  # Don't retry for file not found
        }
        catch [System.IO.DirectoryNotFoundException] {
            $result.Error = $_.Exception.Message
            $result.ErrorCategory = 'DirectoryNotFound'
            Add-HashSmithStatistic -Name 'NonRetriableErrors' -Amount 1
            break  # Don't retry for directory not found
        }
        catch [System.InvalidOperationException] {
            $result.Error = $_.Exception.Message
            $result.ErrorCategory = 'Integrity'
            Add-HashSmithStatistic -Name 'NonRetriableErrors' -Amount 1
            break  # Don't retry for integrity violations
        }
        catch [System.UnauthorizedAccessException] {
            $result.Error = $_.Exception.Message
            $result.ErrorCategory = 'AccessDenied'
            Add-HashSmithStatistic -Name 'NonRetriableErrors' -Amount 1
            break  # Don't retry for access denied
        }
        catch [System.IO.IOException] {
            $result.Error = $_.Exception.Message
            $result.ErrorCategory = 'IO'
            Add-HashSmithStatistic -Name 'RetriableErrors' -Amount 1
            Write-HashSmithLog -Message "I/O error during hash computation (attempt $attempt): $($_.Exception.Message)" -Level WARN -Component 'HASH'
            Update-HashSmithCircuitBreaker -IsFailure:$true -Component 'HASH'
        }
        catch {
            $result.Error = $_.Exception.Message
            $result.ErrorCategory = 'Unknown'
            Add-HashSmithStatistic -Name 'RetriableErrors' -Amount 1
            Write-HashSmithLog -Message "Unexpected error during hash computation (attempt $attempt): $($_.Exception.Message)" -Level WARN -Component 'HASH'
            Update-HashSmithCircuitBreaker -IsFailure:$true -Component 'HASH'
        }
        
        # Exponential backoff for retries
        if ($attempt -lt $RetryCount -and $result.ErrorCategory -in @('IO', 'Unknown')) {
            $delay = [Math]::Min(500 * [Math]::Pow(2, $attempt - 1), $config.MaxRetryDelay)
            Write-HashSmithLog -Message "Retrying in ${delay}ms..." -Level DEBUG -Component 'HASH'
            Start-Sleep -Milliseconds $delay
        }
    }
    
    $result.Duration = (Get-Date) - $startTime
    
    if ($result.Success) {
        Write-HashSmithLog -Message "Hash computed successfully: $([System.IO.Path]::GetFileName($Path))" -Level DEBUG -Component 'HASH'
    } else {
        Write-HashSmithLog -Message "Hash computation failed after $($result.Attempts) attempts: $([System.IO.Path]::GetFileName($Path))" -Level ERROR -Component 'HASH'
        $stats = Get-HashSmithStatistics
        $processingErrors = $stats.ProcessingErrors
        if ($processingErrors -is [System.Collections.Concurrent.ConcurrentBag[object]]) {
            $processingErrors.Add(@{
                Path = $Path
                Error = $result.Error
                ErrorCategory = $result.ErrorCategory
                Attempts = $result.Attempts
                RaceCondition = $result.RaceConditionDetected
                Timestamp = Get-Date
            })
        }
    }
    
    return $result
}

#endregion

# Export public functions
Export-ModuleMember -Function @(
    'Get-HashSmithFileHashSafe'
)
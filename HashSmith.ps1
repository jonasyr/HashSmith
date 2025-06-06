<#
.SYNOPSIS
    Creates MD5 checksums for all files with HIGH-PERFORMANCE parallel processing.

.PARAMETER SourceDir
    Path to the source directory to process.

.PARAMETER LogFile
    Output path for the MD5 log file.

.PARAMETER MD5Tool
    Path to MD5 executable.

.PARAMETER Resume
    Resume from existing log file.

.PARAMETER ExcludePatterns
    Array of file patterns to exclude.

.PARAMETER WhatIf
    Show what would be processed without actually generating checksums.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$SourceDir,
    
    [Parameter()]
    [string]$LogFile,
    
    [Parameter()]
    [string]$MD5Tool,
    
    [Parameter()]
    [switch]$Resume,
    
    [Parameter()]
    [string[]]$ExcludePatterns = @(),
    
    [Parameter()]
    [switch]$WhatIf
)

# Validate source directory
if (-not (Test-Path $SourceDir -PathType Container)) {
    Write-Error "Source directory '$SourceDir' does not exist."
    exit 1
}

# Auto-detect MD5 tool
if (-not $MD5Tool) {
    $CommonPaths = @(
        "C:\Peano\Tools\MD5-x64.exe",
        "C:\Tools\MD5-x64.exe",
        ".\MD5-x64.exe"
    )
    
    foreach ($path in $CommonPaths) {
        if (Test-Path $path) {
            $MD5Tool = $path
            break
        }
    }
    
    if (-not $MD5Tool) {
        Write-Error "MD5 tool not found. Please specify -MD5Tool parameter."
        exit 1
    }
}

# Validate MD5 tool
if (-not (Test-Path $MD5Tool)) {
    Write-Error "MD5 tool not found at: $MD5Tool"
    exit 1
}

# Auto-generate log file if not specified
if (-not $LogFile) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $sourceName = Split-Path $SourceDir -Leaf
    $LogFile = Join-Path $SourceDir "$sourceName`_$timestamp.md5"
}

# Resolve paths
$SourceDir = Resolve-Path $SourceDir
$LogFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LogFile)

# Display header
Write-Host ""
Write-Host "+============================================================+" -ForegroundColor Cyan
Write-Host "|          HIGH-PERFORMANCE MD5 Checksum Generator          |" -ForegroundColor Cyan
Write-Host "+============================================================+" -ForegroundColor Cyan
Write-Host ""
Write-Host "[*] Source Directory: $SourceDir" -ForegroundColor Green
Write-Host "[*] Log File: $LogFile" -ForegroundColor Green
Write-Host "[*] MD5 Tool: $MD5Tool" -ForegroundColor Green
Write-Host ""

# Helper functions
function Write-LogMessage {
    param($Message, $Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    switch ($Level) {
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "WARN"  { Write-Host $logEntry -ForegroundColor Yellow }
        "INFO"  { Write-Host $logEntry -ForegroundColor White }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
    }
}

function Format-FileSize {
    param([long]$Bytes)
    if ($Bytes -eq 0) { return "0 B" }
    
    $sizes = @("B", "KB", "MB", "GB", "TB")
    $index = 0
    $size = [double]$Bytes
    
    while ($size -ge 1024 -and $index -lt ($sizes.Count - 1)) {
        $size = $size / 1024
        $index++
    }
    
    return "{0:N2} {1}" -f $size, $sizes[$index]
}

function Format-Duration {
    param([TimeSpan]$Duration)
    if ($Duration.Days -gt 0) {
        return "{0}d {1:hh\:mm\:ss}" -f $Duration.Days, $Duration
    } else {
        return "{0:hh\:mm\:ss}" -f $Duration
    }
}

function Write-BatchMessage {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [ref]$RecentMessages
    )
    
    # Clear previous batch messages (move cursor up and clear lines)
    if ($RecentMessages.Value -and $RecentMessages.Value.Count -gt 0) {
        for ($i = 0; $i -lt $RecentMessages.Value.Count; $i++) {
            Write-Host "`e[1A`e[2K" -NoNewline  # Move up one line and clear it
        }
    }
    
    # Initialize if null
    if (-not $RecentMessages.Value) {
        $RecentMessages.Value = @()
    }
    
    # Add new message to recent messages (keep last 3)
    $RecentMessages.Value += $Message
    if ($RecentMessages.Value.Count -gt 3) {
        $RecentMessages.Value = $RecentMessages.Value[-3..-1]
    }
    
    # Display all recent messages
    foreach ($msg in $RecentMessages.Value) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logEntry = "[$timestamp] [$Level] $msg"
        Write-Host $logEntry -ForegroundColor White
    }
}

# FIXED: Robust hash extraction function
function Extract-MD5Hash {
    param([string]$MD5Output)
    
    try {
        # Return null if input is null or empty
        if ([string]::IsNullOrWhiteSpace($MD5Output)) {
            return $null
        }
        
        # Check for common failure patterns that indicate we should use PowerShell fallback
        if ($MD5Output -match "No file found" -or 
            $MD5Output -match "Verkn.*pfung" -or 
            $MD5Output -match "error code 5" -or
            $MD5Output -match "Access is denied" -or
            $MD5Output -match "cannot access") {
            return $null  # Signal that fallback is needed
        }
        
        # Handle multi-line output by splitting into lines
        $lines = $MD5Output -split "`n|`r`n|`r"
        
        # Method 1: Look for line with = sign (main hash line)
        foreach ($line in $lines) {
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                $line = $line.Trim()
                if ($line -match '=\s*([a-fA-F0-9]{32})') {
                    return $Matches[1].ToLower()
                }
            }
        }
        
        # Method 2: Find = sign and extract hash after it (fallback for single line)
        $equalPos = $MD5Output.IndexOf('=')
        if ($equalPos -ge 0 -and $equalPos -lt ($MD5Output.Length - 32)) {
            $afterEqual = $MD5Output.Substring($equalPos + 1).Trim()
            $words = $afterEqual -split '\s+'
            foreach ($word in $words) {
                if ($word -and $word.Length -eq 32 -and $word -match '^[a-fA-F0-9]{32}$') {
                    return $word.ToLower()
                }
            }
        }
        
        # Method 3: Use regex to find 32-character hex string anywhere
        if ($MD5Output -match '([a-fA-F0-9]{32})') {
            return $Matches[1].ToLower()
        }
        
        # Method 4: Scan for 32-char hex string anywhere (final fallback)  
        for ($pos = 0; $pos -le ($MD5Output.Length - 32); $pos++) {
            $candidate = $MD5Output.Substring($pos, 32)
            if ($candidate -match '^[a-fA-F0-9]{32}$') {
                return $candidate.ToLower()
            }
        }
        
        return $null
    } catch {
        # If any error occurs in hash extraction, return null
        return $null
    }
}

# FIXED: Robust file processing function for parallel execution
function Process-FileForMD5 {
    param(
        [string]$FilePath,
        [string]$MD5ToolPath,
        [long]$FileLength,
        [string]$FileName
    )
    
    $result = @{
        FullName = $FilePath
        Length = $FileLength
        Name = $FileName
        Success = $false
        Hash = $null
        Error = $null
        UsedFallback = $false
    }
    
    try {
        # Validate inputs
        if ([string]::IsNullOrWhiteSpace($FilePath) -or 
            [string]::IsNullOrWhiteSpace($MD5ToolPath) -or
            -not (Test-Path $FilePath -PathType Leaf)) {
            throw "Invalid file path or file does not exist"
        }
        
        # Try MD5 tool first
        $md5Output = $null
        try {
            $md5Output = & $MD5ToolPath $FilePath -ContinueOnErrors -TextMode 2>&1
            $exitCode = $LASTEXITCODE
        } catch {
            $exitCode = -1
            $md5Output = $_.Exception.Message
        }
        
        # Extract hash if tool succeeded
        $hash = $null
        if ($exitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($md5Output)) {
            $hash = Extract-MD5Hash $md5Output
        }
        
        # PowerShell fallback if MD5 tool failed or hash extraction failed
        if (-not $hash) {
            try {
                $psHashObj = Get-FileHash -Path $FilePath -Algorithm MD5 -ErrorAction Stop
                if ($psHashObj -and $psHashObj.Hash) {
                    $hash = $psHashObj.Hash.ToLower()
                    $result.UsedFallback = $true
                }
            } catch {
                # Determine specific error type
                $errorMsg = $_.Exception.Message
                if ($errorMsg -match "because it is being used by another process") {
                    throw "File is locked or in use: $FileName"
                } elseif ($errorMsg -match "Access.*denied" -or $errorMsg -match "UnauthorizedAccess") {
                    throw "Access denied: $FileName"
                } elseif ($errorMsg -match "path.*not found" -or $errorMsg -match "FileNotFound") {
                    throw "File not found: $FileName"
                } else {
                    throw "Could not access file: $errorMsg"
                }
            }
        }
        
        # Final validation
        if ($hash -and $hash -match '^[a-fA-F0-9]{32}$') {
            $result.Success = $true
            $result.Hash = $hash
        } else {
            throw "Failed to generate valid MD5 hash"
        }
        
    } catch {
        $result.Error = $_.Exception.Message
        $result.Success = $false
    }
    
    return $result
}

# Main processing
$stopwatch = $null

try {
    Write-LogMessage "[*] Starting HIGH-PERFORMANCE MD5 checksum generation..." "INFO"
    
    # Collect all files
    Write-LogMessage "[*] Scanning directory for files..." "INFO"
    $allFiles = Get-ChildItem -Path $SourceDir -Recurse -File -ErrorAction SilentlyContinue
    
    # Apply exclusion patterns
    if ($ExcludePatterns.Count -gt 0) {
        Write-LogMessage "[*] Applying exclusion patterns: $($ExcludePatterns -join ', ')" "INFO"
        foreach ($pattern in $ExcludePatterns) {
            $allFiles = $allFiles | Where-Object { $_.Name -notlike $pattern }
        }
    }
    
    $totalFiles = $allFiles.Count
    $totalSize = ($allFiles | Measure-Object -Property Length -Sum).Sum
    
    if ($totalFiles -eq 0) {
        Write-LogMessage "[!] No files found to process" "WARN"
        exit 0
    }
    
    Write-LogMessage "[*] Found $totalFiles files ($(Format-FileSize $totalSize))" "INFO"
    
    # Test MD5 tool with first file
    if ($allFiles.Count -gt 0) {
        $testFile = $allFiles[0]
        Write-LogMessage "[*] Testing MD5 tool with: $($testFile.Name)" "INFO"
        
        $testResult = Process-FileForMD5 -FilePath $testFile.FullName -MD5ToolPath $MD5Tool -FileLength $testFile.Length -FileName $testFile.Name
        
        if ($testResult.Success) {
            if ($testResult.UsedFallback) {
                Write-LogMessage "[+] PowerShell fallback test SUCCESSFUL: $($testResult.Hash)" "SUCCESS"
                Write-LogMessage "[!] Note: MD5 tool failed, using PowerShell fallback for special files" "WARN"
            } else {
                Write-LogMessage "[+] MD5 tool test SUCCESSFUL: $($testResult.Hash)" "SUCCESS"
            }
        } else {
            Write-LogMessage "[!] Both MD5 tool and PowerShell fallback failed: $($testResult.Error)" "ERROR"
            exit 1
        }
        
        Write-Host ""
    }
    
    # Handle resume functionality
    $startIndex = 0
    if ($Resume -and (Test-Path $LogFile)) {
        Write-LogMessage "[*] Resume mode enabled" "INFO"
        $content = Get-Content $LogFile -ErrorAction SilentlyContinue
        if ($content) {
            # Count lines that contain successful MD5 hashes (not error lines or empty lines)
            $processedLines = $content | Where-Object { 
                $_ -match '^[^#].*=\s*[a-fA-F0-9]{32}.*size:\s*\d+\s*bytes' 
            }
            $startIndex = $processedLines.Count
            
            # Also count error lines for total processed count
            $errorLines = $content | Where-Object { $_ -match '^#\s*ERROR:' }
            $totalProcessedInLog = $startIndex + $errorLines.Count
            
            Write-LogMessage "[*] Log analysis: $startIndex successful + $($errorLines.Count) errors = $totalProcessedInLog total processed" "INFO"
            Write-LogMessage "[*] Resuming from file $($startIndex + 1)" "INFO"
            
            if ($startIndex -gt 0) {
                Write-Host ""
                Write-Host "[*] RESUME SAFETY CHECK:" -ForegroundColor Yellow
                Write-Host "    - Existing log file: $LogFile" -ForegroundColor Cyan
                Write-Host "    - Successfully processed: $startIndex files" -ForegroundColor Cyan
                Write-Host "    - Errors encountered: $($errorLines.Count) files" -ForegroundColor Cyan
                Write-Host "    - Total attempted: $totalProcessedInLog files" -ForegroundColor Cyan
                Write-Host "    - Will skip these files and continue from where left off" -ForegroundColor Cyan
                Write-Host "    - This is SAFE and will not duplicate work" -ForegroundColor Green
                Write-Host ""
            }
        } else {
            Write-LogMessage "[*] Log file exists but is empty, starting from beginning" "INFO"
        }
    } elseif (-not $Resume -and (Test-Path $LogFile)) {
        Write-LogMessage "[*] Removing existing log file (Resume not enabled)" "INFO"
        Remove-Item $LogFile -Force -ErrorAction SilentlyContinue
    }
    
    # WhatIf mode
    if ($WhatIf) {
        Write-Host "+============================================================+" -ForegroundColor Yellow
        Write-Host "|                   [?] WHAT-IF MODE                        |" -ForegroundColor Yellow
        Write-Host "+============================================================+" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "[*] Files to process: $($totalFiles - $startIndex)" -ForegroundColor Cyan
        Write-Host "[*] Total size: $(Format-FileSize ($allFiles[$startIndex..($totalFiles-1)] | Measure-Object -Property Length -Sum).Sum)" -ForegroundColor Cyan
        Write-Host "[*] Log file: $LogFile" -ForegroundColor Cyan
        return
    }
    
    # === PARALLEL BATCH PROCESSING SETUP ===
    $cpuCores = [Environment]::ProcessorCount
    $batchSize = $cpuCores * 2  # Optimal thread count
    $maxConcurrency = $batchSize
    
    # Check PowerShell version for parallel processing
    $useParallel = $PSVersionTable.PSVersion.Major -ge 7
    
    if ($useParallel) {
        Write-LogMessage "[*] PARALLEL MODE: Using $batchSize threads on $cpuCores CPU cores" "SUCCESS"
    } else {
        Write-LogMessage "[!] SEQUENTIAL MODE: PowerShell 7+ required for parallel processing" "WARN"
        $batchSize = 1
    }
    
    # Initialize tracking
    $processedCount = $startIndex
    $processedSize = 0
    $errorCount = 0
    $lastTwoLines = @()
    $persistentErrors = @()  # Store recent errors for progress display
    $recentBatchMessages = @()  # Store recent batch messages for display
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    # Calculate batches
    $remainingFiles = $allFiles[$startIndex..($totalFiles-1)]
    $totalBatches = [Math]::Ceiling($remainingFiles.Count / $batchSize)
    
    Write-LogMessage "[*] Processing $($remainingFiles.Count) files in $totalBatches batches" "INFO"
    Write-Host ""
    
    # === MAIN PARALLEL BATCH PROCESSING LOOP ===
    for ($batchNum = 0; $batchNum -lt $totalBatches; $batchNum++) {
        $batchStart = $batchNum * $batchSize
        $batchEnd = [Math]::Min($batchStart + $batchSize - 1, $remainingFiles.Count - 1)
        $currentBatch = $remainingFiles[$batchStart..$batchEnd]
        
        # Display batch progress with rolling message display (for ALL batches)
        $batchMessage = "[*] Processing batch $($batchNum + 1)/$totalBatches ($($currentBatch.Count) files)"
        Write-BatchMessage -Message $batchMessage -Level "INFO" -RecentMessages ([ref]$recentBatchMessages)
        
        if ($useParallel) {
            # PARALLEL PROCESSING - FIXED to use the robust function
            $batchResults = $currentBatch | ForEach-Object -Parallel {
                # Import the function into the parallel runspace
                function Extract-MD5Hash {
                    param([string]$MD5Output)
                    
                    try {
                        if ([string]::IsNullOrWhiteSpace($MD5Output)) {
                            return $null
                        }
                        
                        if ($MD5Output -match "No file found" -or 
                            $MD5Output -match "Verkn.*pfung" -or 
                            $MD5Output -match "error code 5" -or
                            $MD5Output -match "Access is denied" -or
                            $MD5Output -match "cannot access") {
                            return $null
                        }
                        
                        $lines = $MD5Output -split "`n|`r`n|`r"
                        
                        foreach ($line in $lines) {
                            if (-not [string]::IsNullOrWhiteSpace($line)) {
                                $line = $line.Trim()
                                if ($line -match '=\s*([a-fA-F0-9]{32})') {
                                    return $Matches[1].ToLower()
                                }
                            }
                        }
                        
                        $equalPos = $MD5Output.IndexOf('=')
                        if ($equalPos -ge 0 -and $equalPos -lt ($MD5Output.Length - 32)) {
                            $afterEqual = $MD5Output.Substring($equalPos + 1).Trim()
                            $words = $afterEqual -split '\s+'
                            foreach ($word in $words) {
                                if ($word -and $word.Length -eq 32 -and $word -match '^[a-fA-F0-9]{32}$') {
                                    return $word.ToLower()
                                }
                            }
                        }
                        
                        if ($MD5Output -match '([a-fA-F0-9]{32})') {
                            return $Matches[1].ToLower()
                        }
                        
                        for ($pos = 0; $pos -le ($MD5Output.Length - 32); $pos++) {
                            $candidate = $MD5Output.Substring($pos, 32)
                            if ($candidate -match '^[a-fA-F0-9]{32}$') {
                                return $candidate.ToLower()
                            }
                        }
                        
                        return $null
                    } catch {
                        return $null
                    }
                }
                
                function Process-FileForMD5 {
                    param(
                        [string]$FilePath,
                        [string]$MD5ToolPath,
                        [long]$FileLength,
                        [string]$FileName
                    )
                    
                    $result = @{
                        FullName = $FilePath
                        Length = $FileLength
                        Name = $FileName
                        Success = $false
                        Hash = $null
                        Error = $null
                        UsedFallback = $false
                    }
                    
                    try {
                        if ([string]::IsNullOrWhiteSpace($FilePath) -or 
                            [string]::IsNullOrWhiteSpace($MD5ToolPath) -or
                            -not (Test-Path $FilePath -PathType Leaf)) {
                            throw "Invalid file path or file does not exist"
                        }
                        
                        $md5Output = $null
                        try {
                            $md5Output = & $MD5ToolPath $FilePath -ContinueOnErrors -TextMode 2>&1
                            $exitCode = $LASTEXITCODE
                        } catch {
                            $exitCode = -1
                            $md5Output = $_.Exception.Message
                        }
                        
                        $hash = $null
                        if ($exitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($md5Output)) {
                            $hash = Extract-MD5Hash $md5Output
                        }
                        
                        if (-not $hash) {
                            try {
                                $psHashObj = Get-FileHash -Path $FilePath -Algorithm MD5 -ErrorAction Stop
                                if ($psHashObj -and $psHashObj.Hash) {
                                    $hash = $psHashObj.Hash.ToLower()
                                    $result.UsedFallback = $true
                                }
                            } catch {
                                $errorMsg = $_.Exception.Message
                                if ($errorMsg -match "because it is being used by another process") {
                                    throw "File is locked or in use: $FileName"
                                } elseif ($errorMsg -match "Access.*denied" -or $errorMsg -match "UnauthorizedAccess") {
                                    throw "Access denied: $FileName"
                                } elseif ($errorMsg -match "path.*not found" -or $errorMsg -match "FileNotFound") {
                                    throw "File not found: $FileName"
                                } else {
                                    throw "Could not access file: $errorMsg"
                                }
                            }
                        }
                        
                        if ($hash -and $hash -match '^[a-fA-F0-9]{32}$') {
                            $result.Success = $true
                            $result.Hash = $hash
                        } else {
                            throw "Failed to generate valid MD5 hash"
                        }
                        
                    } catch {
                        $result.Error = $_.Exception.Message
                        $result.Success = $false
                    }
                    
                    return $result
                }
                
                # Use the robust function
                $file = $_
                $MD5ToolPath = $using:MD5Tool
                
                return Process-FileForMD5 -FilePath $file.FullName -MD5ToolPath $MD5ToolPath -FileLength $file.Length -FileName $file.Name
                
            } -ThrottleLimit $maxConcurrency
        } else {
            # SEQUENTIAL PROCESSING - Use the robust function
            $batchResults = @()
            foreach ($file in $currentBatch) {
                $result = Process-FileForMD5 -FilePath $file.FullName -MD5ToolPath $MD5Tool -FileLength $file.Length -FileName $file.Name
                $batchResults += $result
            }
        }
        
        # Process batch results - WRITE TO LOG
        $batchLines = @()
        foreach ($result in $batchResults) {
            $processedCount++
            
            if ($result.Success) {
                $logLine = "$($result.FullName) = $($result.Hash), size: $($result.Length) bytes"
                $batchLines += $logLine
                $processedSize += $result.Length
                
                $lastTwoLines += "[OK] $($result.Name)"
            } else {
                $errorCount++
                $errorLine = "# ERROR: Error processing " + $result.FullName + " - " + $result.Error
                $batchLines += $errorLine
                
                # Add to persistent errors (keep last 3)
                $persistentErrors += "[ERR] $($result.Name): $($result.Error)"
                if ($persistentErrors.Count -gt 3) {
                    $persistentErrors = $persistentErrors[-3..-1]
                }
                
                # Clear rolling batch messages temporarily to show error immediately
                if ($recentBatchMessages -and $recentBatchMessages.Count -gt 0) {
                    for ($i = 0; $i -lt $recentBatchMessages.Count; $i++) {
                        Write-Host "`e[1A`e[2K" -NoNewline
                    }
                }
                
                # Log the error immediately with regular logging (persistent)
                Write-LogMessage "[!] ERROR: $($result.Name) - $($result.Error)" "ERROR"
                
                # Redisplay the batch messages after the error
                if ($recentBatchMessages) {
                    foreach ($msg in $recentBatchMessages) {
                        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                        $logEntry = "[$timestamp] [INFO] $msg"
                        Write-Host $logEntry -ForegroundColor White
                    }
                }
                
                $lastTwoLines += "[ERR] $($result.Name)"
            }
            
            if ($lastTwoLines.Count -gt 2) {
                $lastTwoLines = $lastTwoLines[-2..-1]
            }
        }
        
        # Batch write to log file for performance
        if ($batchLines.Count -gt 0) {
            Add-Content -Path $LogFile -Value $batchLines
        }
        
        # Update progress
        $percentComplete = [int](($processedCount / $totalFiles) * 100)
        $elapsed = $stopwatch.Elapsed
        
        if ($processedCount -gt $startIndex) {
            $avgTimePerFile = $elapsed.TotalSeconds / ($processedCount - $startIndex)
            $remaining = $totalFiles - $processedCount
            $etaSeconds = $avgTimePerFile * $remaining
            $eta = [TimeSpan]::FromSeconds($etaSeconds)
            
            $speed = if ($elapsed.TotalSeconds -gt 0) { 
                [int](($processedCount - $startIndex) / $elapsed.TotalSeconds) 
            } else { 0 }
            
            $activity = "[>] BATCH PROCESSING MD5 checksums ($processedCount/$totalFiles)"
            $modeInfo = if($useParallel){"P$batchSize"}else{"S"}
            $status = "$speed f/s | $(Format-Duration $eta) | $(Format-FileSize $processedSize) | E:$errorCount | $modeInfo | $($batchNum + 1)/$totalBatches"
            
            Write-Progress -Activity $activity -Status $status -PercentComplete $percentComplete
        }
    }
    
    # Clear the rolling batch messages and show completion
    if ($recentBatchMessages -and $recentBatchMessages.Count -gt 0) {
        for ($i = 0; $i -lt $recentBatchMessages.Count; $i++) {
            Write-Host "`e[1A`e[2K" -NoNewline  # Move up one line and clear it
        }
    }
    Write-LogMessage "[+] Batch processing completed successfully!" "SUCCESS"
    
    $stopwatch.Stop()
    
    # Generate total MD5
    Write-LogMessage "[*] Generating total directory MD5..." "INFO"
    Write-Progress -Activity "[>] Generating total MD5..." -Status "Calculating..." -PercentComplete 95
    
    try {
        Add-Content -Path $LogFile -Value ""
        $totalMd5Output = & $MD5Tool $SourceDir -r -ContinueOnErrors -TotalMD5 -TextMode 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            $totalHash = Extract-MD5Hash $totalMd5Output
            
            if ($totalHash) {
                Add-Content -Path $LogFile -Value "TotalMD5 = $totalHash"
                
                $processedFiles = $processedCount - $startIndex
                $summaryLine = "$processedFiles files checked ($processedSize bytes, $(Format-FileSize $processedSize), $($stopwatch.Elapsed.TotalSeconds.ToString("F1")) sec)."
                Add-Content -Path $LogFile -Value $summaryLine
                
                Write-LogMessage "[+] Total MD5 generated successfully: $totalHash" "SUCCESS"
            } else {
                Write-LogMessage "[!] Could not extract TotalMD5 hash" "WARN"
                Add-Content -Path $LogFile -Value $totalMd5Output
            }
        } else {
            Write-LogMessage "[!] Total MD5 generation failed" "WARN"
        }
    } catch {
        Write-LogMessage "[!] Could not generate total MD5: $($_.Exception.Message)" "WARN"
    }
    
    # Final statistics
    $successCount = $processedCount - $startIndex - $errorCount
    $totalElapsed = Format-Duration $stopwatch.Elapsed
    
    Write-Progress -Activity "[+] Complete" -Status "Done" -PercentComplete 100
    Start-Sleep -Seconds 1
    Write-Progress -Activity "[+] Complete" -Completed
    
    # Summary
    Write-Host ""
    Write-Host "+============================================================+" -ForegroundColor Green
    Write-Host "|                [+] TURBO OPERATION COMPLETE               |" -ForegroundColor Green
    Write-Host "+============================================================+" -ForegroundColor Green
    Write-Host ""
    Write-Host "[*] Total files processed: $successCount" -ForegroundColor White
    Write-Host "[*] Errors encountered: $errorCount" -ForegroundColor $(if($errorCount -gt 0){"Red"}else{"Green"})
    Write-Host "[*] Total data processed: $(Format-FileSize $processedSize)" -ForegroundColor Cyan
    Write-Host "[*] Total time: $totalElapsed" -ForegroundColor Cyan
    Write-Host "[*] Processing mode: $(if($useParallel){"PARALLEL ($batchSize threads)"}else{"Sequential"})" -ForegroundColor Yellow
    Write-Host "[*] Log file: $LogFile" -ForegroundColor Yellow
    Write-Host ""
    
    if ($errorCount -gt 0) {
        Write-LogMessage "[!] Operation completed with $errorCount errors" "WARN"
    } else {
        Write-LogMessage "[+] TURBO operation completed successfully!" "SUCCESS"
    }
    
} catch {
    Write-LogMessage "[!] Fatal error: $($_.Exception.Message)" "ERROR"
    Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
    exit 1
} finally {
    if ($stopwatch) {
        $stopwatch.Stop()
    }
    Write-Progress -Activity "MD5 Generation" -Completed -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "[+] TURBO Script execution completed." -ForegroundColor Cyan
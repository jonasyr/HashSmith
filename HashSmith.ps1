<#
.SYNOPSIS
    Production-ready MD5 checksum generator with high-performance parallel processing.
    
.DESCRIPTION
    Generates MD5 checksums for all files in a directory tree with atomic logging,
    comprehensive error handling, and resume/fix capabilities.
    
.PARAMETER SourceDir
    Path to the source directory to process.
    
.PARAMETER LogFile
    Output path for the MD5 log file. Auto-generated if not specified.
    
.PARAMETER MD5Tool
    Path to external MD5 executable (optional - uses .NET by default).
    
.PARAMETER Resume
    Resume from existing log file, skipping already processed files.
    
.PARAMETER FixErrors
    Re-process only files that previously failed.
    
.PARAMETER ExcludePatterns
    Array of wildcard patterns to exclude files.
    
.PARAMETER HashAlgorithm
    Hash algorithm to use (MD5, SHA256, SHA512). Default: MD5.
    
.PARAMETER UseJsonLog
    Output additional JSON format log alongside plain text.
    
.PARAMETER MaxThreads
    Maximum parallel threads (default: CPU count * 2).
    
.PARAMETER RetryCount
    Number of retries for failed files (default: 3).
    
.EXAMPLE
    .\MD5-Checksum.ps1 -SourceDir "C:\Data" -Resume
    
.EXAMPLE
    .\MD5-Checksum.ps1 -SourceDir "C:\Data" -FixErrors -HashAlgorithm SHA256
    
.NOTES
    Version: 2.0.0
    Author: Production-Ready Implementation
    Requires: PowerShell 5.1 or higher (7+ recommended for parallel processing)
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateScript({
        if (-not (Test-Path $_ -PathType Container)) {
            throw "Directory '$_' does not exist"
        }
        $true
    })]
    [string]$SourceDir,
    
    [Parameter()]
    [ValidateScript({
        $parent = Split-Path $_ -Parent
        if ($parent -and -not (Test-Path $parent)) {
            throw "Log file parent directory does not exist"
        }
        $true
    })]
    [string]$LogFile,
    
    [Parameter()]
    [ValidateScript({
        if ($_ -and -not (Test-Path $_)) {
            throw "MD5 tool not found at '$_'"
        }
        $true
    })]
    [string]$MD5Tool,
    
    [Parameter()]
    [switch]$Resume,
    
    [Parameter()]
    [switch]$FixErrors,
    
    [Parameter()]
    [string[]]$ExcludePatterns = @(),
    
    [Parameter()]
    [ValidateSet('MD5', 'SHA256', 'SHA512')]
    [string]$HashAlgorithm = 'MD5',
    
    [Parameter()]
    [switch]$UseJsonLog,
    
    [Parameter()]
    [ValidateRange(1, 128)]
    [int]$MaxThreads = ([Environment]::ProcessorCount * 2),
    
    [Parameter()]
    [ValidateRange(0, 10)]
    [int]$RetryCount = 3
)

#region Configuration
$Script:Config = @{
    Version = '2.0.0'
    LogEncoding = 'UTF8'
    BufferSize = 1MB
    LockTimeout = 30
    ProgressUpdateInterval = 100
    MaxPathLength = 32767
    SupportLongPaths = $true
}
#endregion

#region Helper Functions

function Write-LogMessage {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp] [$Level] $Message"
    
    switch ($Level) {
        'ERROR'   { Write-Host $logEntry -ForegroundColor Red }
        'WARN'    { Write-Host $logEntry -ForegroundColor Yellow }
        'INFO'    { Write-Host $logEntry -ForegroundColor White }
        'SUCCESS' { Write-Host $logEntry -ForegroundColor Green }
    }
    
    # Also write to verbose stream for debugging
    Write-Verbose $logEntry
}

function Get-LongPath {
    param([string]$Path)
    
    if ($Script:Config.SupportLongPaths -and 
        $Path.Length -gt 260 -and 
        -not $Path.StartsWith('\\?\') -and
        -not $Path.StartsWith('\\')) {
        return "\\?\$Path"
    }
    return $Path
}

function Test-FileLocked {
    param([string]$Path)
    
    try {
        $file = [System.IO.File]::Open($Path, 'Open', 'Read', 'None')
        $file.Close()
        return $false
    }
    catch {
        return $true
    }
}

function Get-SafeFileHash {
    param(
        [string]$Path,
        [string]$Algorithm = 'MD5',
        [int]$RetryCount = 3
    )
    
    $attempt = 0
    $lastError = $null
    
    while ($attempt -lt $RetryCount) {
        try {
            $attempt++
            
            # Use long path if needed
            $safePath = Get-LongPath -Path $Path
            
            # Check if file exists and is accessible
            if (-not (Test-Path -LiteralPath $safePath)) {
                throw "File not found: $Path"
            }
            
            # Use streaming for large files
            $hashAlgo = [System.Security.Cryptography.HashAlgorithm]::Create($Algorithm)
            $stream = $null
            
            try {
                $stream = [System.IO.File]::OpenRead($safePath)
                $hashBytes = $hashAlgo.ComputeHash($stream)
                $hash = [System.BitConverter]::ToString($hashBytes) -replace '-', ''
                return $hash.ToLower()
            }
            finally {
                if ($stream) { $stream.Dispose() }
                if ($hashAlgo) { $hashAlgo.Dispose() }
            }
        }
        catch {
            $lastError = $_
            
            # Don't retry for certain errors
            if ($_.Exception -is [System.IO.FileNotFoundException] -or
                $_.Exception -is [System.IO.DirectoryNotFoundException]) {
                break
            }
            
            # Wait before retry with exponential backoff
            if ($attempt -lt $RetryCount) {
                Start-Sleep -Milliseconds (500 * $attempt)
            }
        }
    }
    
    throw $lastError
}

function Write-LogEntry {
    param(
        [string]$LogPath,
        [string]$FilePath,
        [string]$Hash,
        [long]$Size,
        [string]$Error,
        [switch]$Atomic
    )
    
    # Format: path = hash, size: X bytes
    # Error format: path = ERROR: message, size: X bytes
    if ($Error) {
        $logLine = "$FilePath = ERROR: $Error, size: $Size bytes"
    }
    else {
        $logLine = "$FilePath = $Hash, size: $Size bytes"
    }
    
    if ($Atomic) {
        # Use file locking for atomic writes
        $lockAcquired = $false
        $stream = $null
        $writer = $null
        
        try {
            $stream = [System.IO.File]::Open($LogPath, 'Append', 'Write', 'Read')
            $lockAcquired = $true
            
            $writer = [System.IO.StreamWriter]::new($stream, [System.Text.Encoding]::UTF8)
            $writer.WriteLine($logLine)
            $writer.Flush()
        }
        finally {
            if ($writer) { $writer.Dispose() }
            if ($stream) { $stream.Dispose() }
        }
    }
    else {
        # Fallback to Add-Content (less safe but more compatible)
        Add-Content -Path $LogPath -Value $logLine -Encoding UTF8
    }
}

function Get-ExistingLogEntries {
    param([string]$LogPath)
    
    $entries = @{
        Processed = @{}
        Failed = @{}
        TotalMD5 = $null
    }
    
    if (-not (Test-Path $LogPath)) {
        return $entries
    }
    
    try {
        $lines = Get-Content $LogPath -Encoding UTF8 -ErrorAction Stop
        
        foreach ($line in $lines) {
            if ($line -match '^(.+?)\s*=\s*([a-fA-F0-9]{32,128})\s*,\s*size:\s*(\d+)\s*bytes') {
                $entries.Processed[$matches[1]] = @{
                    Hash = $matches[2]
                    Size = [long]$matches[3]
                }
            }
            elseif ($line -match '^(.+?)\s*=\s*ERROR:\s*(.+?)\s*,\s*size:\s*(\d+)\s*bytes') {
                $entries.Failed[$matches[1]] = @{
                    Error = $matches[2]
                    Size = [long]$matches[3]
                }
            }
            elseif ($line -match '^TotalMD5\s*=\s*([a-fA-F0-9]{32,128})') {
                $entries.TotalMD5 = $matches[1]
            }
        }
    }
    catch {
        Write-LogMessage "Error reading log file: $_" -Level ERROR
    }
    
    return $entries
}

function Update-LogEntry {
    param(
        [string]$LogPath,
        [string]$FilePath,
        [string]$NewHash,
        [long]$Size,
        [string]$Error
    )
    
    # For production safety, use a temporary file approach
    $tempFile = "$LogPath.tmp"
    $backupFile = "$LogPath.bak"
    
    try {
        # Create backup
        Copy-Item -Path $LogPath -Destination $backupFile -Force
        
        # Read all lines
        $lines = Get-Content $LogPath -Encoding UTF8
        $updated = $false
        
        # Process lines
        $newLines = foreach ($line in $lines) {
            if ($line -match "^$([regex]::Escape($FilePath))\s*=") {
                $updated = $true
                if ($Error) {
                    "$FilePath = ERROR: $Error, size: $Size bytes"
                }
                else {
                    "$FilePath = $NewHash, size: $Size bytes"
                }
            }
            else {
                $line
            }
        }
        
        # Write to temp file
        $newLines | Set-Content -Path $tempFile -Encoding UTF8
        
        # Atomic replace
        Move-Item -Path $tempFile -Destination $LogPath -Force
        
        # Remove backup on success
        Remove-Item -Path $backupFile -Force -ErrorAction SilentlyContinue
        
        return $updated
    }
    catch {
        # Restore from backup on error
        if (Test-Path $backupFile) {
            Move-Item -Path $backupFile -Destination $LogPath -Force
        }
        throw
    }
    finally {
        # Cleanup
        Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
    }
}

function Write-JsonLog {
    param(
        [string]$LogPath,
        [hashtable]$Entries,
        [hashtable]$Statistics
    )
    
    $jsonPath = [System.IO.Path]::ChangeExtension($LogPath, '.json')
    
    $jsonData = @{
        Version = $Script:Config.Version
        Timestamp = (Get-Date -Format 'o')
        Algorithm = $HashAlgorithm
        Statistics = $Statistics
        Files = @()
    }
    
    foreach ($file in $Entries.Processed.Keys) {
        $jsonData.Files += @{
            Path = $file
            Hash = $Entries.Processed[$file].Hash
            Size = $Entries.Processed[$file].Size
            Status = 'Success'
        }
    }
    
    foreach ($file in $Entries.Failed.Keys) {
        $jsonData.Files += @{
            Path = $file
            Error = $Entries.Failed[$file].Error
            Size = $Entries.Failed[$file].Size
            Status = 'Failed'
        }
    }
    
    $jsonData | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath -Encoding UTF8
}

#endregion

#region Main Processing

# Initialize
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$SourceDir = Resolve-Path $SourceDir
$useParallel = $PSVersionTable.PSVersion.Major -ge 7

# Auto-generate log file if not specified
if (-not $LogFile) {
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $sourceName = Split-Path $SourceDir -Leaf
    $LogFile = Join-Path $SourceDir "${sourceName}_${HashAlgorithm}_${timestamp}.log"
}

$LogFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LogFile)

# Display configuration
Write-Host ""
Write-Host "+============================================================+" -ForegroundColor Cyan
Write-Host "|          Production-Ready Checksum Generator v$($Script:Config.Version)        |" -ForegroundColor Cyan
Write-Host "+============================================================+" -ForegroundColor Cyan
Write-Host ""
Write-Host "[*] Source Directory: $SourceDir" -ForegroundColor Green
Write-Host "[*] Log File: $LogFile" -ForegroundColor Green
Write-Host "[*] Algorithm: $HashAlgorithm" -ForegroundColor Green
Write-Host "[*] Max Threads: $MaxThreads" -ForegroundColor Green
Write-Host "[*] Mode: $(if($useParallel){'Parallel'}else{'Sequential'})" -ForegroundColor Green
Write-Host ""

# Validate write permissions
try {
    $testFile = Join-Path (Split-Path $LogFile) "test_write_$([Guid]::NewGuid()).tmp"
    [System.IO.File]::WriteAllText($testFile, "test")
    Remove-Item $testFile -Force
}
catch {
    Write-LogMessage "Cannot write to log directory: $_" -Level ERROR
    exit 1
}

# Load existing entries if Resume or FixErrors
$existingEntries = @{ Processed = @{}; Failed = @{} }
if ($Resume -or $FixErrors) {
    Write-LogMessage "Loading existing log entries..." -Level INFO
    $existingEntries = Get-ExistingLogEntries -LogPath $LogFile
    
    if ($Resume) {
        Write-LogMessage "Resume mode: Found $($existingEntries.Processed.Count) processed, $($existingEntries.Failed.Count) failed" -Level INFO
    }
    if ($FixErrors) {
        Write-LogMessage "Fix mode: Will retry $($existingEntries.Failed.Count) failed files" -Level INFO
    }
}

# Collect files
Write-LogMessage "Scanning directory for files..." -Level INFO
$allFiles = Get-ChildItem -Path $SourceDir -Recurse -File -ErrorAction SilentlyContinue

# Apply exclusions
if ($ExcludePatterns.Count -gt 0) {
    Write-LogMessage "Applying exclusion patterns: $($ExcludePatterns -join ', ')" -Level INFO
    foreach ($pattern in $ExcludePatterns) {
        $allFiles = $allFiles | Where-Object { $_.Name -notlike $pattern }
    }
}

# Determine files to process
$filesToProcess = @()

if ($FixErrors) {
    # Only process previously failed files
    foreach ($failedPath in $existingEntries.Failed.Keys) {
        $file = $allFiles | Where-Object { $_.FullName -eq $failedPath }
        if ($file) {
            $filesToProcess += $file
        }
    }
}
else {
    # Process all files not already successfully processed
    $filesToProcess = $allFiles | Where-Object {
        -not $existingEntries.Processed.ContainsKey($_.FullName)
    }
}

$totalFiles = $filesToProcess.Count
$totalSize = ($filesToProcess | Measure-Object -Property Length -Sum).Sum

if ($totalFiles -eq 0) {
    Write-LogMessage "No files to process" -Level WARN
    exit 0
}

Write-LogMessage "Found $totalFiles files to process ($('{0:N2} GB' -f ($totalSize / 1GB)))" -Level INFO

# WhatIf mode
if ($WhatIf) {
    Write-Host ""
    Write-Host "What-If Mode: Would process $totalFiles files" -ForegroundColor Yellow
    Write-Host "Total size: $('{0:N2} GB' -f ($totalSize / 1GB))" -ForegroundColor Yellow
    return
}

# Create log file if needed
if (-not (Test-Path $LogFile)) {
    New-Item -Path $LogFile -ItemType File -Force | Out-Null
    
    # Write header
    $header = @(
        "# Checksum Log Generated by Production-Ready Script v$($Script:Config.Version)",
        "# Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "# Algorithm: $HashAlgorithm",
        "# Source: $SourceDir",
        ""
    )
    $header | Set-Content -Path $LogFile -Encoding UTF8
}

# Process files
$processedCount = 0
$errorCount = 0
$processedSize = 0
$results = @()

Write-LogMessage "Starting file processing..." -Level INFO

# Process function for parallel execution
$processFileScript = {
    param($File, $Algorithm, $RetryCount)
    
    # Re-create functions in parallel runspace
    function Get-LongPath {
        param([string]$Path)
        if ($Path.Length -gt 260 -and -not $Path.StartsWith('\\?\') -and -not $Path.StartsWith('\\')) {
            return "\\?\$Path"
        }
        return $Path
    }
    
    function Get-SafeFileHash {
        param([string]$Path, [string]$Algorithm, [int]$RetryCount)
        
        $attempt = 0
        $lastError = $null
        
        while ($attempt -lt $RetryCount) {
            try {
                $attempt++
                $safePath = Get-LongPath -Path $Path
                
                $hashAlgo = [System.Security.Cryptography.HashAlgorithm]::Create($Algorithm)
                $stream = $null
                
                try {
                    $stream = [System.IO.File]::OpenRead($safePath)
                    $hashBytes = $hashAlgo.ComputeHash($stream)
                    $hash = [System.BitConverter]::ToString($hashBytes) -replace '-', ''
                    return $hash.ToLower()
                }
                finally {
                    if ($stream) { $stream.Dispose() }
                    if ($hashAlgo) { $hashAlgo.Dispose() }
                }
            }
            catch {
                $lastError = $_
                if ($attempt -lt $RetryCount) {
                    Start-Sleep -Milliseconds (500 * $attempt)
                }
            }
        }
        throw $lastError
    }
    
    $result = @{
        Path = $File.FullName
        Name = $File.Name
        Size = $File.Length
        Success = $false
        Hash = $null
        Error = $null
    }
    
    try {
        $result.Hash = Get-SafeFileHash -Path $File.FullName -Algorithm $Algorithm -RetryCount $RetryCount
        $result.Success = $true
    }
    catch {
        $result.Error = $_.Exception.Message
    }
    
    return $result
}

# Process in batches
$batchSize = [Math]::Min($MaxThreads, $totalFiles)
$batches = [Math]::Ceiling($totalFiles / $batchSize)

for ($i = 0; $i -lt $totalFiles; $i += $batchSize) {
    $batch = $filesToProcess[$i..[Math]::Min($i + $batchSize - 1, $totalFiles - 1)]
    $batchNum = [Math]::Floor($i / $batchSize) + 1
    
    Write-LogMessage "Processing batch $batchNum/$batches..." -Level INFO
    
    # Process batch
    if ($useParallel) {
        $batchResults = $batch | ForEach-Object -Parallel {
            # Get algorithm and retry count from outside scope
            $Algorithm = $using:HashAlgorithm
            $RetryCount = $using:RetryCount
            
            # Re-create functions in parallel runspace
            function Get-LongPath {
                param([string]$Path)
                if ($Path.Length -gt 260 -and -not $Path.StartsWith('\\?\') -and -not $Path.StartsWith('\\')) {
                    return "\\?\$Path"
                }
                return $Path
            }
            
            function Get-SafeFileHash {
                param([string]$Path, [string]$Algorithm, [int]$RetryCount)
                
                $attempt = 0
                $lastError = $null
                
                while ($attempt -lt $RetryCount) {
                    try {
                        $attempt++
                        $safePath = Get-LongPath -Path $Path
                        
                        $hashAlgo = [System.Security.Cryptography.HashAlgorithm]::Create($Algorithm)
                        $stream = $null
                        
                        try {
                            $stream = [System.IO.File]::OpenRead($safePath)
                            $hashBytes = $hashAlgo.ComputeHash($stream)
                            $hash = [System.BitConverter]::ToString($hashBytes) -replace '-', ''
                            return $hash.ToLower()
                        }
                        finally {
                            if ($stream) { $stream.Dispose() }
                            if ($hashAlgo) { $hashAlgo.Dispose() }
                        }
                    }
                    catch {
                        $lastError = $_
                        if ($attempt -lt $RetryCount) {
                            Start-Sleep -Milliseconds (500 * $attempt)
                        }
                    }
                }
                throw $lastError
            }
            
            $result = @{
                Path = $_.FullName
                Name = $_.Name
                Size = $_.Length
                Success = $false
                Hash = $null
                Error = $null
            }
            
            try {
                $result.Hash = Get-SafeFileHash -Path $_.FullName -Algorithm $Algorithm -RetryCount $RetryCount
                $result.Success = $true
            }
            catch {
                $result.Error = $_.Exception.Message
            }
            
            return $result
        } -ThrottleLimit $MaxThreads
    }
    else {
        $batchResults = $batch | ForEach-Object {
            & $processFileScript -File $_ -Algorithm $HashAlgorithm -RetryCount $RetryCount
        }
    }
    
    # Write results atomically
    foreach ($result in $batchResults) {
        $processedCount++
        
        if ($FixErrors) {
            # Update existing entry
            $updated = Update-LogEntry -LogPath $LogFile -FilePath $result.Path -NewHash $result.Hash -Size $result.Size -Error $result.Error
            
            if ($result.Success) {
                $processedSize += $result.Size
                Write-Verbose "Fixed: $($result.Name)"
            }
            else {
                $errorCount++
                Write-LogMessage "Failed to fix: $($result.Name) - $($result.Error)" -Level WARN
            }
        }
        else {
            # Write new entry
            Write-LogEntry -LogPath $LogFile -FilePath $result.Path -Hash $result.Hash -Size $result.Size -Error $result.Error -Atomic
            
            if ($result.Success) {
                $processedSize += $result.Size
                Write-Verbose "Processed: $($result.Name)"
            }
            else {
                $errorCount++
                Write-LogMessage "Error: $($result.Name) - $($result.Error)" -Level WARN
            }
        }
        
        # Update progress
        if ($processedCount % $Script:Config.ProgressUpdateInterval -eq 0) {
            $percent = [Math]::Round(($processedCount / $totalFiles) * 100)
            Write-Progress -Activity "Processing files" -Status "$processedCount/$totalFiles" -PercentComplete $percent
        }
    }
}

Write-Progress -Activity "Processing files" -Completed

# Generate total hash
if (-not $FixErrors) {
    Write-LogMessage "Generating total directory hash..." -Level INFO
    
    try {
        # Compute total hash from all individual hashes
        $allHashes = Get-Content $LogFile -Encoding UTF8 | 
            Where-Object { $_ -match '=\s*([a-fA-F0-9]{32,128})\s*,' } | 
            ForEach-Object { $matches[1] }
        
        $combinedHashes = $allHashes -join ''
        $totalHashBytes = [System.Text.Encoding]::UTF8.GetBytes($combinedHashes)
        $totalHashAlgo = [System.Security.Cryptography.HashAlgorithm]::Create($HashAlgorithm)
        $totalHash = [System.BitConverter]::ToString($totalHashAlgo.ComputeHash($totalHashBytes)) -replace '-', ''
        
        Add-Content -Path $LogFile -Value ""
        Add-Content -Path $LogFile -Value "Total$HashAlgorithm = $($totalHash.ToLower())"
        
        $summaryLine = "$($processedCount - $errorCount) files checked ($processedSize bytes, $('{0:N2} GB' -f ($processedSize / 1GB)), $($stopwatch.Elapsed.TotalSeconds.ToString('F1')) sec)."
        Add-Content -Path $LogFile -Value $summaryLine
        
        Write-LogMessage "Total hash: $($totalHash.ToLower())" -Level SUCCESS
    }
    catch {
        Write-LogMessage "Failed to generate total hash: $_" -Level ERROR
    }
}

$stopwatch.Stop()

# Generate JSON log if requested
if ($UseJsonLog) {
    Write-LogMessage "Generating JSON log..." -Level INFO
    
    $statistics = @{
        TotalFiles = $processedCount
        SuccessCount = $processedCount - $errorCount
        ErrorCount = $errorCount
        TotalSize = $processedSize
        Duration = $stopwatch.Elapsed.TotalSeconds
        Algorithm = $HashAlgorithm
    }
    
    $allEntries = Get-ExistingLogEntries -LogPath $LogFile
    Write-JsonLog -LogPath $LogFile -Entries $allEntries -Statistics $statistics
}

# Final summary
Write-Host ""
Write-Host "+============================================================+" -ForegroundColor Green
Write-Host "|                  OPERATION COMPLETE                        |" -ForegroundColor Green
Write-Host "+============================================================+" -ForegroundColor Green
Write-Host ""
Write-Host "[*] Files processed: $($processedCount - $errorCount)" -ForegroundColor White
Write-Host "[*] Errors: $errorCount" -ForegroundColor $(if($errorCount -gt 0){'Red'}else{'Green'})
Write-Host "[*] Total size: $('{0:N2} GB' -f ($processedSize / 1GB))" -ForegroundColor Cyan
Write-Host "[*] Duration: $($stopwatch.Elapsed.ToString('hh\:mm\:ss'))" -ForegroundColor Cyan
Write-Host "[*] Log file: $LogFile" -ForegroundColor Yellow
if ($UseJsonLog) {
    Write-Host "[*] JSON log: $([System.IO.Path]::ChangeExtension($LogFile, '.json'))" -ForegroundColor Yellow
}
Write-Host ""

if ($errorCount -gt 0) {
    Write-LogMessage "Operation completed with $errorCount errors. Use -FixErrors to retry." -Level WARN
}
else {
    Write-LogMessage "Operation completed successfully!" -Level SUCCESS
}

#endregion
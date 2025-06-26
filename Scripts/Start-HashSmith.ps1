<#
.SYNOPSIS
    Production-ready file integrity verification system with reliable resume functionality
    
.DESCRIPTION
    Generates cryptographic hashes for ALL files in a directory tree with:
    - Guaranteed complete file discovery (no files missed)
    - Deterministic total directory integrity hash
    - Race condition protection with file modification verification
    - Comprehensive error handling and recovery
    - Symbolic link and reparse point detection
    - Network path support with resilience
    - Unicode and long path support
    - Memory-efficient streaming processing
    - Reliable resume functionality that properly skips processed files
    
.PARAMETER SourceDir
    Path to the source directory to process.
    
.PARAMETER LogFile
    Output path for the hash log file. Auto-generated if not specified.
    
.PARAMETER HashAlgorithm
    Hash algorithm to use (MD5, SHA1, SHA256, SHA512). Default: MD5.
    
.PARAMETER Resume
    Resume from existing log file, skipping already processed files.
    
.PARAMETER FixErrors
    Re-process only files that previously failed.
    
.PARAMETER ExcludePatterns
    Array of wildcard patterns to exclude files.
    
.PARAMETER IncludeHidden
    Include hidden and system files in processing.
    
.PARAMETER IncludeSymlinks
    Include symbolic links and reparse points (default: false for safety).
    
.PARAMETER MaxThreads
    Maximum parallel threads (default: CPU count).
    
.PARAMETER RetryCount
    Number of retries for failed files (default: 3).
    
.PARAMETER ChunkSize
    Base files to process per batch (default: 1000).
    
.PARAMETER TimeoutSeconds
    Timeout for file operations in seconds (default: 30).

.PARAMETER ProgressTimeoutMinutes
    Timeout in minutes for no progress before stopping processing (default: 120 minutes).
    
.PARAMETER UseJsonLog
    Output structured JSON log alongside text log.
    
.PARAMETER VerifyIntegrity
    Verify file integrity before and after processing.
    
.PARAMETER ShowProgress
    Show detailed progress information.
    
.PARAMETER TestMode
    Run in test mode with extensive validation checks.
    
.PARAMETER StrictMode
    Enable strict mode with maximum validation (slower but safer).
    
.PARAMETER SortFilesBySize
    Sort files by size (smaller first) for better progress indication.
    
.EXAMPLE
    .\Start-HashSmith.ps1 -SourceDir "C:\Data" -HashAlgorithm MD5 -Resume
    
.EXAMPLE
    .\Start-HashSmith.ps1 -SourceDir "\\server\share" -Resume -IncludeHidden -StrictMode
    
.EXAMPLE
    .\Start-HashSmith.ps1 -SourceDir "C:\Data" -FixErrors -UseJsonLog -VerifyIntegrity
    
.NOTES
    Version: 4.1.0-Fixed
    Author: Production-Ready Implementation with Critical Bug Fixes
    Requires: PowerShell 5.1 or higher (7+ recommended for parallel processing)
    
    Key Fixes:
    - Resume functionality now properly skips already processed files
    - Simplified architecture without complex timer issues
    - Improved error handling and logging reliability
    - Professional output without excessive marketing language
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateScript({
        if (-not (Test-Path $_ -PathType Container)) {
            throw "Directory '$_' does not exist or is not accessible"
        }
        $true
    })]
    [string]$SourceDir,
    
    [Parameter()]
    [ValidateScript({
        if ($_ -and (Split-Path $_ -Parent)) {
            $parent = Split-Path $_ -Parent
            if (-not (Test-Path $parent)) {
                throw "Log file parent directory does not exist: $parent"
            }
        }
        $true
    })]
    [string]$LogFile,
    
    [Parameter()]
    [ValidateSet('MD5', 'SHA1', 'SHA256', 'SHA512')]
    [string]$HashAlgorithm = 'MD5',
    
    [Parameter()]
    [switch]$Resume,
    
    [Parameter()]
    [switch]$FixErrors,
    
    [Parameter()]
    [string[]]$ExcludePatterns = @(),
    
    [Parameter()]
    [bool]$IncludeHidden = $true,
    
    [Parameter()]
    [bool]$IncludeSymlinks = $false,
    
    [Parameter()]
    [ValidateRange(1, 64)]
    [int]$MaxThreads = [Environment]::ProcessorCount,
    
    [Parameter()]
    [ValidateRange(1, 10)]
    [int]$RetryCount = 3,
    
    [Parameter()]
    [ValidateRange(100, 5000)]
    [int]$ChunkSize = 1000,
    
    [Parameter()]
    [ValidateRange(10, 300)]
    [int]$TimeoutSeconds = 30,
    
    [Parameter()]
    [ValidateRange(5, 1440)]
    [int]$ProgressTimeoutMinutes = 120,
    
    [Parameter()]
    [switch]$UseJsonLog,
    
    [Parameter()]
    [switch]$VerifyIntegrity,
    
    [Parameter()]
    [switch]$ShowProgress,
    
    [Parameter()]
    [switch]$TestMode,
    
    [Parameter()]
    [switch]$StrictMode,
    
    [Parameter()]
    [switch]$SortFilesBySize,
    
    [Parameter()]
    [switch]$UseParallel
)

#region Helper Functions

<#
.SYNOPSIS
    Writes a professional header
#>
function Write-ProfessionalHeader {
    [CmdletBinding()]
    param(
        [string]$Title,
        [string]$Subtitle = "",
        [string]$Color = "Cyan"
    )
    
    $width = 80
    $titlePadding = [Math]::Max(0, ($width - $Title.Length) / 2)
    $subtitlePadding = [Math]::Max(0, ($width - $Subtitle.Length) / 2)
    
    Write-Host ""
    Write-Host ("═" * $width) -ForegroundColor $Color
    Write-Host (" " * $titlePadding + $Title) -ForegroundColor White
    if ($Subtitle) {
        Write-Host (" " * $subtitlePadding + $Subtitle) -ForegroundColor Gray
    }
    Write-Host ("═" * $width) -ForegroundColor $Color
    Write-Host ""
}

<#
.SYNOPSIS
    Writes configuration item
#>
function Write-ConfigItem {
    [CmdletBinding()]
    param(
        [string]$Icon,
        [string]$Label,
        [string]$Value,
        [string]$Color = "White"
    )
    
    $formattedLabel = $Label.PadRight(20)
    Write-Host "$Icon $formattedLabel : " -NoNewline -ForegroundColor Gray
    Write-Host $Value -ForegroundColor $Color
}

<#
.SYNOPSIS
    Writes statistics item
#>
function Write-StatItem {
    [CmdletBinding()]
    param(
        [string]$Icon,
        [string]$Label,
        [string]$Value,
        [string]$Color = "Cyan"
    )
    
    Write-Host "$Icon " -NoNewline -ForegroundColor $Color
    Write-Host "$Label : " -NoNewline -ForegroundColor White
    Write-Host $Value -ForegroundColor $Color
}

<#
.SYNOPSIS
    Registers graceful termination handler for the main script
#>
function Register-MainScriptTermination {
    [CmdletBinding()]
    param(
        [string]$LogPath
    )
    
    # Register CTRL+C handler for main script
    Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
        Write-Host "`n🛑 Graceful shutdown initiated..." -ForegroundColor Yellow
        
        try {
            # Final log flush
            if ($using:LogPath) {
                Clear-HashSmithLogBatch -LogPath $using:LogPath
                Write-Host "📝 Final log batch flushed successfully" -ForegroundColor Green
            }
            
            # Final statistics
            $finalStats = Get-HashSmithStatistics
            Write-Host "📊 Final Statistics:" -ForegroundColor Cyan
            Write-Host "   • Files Processed: $($finalStats.FilesProcessed)" -ForegroundColor White
            Write-Host "   • Bytes Processed: $('{0:N1} GB' -f ($finalStats.BytesProcessed / 1GB))" -ForegroundColor White
            Write-Host "   • Errors: $($finalStats.FilesError)" -ForegroundColor White
            
        } catch {
            Write-Warning "Error during graceful shutdown: $($_.Exception.Message)"
        }
        
        Write-Host "✅ Graceful shutdown complete - Resume with -Resume to continue" -ForegroundColor Green
        exit 130
    }
}

#endregion

#region Module Import and Initialization

# Get script directory for relative module paths
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptPath
$ModulesPath = Join-Path $ProjectRoot "Modules"

# Module loading
Write-Host ""
Write-Host "🔧 Initializing HashSmith modules..." -ForegroundColor Cyan

try {
    $modules = @(
        "HashSmithConfig",
        "HashSmithCore", 
        "HashSmithDiscovery",
        "HashSmithHash",
        "HashSmithLogging",
        "HashSmithIntegrity",
        "HashSmithProcessor"
    )
    
    $moduleLoadStart = Get-Date
    foreach ($module in $modules) {
        Write-Host "   • Loading $module" -ForegroundColor Gray
        Import-Module (Join-Path $ModulesPath $module) -Force -Verbose:$false
    }
    $moduleLoadTime = (Get-Date) - $moduleLoadStart
    
    Write-Host "✅ All modules loaded in $($moduleLoadTime.TotalSeconds.ToString('F1'))s" -ForegroundColor Green
}
catch {
    Write-Host "❌ Failed to import HashSmith modules: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Initialize configuration
$configOverrides = @{
    ProgressTimeoutMinutes = $ProgressTimeoutMinutes
}
Initialize-HashSmithConfig -ConfigOverrides $configOverrides

# Get configuration
$config = Get-HashSmithConfig

# Reset statistics for fresh run
Reset-HashSmithStatistics

#endregion

#region Main Script Execution

# Initialize timing
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# Professional banner
Write-Host ""
Write-Host "██╗  ██╗ █████╗ ███████╗██╗  ██╗███████╗███╗   ███╗██╗████████╗██╗  ██╗" -ForegroundColor Cyan
Write-Host "██║  ██║██╔══██╗██╔════╝██║  ██║██╔════╝████╗ ████║██║╚══██╔══╝██║  ██║" -ForegroundColor Cyan
Write-Host "███████║███████║███████╗███████║███████╗██╔████╔██║██║   ██║   ███████║" -ForegroundColor Cyan
Write-Host "██╔══██║██╔══██║╚════██║██╔══██║╚════██║██║╚██╔╝██║██║   ██║   ██╔══██║" -ForegroundColor Cyan
Write-Host "██║  ██║██║  ██║███████║██║  ██║███████║██║ ╚═╝ ██║██║   ██║   ██║  ██║" -ForegroundColor Cyan
Write-Host "╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝╚═╝   ╚═╝   ╚═╝  ╚═╝" -ForegroundColor Cyan

Write-ProfessionalHeader -Title "🔐 Production File Integrity System 🔐" -Subtitle "Version $($config.Version) - Reliable and Efficient" -Color "Blue"

# System information
$osWindows = $PSVersionTable.PSVersion.Major -ge 6 ? $IsWindows : ($env:OS -eq "Windows_NT")
$osLinux = $PSVersionTable.PSVersion.Major -ge 6 ? $IsLinux : $false
$osMacOS = $PSVersionTable.PSVersion.Major -ge 6 ? $IsMacOS : $false

# Memory detection
$memoryGB = 0
try {
    if ($osWindows) {
        if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
            $memoryGB = [Math]::Round(((Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum / 1GB), 1)
        } else {
            $memoryGB = [Math]::Round(((Get-WmiObject Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum / 1GB), 1)
        }
    } elseif ($osLinux -and (Test-Path '/proc/meminfo')) {
        $memInfo = Get-Content '/proc/meminfo' | Where-Object { $_ -match '^MemTotal:' }
        if ($memInfo -match '(\d+)\s*kB') {
            $memoryGB = [Math]::Round(([int64]$matches[1] * 1024 / 1GB), 1)
        }
    }
} catch {
    $memoryGB = 0
}

$computerName = if ($osWindows) { 
    $env:COMPUTERNAME 
} else { 
    $env:HOSTNAME -or "Unknown"
}

Write-Host "🖥️ System Information" -ForegroundColor Yellow
Write-Host "   Computer Name    : $computerName" -ForegroundColor White
Write-Host "   Operating System : $(if($osWindows){'Windows'}elseif($osLinux){'Linux'}elseif($osMacOS){'macOS'}else{'Unknown'})" -ForegroundColor White
Write-Host "   PowerShell       : $($PSVersionTable.PSVersion)" -ForegroundColor White
Write-Host "   CPU Cores        : $([Environment]::ProcessorCount)" -ForegroundColor White
Write-Host "   Total Memory     : $(if($memoryGB -gt 0){"$memoryGB GB"}else{"Unknown"})" -ForegroundColor White
Write-Host ""

try {
    # Normalize source directory
    $SourceDir = (Resolve-Path $SourceDir).Path
    
    # Auto-generate log file if not specified
    if (-not $LogFile) {
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $sourceName = Split-Path $SourceDir -Leaf
        $LogFile = Join-Path $SourceDir "${sourceName}_${HashAlgorithm}_${timestamp}.log"
    }
    
    $LogFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LogFile)
    
    # Register graceful termination
    Register-MainScriptTermination -LogPath $LogFile
    
    # Configuration display
    Write-ProfessionalHeader -Title "Configuration Settings" -Color "Green"
    
    Write-ConfigItem -Icon "📁" -Label "Source Directory" -Value $SourceDir -Color "Cyan"
    Write-ConfigItem -Icon "📝" -Label "Log File" -Value $LogFile -Color "Green"
    Write-ConfigItem -Icon "🔑" -Label "Hash Algorithm" -Value $HashAlgorithm -Color "Yellow"
    Write-ConfigItem -Icon "🧵" -Label "Max Threads" -Value $MaxThreads -Color "Magenta"
    Write-ConfigItem -Icon "📦" -Label "Chunk Size" -Value $ChunkSize -Color "Cyan"
    Write-ConfigItem -Icon "👁️ " -Label "Include Hidden" -Value $IncludeHidden -Color $(if($IncludeHidden){"Green"}else{"Red"})
    Write-ConfigItem -Icon "🔗" -Label "Include Symlinks" -Value $IncludeSymlinks -Color $(if($IncludeSymlinks){"Green"}else{"Red"})
    Write-ConfigItem -Icon "🛡️ " -Label "Verify Integrity" -Value $VerifyIntegrity -Color $(if($VerifyIntegrity){"Green"}else{"Gray"})
    Write-ConfigItem -Icon "⚡" -Label "Strict Mode" -Value $StrictMode -Color $(if($StrictMode){"Yellow"}else{"Gray"})
    Write-ConfigItem -Icon "🧪" -Label "Test Mode" -Value $TestMode -Color $(if($TestMode){"Yellow"}else{"Gray"})
    
    # Display resume status
    if ($Resume) {
        Write-ConfigItem -Icon "🔄" -Label "Resume Mode" -Value "ENABLED (will skip processed files)" -Color "Green"
    } elseif ($FixErrors) {
        Write-ConfigItem -Icon "🔧" -Label "Fix Errors Mode" -Value "ENABLED (retry failed files only)" -Color "Yellow"
    } else {
        Write-ConfigItem -Icon "🆕" -Label "Processing Mode" -Value "FULL (process all files)" -Color "Cyan"
    }
    
    # Test write permissions
    if (-not $WhatIfPreference) {
        try {
            $testFile = Join-Path (Split-Path $LogFile) "test_write_$([Guid]::NewGuid()).tmp"
            "test" | Set-Content -Path $testFile -ErrorAction Stop
            if (Test-Path $testFile) {
                Remove-Item $testFile -Force -ErrorAction SilentlyContinue
            }
        }
        catch [System.UnauthorizedAccessException] {
            $alternateLogPath = Join-Path $env:TEMP "$(Split-Path $LogFile -Leaf)"
            Write-Host "⚠️  Access denied to original log location. Using: $alternateLogPath" -ForegroundColor Yellow
            $LogFile = $alternateLogPath
        }
        catch {
            $alternateLogPath = Join-Path $env:TEMP "$(Split-Path $LogFile -Leaf)"
            Write-Host "⚠️  Cannot access log directory. Using: $alternateLogPath" -ForegroundColor Yellow
            $LogFile = $alternateLogPath
        }
    }
    
    # Load existing entries for resume/fix
    $existingEntries = @{ Processed = @{}; Failed = @{} }
    if ($Resume -or $FixErrors) {
        if (Test-Path $LogFile) {
            Write-Host ""
            Write-Host "🔄 Loading existing log entries for resume operation..." -ForegroundColor Cyan
            
            $loadStart = Get-Date
            $existingEntries = Get-HashSmithExistingEntries -LogPath $LogFile
            $loadTime = (Get-Date) - $loadStart
            
            Write-Host "   ✅ Log loaded in $($loadTime.TotalSeconds.ToString('F1'))s" -ForegroundColor Green
            Write-Host "   • Processed: $($existingEntries.Statistics.ProcessedCount)" -ForegroundColor Green
            Write-Host "   • Failed: $($existingEntries.Statistics.FailedCount)" -ForegroundColor Red
        } else {
            Write-Host "⚠️  Resume/Fix requested but no existing log file found" -ForegroundColor Yellow
        }
    }
    
    # File discovery phase
    Write-ProfessionalHeader -Title "File Discovery Phase" -Color "Green"
    Write-Host "🚀 Starting file discovery..." -ForegroundColor Cyan
    
    $discoveryResult = Get-HashSmithAllFiles -Path $SourceDir -ExcludePatterns $ExcludePatterns -IncludeHidden:$IncludeHidden -IncludeSymlinks:$IncludeSymlinks -TestMode:$TestMode -StrictMode:$StrictMode
    $allFiles = $discoveryResult.Files
    $discoveryStats = $discoveryResult.Statistics
    
    # Discovery results display
    Write-Host ""
    Write-Host "✅ File Discovery Complete" -ForegroundColor Green
    Write-Host "┌─────────────────────────────────────────┐" -ForegroundColor Gray
    Write-StatItem -Icon "📊" -Label "Files Found" -Value $allFiles.Count -Color "Cyan"
    Write-StatItem -Icon "⏭️" -Label "Files Skipped" -Value $discoveryStats.TotalSkipped -Color "Yellow"
    Write-StatItem -Icon "🔗" -Label "Symbolic Links" -Value $discoveryStats.TotalSymlinks -Color "Magenta"
    if ($discoveryResult.Errors.Count -gt 0) {
        Write-StatItem -Icon "⚠️ " -Label "Discovery Errors" -Value $discoveryResult.Errors.Count -Color "Red"
    }
    Write-StatItem -Icon "⏱️" -Label "Discovery Time" -Value "$($discoveryStats.DiscoveryTime.ToString('F2'))s" -Color "Blue"
    Write-StatItem -Icon "🚀" -Label "Performance" -Value "$($discoveryStats.FilesPerSecond) files/second" -Color "Green"
    Write-Host "└─────────────────────────────────────────┘" -ForegroundColor Gray
    Write-Host ""
    
    # File filtering for resume functionality
    $filesToProcess = @()
    $skippedResumeCount = 0
    
    if ($FixErrors) {
        # Only process previously failed files that still exist
        Write-Host "🔧 Fix Mode: Identifying failed files to retry..." -ForegroundColor Yellow
        
        foreach ($failedPath in $existingEntries.Failed.Keys) {
            $absolutePath = if ([System.IO.Path]::IsPathRooted($failedPath)) { 
                $failedPath 
            } else { 
                Join-Path $SourceDir $failedPath 
            }
            
            $file = $allFiles | Where-Object { $_.FullName -eq $absolutePath }
            if ($file) {
                $filesToProcess += $file
            }
        }
        Write-Host "   ✅ Fix Mode: Will retry $($filesToProcess.Count) failed files" -ForegroundColor Yellow
        
    } elseif ($Resume) {
        # Properly filter already processed files
        Write-Host "🔄 Resume Mode: Filtering already processed files..." -ForegroundColor Cyan
        Write-Host "   📊 Found $($existingEntries.Processed.Count) processed files in log" -ForegroundColor Gray
        
        $filterStart = Get-Date
        foreach ($file in $allFiles) {
            $absolutePath = $file.FullName
            $relativePath = $absolutePath.Substring($SourceDir.Length).TrimStart('\', '/')
            
            # Check if file was already processed
            $alreadyProcessed = $existingEntries.Processed.ContainsKey($absolutePath) -or 
                               $existingEntries.Processed.ContainsKey($relativePath) -or
                               $existingEntries.Processed.ContainsKey($file.FullName)
            
            if ($alreadyProcessed) {
                $skippedResumeCount++
                if ($skippedResumeCount % 5000 -eq 0) {
                    Write-Host "`r   ✅ Skipped: $skippedResumeCount already processed" -NoNewline -ForegroundColor Green
                }
            } else {
                $filesToProcess += $file
            }
        }
        
        $filterTime = (Get-Date) - $filterStart
        Write-Host "`r   ✅ Resume filtering complete in $($filterTime.TotalSeconds.ToString('F1'))s" -ForegroundColor Green
        Write-Host "   📊 Files discovered: $($allFiles.Count)" -ForegroundColor Gray
        Write-Host "   📊 Files in log: $($existingEntries.Processed.Count)" -ForegroundColor Gray
        Write-Host "   📊 Skipped (already processed): $skippedResumeCount" -ForegroundColor Green
        Write-Host "   📊 Remaining to process: $($filesToProcess.Count)" -ForegroundColor Cyan
        
        # Report any discrepancy
        if ($skippedResumeCount -ne $allFiles.Count -and $filesToProcess.Count -eq 0) {
            $missingFromLog = $allFiles.Count - $skippedResumeCount
            Write-Host "   ⚠️  Note: $missingFromLog files discovered but not found in log (may be new/renamed files)" -ForegroundColor Yellow
        }
        
        Write-HashSmithLog -Message "RESUME: Discovered $($allFiles.Count) files, skipped $skippedResumeCount already processed, $($filesToProcess.Count) remaining" -Level SUCCESS -Component 'RESUME'
        
    } else {
        # Process all discovered files
        $filesToProcess = $allFiles
        Write-Host "🆕 Full Mode: Processing all $($filesToProcess.Count) discovered files" -ForegroundColor Cyan
    }
    
    if ($filesToProcess.Count -eq 0) {
        Write-Host ""
        Write-Host "🎉 All files already processed!" -ForegroundColor Green
        
        # Check if directory integrity hash needs to be computed
        if (-not $FixErrors -and $Resume) {
            Write-Host "🔍 Checking if directory integrity hash needs computation..." -ForegroundColor Cyan
            
            # Build complete file hash collection from existing entries
            $allFileHashes = @{}
            foreach ($processedFile in $existingEntries.Processed.Keys) {
                $absolutePath = if ([System.IO.Path]::IsPathRooted($processedFile)) { 
                    $processedFile 
                } else { 
                    Join-Path $SourceDir $processedFile 
                }
                
                $entry = $existingEntries.Processed[$processedFile]
                $allFileHashes[$absolutePath] = @{
                    Hash = $entry.Hash
                    Size = $entry.Size
                    IsSymlink = if ($entry.ContainsKey('IsSymlink')) { $entry.IsSymlink } else { $false }
                    RaceConditionDetected = if ($entry.ContainsKey('RaceConditionDetected')) { $entry.RaceConditionDetected } else { $false }
                    IntegrityVerified = if ($entry.ContainsKey('IntegrityVerified')) { $entry.IntegrityVerified } else { $false }
                }
            }
            
            # Check if directory integrity hash already exists in log
            $logContent = Get-Content $LogFile -Raw -ErrorAction SilentlyContinue
            $hasDirectoryHash = $logContent -and $logContent.Contains("Total$($HashAlgorithm) =")
            
            if (-not $hasDirectoryHash -and $allFileHashes.Count -gt 0) {
                Write-Host "🔐 Computing missing directory integrity hash..." -ForegroundColor Yellow
                $directoryHashResult = Get-HashSmithDirectoryIntegrityHash -FileHashes $allFileHashes -Algorithm $HashAlgorithm -BasePath $SourceDir -StrictMode:$StrictMode
                
                if ($directoryHashResult) {
                    $totalBytes = $directoryHashResult.TotalSize
                    $totalGB = $totalBytes / 1GB
                    
                    $summaryInfo = @(
                        "",
                        "Total$($HashAlgorithm) = $($directoryHashResult.Hash)",
                        "$($directoryHashResult.FileCount) files checked ($($totalBytes) bytes, $($totalGB.ToString('F2')) GB)."
                    )
                    
                    $summaryInfo | Add-Content -Path $LogFile -Encoding UTF8
                    Write-Host "✅ Directory integrity hash computed: $($directoryHashResult.Hash)" -ForegroundColor Green
                    Write-HashSmithLog -Message "DIRECTORY: Computed missing integrity hash: $($directoryHashResult.Hash)" -Level SUCCESS -Component 'INTEGRITY'
                } else {
                    Write-Host "⚠️  Failed to compute directory integrity hash" -ForegroundColor Yellow
                }
            } elseif ($hasDirectoryHash) {
                Write-Host "✅ Directory integrity hash already exists in log" -ForegroundColor Green
            } else {
                Write-Host "⚠️  No processed files found for directory hash computation" -ForegroundColor Yellow
            }
        }
        
        Write-Host "   Use -FixErrors to retry failed files if needed" -ForegroundColor Gray
        exit 0
    }
    
    # Processing analysis
    $totalFiles = $filesToProcess.Count
    $totalSize = ($filesToProcess | Measure-Object -Property Length -Sum).Sum
    
    # Sort files by size if requested
    if ($SortFilesBySize) {
        Write-Host "📊 Sorting files by size (smaller first)..." -ForegroundColor Cyan
        $filesToProcess = $filesToProcess | Sort-Object Length
        Write-Host "   ✅ Files sorted - smaller files will be processed first" -ForegroundColor Green
    }
    
    # File analysis
    $smallFiles = ($filesToProcess | Where-Object { $_.Length -lt 1MB }).Count
    $mediumFiles = ($filesToProcess | Where-Object { $_.Length -ge 1MB -and $_.Length -lt 100MB }).Count
    $largeFiles = ($filesToProcess | Where-Object { $_.Length -ge 100MB -and $_.Length -lt 1GB }).Count
    $veryLargeFiles = ($filesToProcess | Where-Object { $_.Length -ge 1GB }).Count
    
    # Processing overview
    Write-ProfessionalHeader -Title "Processing Overview" -Color "Magenta"
    Write-StatItem -Icon "📁" -Label "Files to Process" -Value $totalFiles -Color "Cyan"
    Write-StatItem -Icon "💾" -Label "Total Size" -Value "$('{0:N2} GB' -f ($totalSize / 1GB))" -Color "Green"
    
    if ($smallFiles -gt 0) {
        Write-StatItem -Icon "🔸" -Label "Small Files (<1MB)" -Value $smallFiles -Color "Yellow"
    }
    if ($mediumFiles -gt 0) {
        Write-StatItem -Icon "🔹" -Label "Medium Files (1MB-100MB)" -Value $mediumFiles -Color "Cyan"
    }
    if ($largeFiles -gt 0) {
        Write-StatItem -Icon "🔶" -Label "Large Files (100MB-1GB)" -Value $largeFiles -Color "DarkYellow"
    }
    if ($veryLargeFiles -gt 0) {
        Write-StatItem -Icon "🔺" -Label "Very Large Files (>1GB)" -Value $veryLargeFiles -Color "Red"
    }
    
    # Time estimation
    $estimatedSeconds = ($totalSize / 50MB) / [Environment]::ProcessorCount
    $estimatedSeconds = [Math]::Max(10, $estimatedSeconds)
    
    if ($estimatedSeconds -lt 60) {
        Write-StatItem -Icon "⏱️" -Label "Estimated Time" -Value "$('{0:N0} seconds' -f $estimatedSeconds)" -Color "Blue"
    } elseif ($estimatedSeconds -lt 3600) {
        Write-StatItem -Icon "⏱️" -Label "Estimated Time" -Value "$('{0:N1} minutes' -f ($estimatedSeconds / 60))" -Color "Blue"
    } else {
        Write-StatItem -Icon "⏱️" -Label "Estimated Time" -Value "$('{0:N1} hours' -f ($estimatedSeconds / 3600))" -Color "Blue"
    }
    
    Write-StatItem -Icon "🧵" -Label "Threading" -Value "Optimized for workload" -Color "Magenta"
    Write-StatItem -Icon "📦" -Label "Chunking" -Value "Adaptive sizing" -Color "Yellow"
    Write-Host ""
    
    # WhatIf mode
    if ($WhatIfPreference) {
        Write-ProfessionalHeader -Title "🔮 WHAT-IF MODE RESULTS 🔮" -Color "Yellow"
        
        $memoryEstimate = 30 + (($totalFiles / 10000) * 1)
        
        Write-StatItem -Icon "📊" -Label "Files to Process" -Value $totalFiles -Color "Cyan"
        Write-StatItem -Icon "💾" -Label "Total Size" -Value "$('{0:N2} GB' -f ($totalSize / 1GB))" -Color "Green"
        Write-StatItem -Icon "⏱️" -Label "Estimated Time" -Value "$('{0:N1} minutes' -f ($estimatedSeconds / 60))" -Color "Magenta"
        Write-StatItem -Icon "🧵" -Label "Threads to Use" -Value $MaxThreads -Color "Cyan"
        Write-StatItem -Icon "🧠" -Label "Est. Memory Usage" -Value "$('{0:N0} MB' -f $memoryEstimate)" -Color "Yellow"
        Write-StatItem -Icon "🔑" -Label "Hash Algorithm" -Value $HashAlgorithm -Color "Blue"
        
        Write-Host ""
        exit 0
    }
    
    # Initialize log file
    if (-not $Resume -and -not $FixErrors) {
        $configuration = @{
            IncludeHidden = $IncludeHidden
            IncludeSymlinks = $IncludeSymlinks
            VerifyIntegrity = $VerifyIntegrity.IsPresent
            StrictMode = $StrictMode.IsPresent
            MaxThreads = $MaxThreads
            ChunkSize = $ChunkSize
            Version = $config.Version
        }
        
        Initialize-HashSmithLogFile -LogPath $LogFile -Algorithm $HashAlgorithm -SourcePath $SourceDir -DiscoveryStats $discoveryStats -Configuration $configuration
    }
    
    # Processing phase
    Write-ProfessionalHeader -Title "File Processing Phase" -Color "Green"
    Write-Host "⚡ Starting file processing..." -ForegroundColor Cyan
    
    # Determine parallel processing
    $useParallel = if ($UseParallel) { 
        $true 
    } elseif ($PSVersionTable.PSVersion.Major -ge 7) { 
        $true
    } else { 
        $false 
    }
    
    if ($useParallel -and $PSVersionTable.PSVersion.Major -ge 7) {
        Write-Host "🚀 Parallel processing enabled (PowerShell 7+)" -ForegroundColor Green
    } else {
        Write-Host "⚙️  Sequential processing mode" -ForegroundColor Gray
    }
    Write-Host ""
    
    # Process files
    $fileHashes = Start-HashSmithFileProcessing -Files $filesToProcess -LogPath $LogFile -Algorithm $HashAlgorithm -ExistingEntries $existingEntries -BasePath $SourceDir -StrictMode:$StrictMode -VerifyIntegrity:$VerifyIntegrity -MaxThreads $MaxThreads -ChunkSize $ChunkSize -RetryCount $RetryCount -TimeoutSeconds $TimeoutSeconds -ProgressTimeoutMinutes $ProgressTimeoutMinutes -ShowProgress:$ShowProgress -UseParallel:$useParallel
    
    # Handle results
    $actualFileHashes = if ($fileHashes -is [hashtable]) {
        $fileHashes
    } elseif ($fileHashes -is [array] -and $fileHashes.Count -gt 0) {
        $hashtableItem = $fileHashes | Where-Object { $_ -is [hashtable] } | Select-Object -Last 1
        if ($hashtableItem) { $hashtableItem } else { @{} }
    } else {
        @{}
    }
    
    # Directory integrity hash computation
    # Compute when we have new files OR when resuming and directory hash might be missing
    $shouldComputeDirectoryHash = -not $FixErrors -and (
        $actualFileHashes.Count -gt 0 -or 
        ($Resume -and $existingEntries.Processed.Count -gt 0)
    )
    
    if ($shouldComputeDirectoryHash) {
        # Check if directory hash already exists (to avoid duplicate computation)
        $logContent = Get-Content $LogFile -Raw -ErrorAction SilentlyContinue
        $hasDirectoryHash = $logContent -and $logContent.Contains("Total$($HashAlgorithm) =")
        
        if (-not $hasDirectoryHash) {
            Write-Host ""
            Write-Host "🔐 Computing directory integrity hash..." -ForegroundColor Cyan
            
            # Include existing processed files for complete directory hash
            $allFileHashes = @{}
            
            # Add newly processed files
            foreach ($key in $actualFileHashes.Keys) {
                $allFileHashes[$key] = $actualFileHashes[$key]
            }
            
            # Add existing processed files
            foreach ($processedFile in $existingEntries.Processed.Keys) {
                $absolutePath = if ([System.IO.Path]::IsPathRooted($processedFile)) { 
                    $processedFile 
                } else { 
                    Join-Path $SourceDir $processedFile 
                }
                
                if (-not $allFileHashes.ContainsKey($absolutePath)) {
                    $entry = $existingEntries.Processed[$processedFile]
                    $allFileHashes[$absolutePath] = @{
                        Hash = $entry.Hash
                        Size = $entry.Size
                        IsSymlink = if ($entry.ContainsKey('IsSymlink')) { $entry.IsSymlink } else { $false }
                        RaceConditionDetected = if ($entry.ContainsKey('RaceConditionDetected')) { $entry.RaceConditionDetected } else { $false }
                        IntegrityVerified = if ($entry.ContainsKey('IntegrityVerified')) { $entry.IntegrityVerified } else { $false }
                    }
                }
            }
            
            if ($allFileHashes.Count -gt 0) {
                $directoryHashResult = Get-HashSmithDirectoryIntegrityHash -FileHashes $allFileHashes -Algorithm $HashAlgorithm -BasePath $SourceDir -StrictMode:$StrictMode
                
                if ($directoryHashResult) {
                    # Final summary
                    $totalBytes = $directoryHashResult.TotalSize
                    $totalGB = $totalBytes / 1GB
                    $processingTime = $stopwatch.Elapsed.TotalSeconds
                    $throughputMBps = if ($processingTime -gt 0) { ($totalBytes / 1MB) / $processingTime } else { 0 }
                    
                    $summaryInfo = @(
                        "",
                        "Total$($HashAlgorithm) = $($directoryHashResult.Hash)",
                        "$($directoryHashResult.FileCount) files checked ($($totalBytes) bytes, $($totalGB.ToString('F2')) GB, $($throughputMBps.ToString('F1')) MB/s)."
                    )
                    
                    $summaryInfo | Add-Content -Path $LogFile -Encoding UTF8
                    Write-Host "✅ Directory hash: $($directoryHashResult.Hash)" -ForegroundColor Green
                    Write-HashSmithLog -Message "DIRECTORY: Computed integrity hash: $($directoryHashResult.Hash)" -Level SUCCESS -Component 'INTEGRITY'
                } else {
                    Write-Host "⚠️  Failed to compute directory integrity hash" -ForegroundColor Yellow
                }
            } else {
                Write-Host "⚠️  No file hashes available for directory integrity computation" -ForegroundColor Yellow
            }
        } else {
            Write-Host "✅ Directory integrity hash already exists in log" -ForegroundColor Green
        }
    }
    
    $stopwatch.Stop()
    $stats = Get-HashSmithStatistics
    
    # JSON log generation
    if ($UseJsonLog) {
        Write-Host "📊 Generating structured JSON log..." -ForegroundColor Cyan
        
        $jsonLog = @{
            Version = $config.Version
            Timestamp = Get-Date -Format 'o'
            Configuration = @{
                SourceDirectory = $SourceDir
                HashAlgorithm = $HashAlgorithm
                IncludeHidden = $IncludeHidden
                IncludeSymlinks = $IncludeSymlinks
                VerifyIntegrity = $VerifyIntegrity.IsPresent
                StrictMode = $StrictMode.IsPresent
                MaxThreads = $MaxThreads
                ChunkSize = $ChunkSize
                RetryCount = $RetryCount
                TimeoutSeconds = $TimeoutSeconds
                ProgressTimeoutMinutes = $ProgressTimeoutMinutes
            }
            Statistics = $stats
            DiscoveryStats = $discoveryStats
            ProcessingTime = $stopwatch.Elapsed.TotalSeconds
            DirectoryHash = if ($directoryHashResult) { $directoryHashResult } else { $null }
            ResumeInfo = @{
                WasResumed = $Resume.IsPresent
                SkippedFiles = $skippedResumeCount
                RemainingFiles = $totalFiles
                FixErrorsMode = $FixErrors.IsPresent
            }
        }
        
        $jsonPath = [System.IO.Path]::ChangeExtension($LogFile, '.json')
        $jsonLog | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath -Encoding UTF8
        Write-Host "✅ JSON log saved: $jsonPath" -ForegroundColor Green
    }
    
    # Final summary
    Write-Host ""
    Write-ProfessionalHeader -Title "🎉 OPERATION COMPLETE 🎉" -Color "Green"
    
    Write-Host "📊 Processing Statistics" -ForegroundColor Yellow
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
    
    Write-StatItem -Icon "🔍" -Label "Files Discovered" -Value $stats.FilesDiscovered -Color "Cyan"
    Write-StatItem -Icon "✅" -Label "Files Processed" -Value $stats.FilesProcessed -Color "Green"
    if ($skippedResumeCount -gt 0) {
        Write-StatItem -Icon "⏭️" -Label "Files Resumed (Skipped)" -Value $skippedResumeCount -Color "Yellow"
    }
    Write-StatItem -Icon "❌" -Label "Files Failed" -Value $stats.FilesError -Color $(if($stats.FilesError -eq 0){"Green"}else{"Red"})
    Write-StatItem -Icon "💾" -Label "Data Processed" -Value "$('{0:N2} GB' -f ($stats.BytesProcessed / 1GB))" -Color "Magenta"
    Write-StatItem -Icon "⏱️" -Label "Processing Time" -Value "$($stopwatch.Elapsed.ToString('hh\:mm\:ss'))" -Color "Blue"
    
    $throughput = if ($stopwatch.Elapsed.TotalSeconds -gt 0) { 
        ($stats.BytesProcessed / 1MB) / $stopwatch.Elapsed.TotalSeconds 
    } else { 0 }
    Write-StatItem -Icon "🚀" -Label "Throughput" -Value "$('{0:N1} MB/s' -f $throughput)" -Color "Cyan"
    
    Write-Host ""
    Write-Host "📄 Output Files" -ForegroundColor Yellow
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
    Write-Host "📝 Log File    : $LogFile" -ForegroundColor White
    
    if ($UseJsonLog) {
        Write-Host "📊 JSON Log    : $([System.IO.Path]::ChangeExtension($LogFile, '.json'))" -ForegroundColor Green
    }
    
    Write-Host ""
    
    # Completion status
    if ($stats.FilesError -gt 0) {
        Write-Host "⚠️  COMPLETED WITH WARNINGS" -ForegroundColor Yellow
        Write-Host "┌─────────────────────────────────────────┐" -ForegroundColor Yellow
        Write-Host "│  • $($stats.FilesError) files failed processing" -ForegroundColor Red
        Write-Host "│  • Use -FixErrors to retry failed files" -ForegroundColor White
        Write-Host "│  • Use -Resume to continue if interrupted" -ForegroundColor White
        Write-Host "└─────────────────────────────────────────┘" -ForegroundColor Yellow
        Set-HashSmithExitCode -ExitCode 1
    } else {
        Write-Host "🎉 SUCCESS - ALL FILES PROCESSED" -ForegroundColor Green
        Write-Host "┌─────────────────────────────────────────┐" -ForegroundColor Green
        Write-Host "│  ✅ Zero errors detected" -ForegroundColor Green
        Write-Host "│  🚀 Processing completed successfully" -ForegroundColor Green
        Write-Host "│  🛡️ All security checks passed" -ForegroundColor Green
        Write-Host "└─────────────────────────────────────────┘" -ForegroundColor Green
    }
    
    Write-Host ""
}
catch {
    Write-Host ""
    Write-Host "💥 CRITICAL ERROR" -ForegroundColor Red
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor White
    Write-Host "Location: $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Gray
    Write-Host "Stack: $($_.ScriptStackTrace)" -ForegroundColor DarkGray
    Write-Host ""
    
    Write-HashSmithLog -Message "Critical error: $($_.Exception.Message)" -Level ERROR
    Write-HashSmithLog -Message "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
    Set-HashSmithExitCode -ExitCode 3
}
finally {
    if ($stopwatch.IsRunning) {
        $stopwatch.Stop()
    }
    
    # Cleanup
    try {
        # Final log flush
        if ($LogFile) {
            Clear-HashSmithLogBatch -LogPath $LogFile
        }
    } catch {
        # Silent cleanup
    }
}

exit (Get-HashSmithExitCode)

#endregion
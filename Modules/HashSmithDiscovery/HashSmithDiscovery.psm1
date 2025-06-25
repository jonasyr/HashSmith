<#
.SYNOPSIS
    File discovery engine for HashSmith

.DESCRIPTION
    This module provides comprehensive file discovery capabilities with enhanced validation,
    symbolic link detection, and completeness testing.
#>

# Import required modules
# Note: Dependencies are handled by the main script import order

#region Public Functions

<#
.SYNOPSIS
    Discovers all files in a directory tree with comprehensive validation

.DESCRIPTION
    Performs memory-efficient file discovery using .NET APIs with support for
    hidden files, symbolic links, exclusion patterns, and integrity validation.

.PARAMETER Path
    The root path to discover files from

.PARAMETER ExcludePatterns
    Array of wildcard patterns to exclude files

.PARAMETER IncludeHidden
    Include hidden and system files

.PARAMETER IncludeSymlinks
    Include symbolic links and reparse points

.PARAMETER TestMode
    Run in test mode with completeness validation

.PARAMETER StrictMode
    Enable strict mode with maximum validation

.EXAMPLE
    $result = Get-HashSmithAllFiles -Path "C:\Data" -IncludeHidden -StrictMode
#>
function Get-HashSmithAllFiles {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        
        [string[]]$ExcludePatterns = @(),
        
        [switch]$IncludeHidden,
        
        [switch]$IncludeSymlinks,
        
        [switch]$TestMode,
        
        [switch]$StrictMode
    )
    
    Write-HashSmithLog -Message "Starting comprehensive file discovery with enhanced validation" -Level INFO -Component 'DISCOVERY'
    Write-HashSmithLog -Message "Target path: $Path" -Level INFO -Component 'DISCOVERY'
    Write-HashSmithLog -Message "Include hidden: $IncludeHidden" -Level INFO -Component 'DISCOVERY'
    Write-HashSmithLog -Message "Include symlinks: $IncludeSymlinks" -Level INFO -Component 'DISCOVERY'
    Write-HashSmithLog -Message "Strict mode: $StrictMode" -Level INFO -Component 'DISCOVERY'
    
    $discoveryStart = Get-Date
    $allFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    $errors = [System.Collections.Generic.List[hashtable]]::new()
    $symlinkCount = 0
    $timeoutMinutes = 30  # Add discovery timeout
    
    # Test network connectivity first
    if (-not (Test-HashSmithNetworkPath -Path $Path -UseCache)) {
        throw "Network path is not accessible: $Path"
    }
    
    try {
        # Use .NET Directory.EnumerateFiles for memory efficiency
        $normalizedPath = Get-HashSmithNormalizedPath -Path $Path
        
        $enumOptions = [System.IO.EnumerationOptions]::new()
        $enumOptions.RecurseSubdirectories = $true
        $enumOptions.IgnoreInaccessible = $false
        $enumOptions.ReturnSpecialDirectories = $false
        $enumOptions.AttributesToSkip = if ($IncludeHidden) { 
            [System.IO.FileAttributes]::None 
        } else { 
            [System.IO.FileAttributes]::Hidden -bor [System.IO.FileAttributes]::System
        }
        
        Write-HashSmithLog -Message "Using .NET Directory.EnumerateFiles for memory-efficient discovery" -Level DEBUG -Component 'DISCOVERY'
        
        # Use parallel discovery if PowerShell 7+ is available
        if ($PSVersionTable.PSVersion.Major -ge 7 -and -not $StrictMode) {
            Write-HashSmithLog -Message "Using parallel file discovery (PowerShell 7+)" -Level INFO -Component 'DISCOVERY'
            
            # First, get all directories for parallel processing
            $directories = @($normalizedPath)
            try {
                $directories += [System.IO.Directory]::EnumerateDirectories($normalizedPath, '*', [System.IO.SearchOption]::AllDirectories)
            } catch {
                Write-HashSmithLog -Message "Error enumerating directories: $($_.Exception.Message)" -Level WARN -Component 'DISCOVERY'
            }
            
            Write-HashSmithLog -Message "📁 Found $($directories.Count) directories to scan" -Level INFO -Component 'DISCOVERY'
            
            # Process directories in parallel to discover files
            $processedCount = 0
            $skippedCount = 0
            $directoryIndex = 0
            
            $allFileResults = $directories | ForEach-Object -Parallel {
                $directory = $_
                $localFiles = @()
                $localErrors = @()
                $localSkipped = 0
                $localSymlinks = 0
                
                # Import variables into parallel runspace
                $IncludeHidden = $using:IncludeHidden
                $IncludeSymlinks = $using:IncludeSymlinks
                $ExcludePatterns = $using:ExcludePatterns
                
                try {
                    # Create enumeration options for this directory
                    $localEnumOptions = [System.IO.EnumerationOptions]::new()
                    $localEnumOptions.RecurseSubdirectories = $false  # Only process current directory
                    $localEnumOptions.IgnoreInaccessible = $false
                    $localEnumOptions.ReturnSpecialDirectories = $false
                    $localEnumOptions.AttributesToSkip = if ($IncludeHidden) { 
                        [System.IO.FileAttributes]::None 
                    } else { 
                        [System.IO.FileAttributes]::Hidden -bor [System.IO.FileAttributes]::System
                    }
                    
                    # Enumerate files in this directory only
                    $fileEnumerator = [System.IO.Directory]::EnumerateFiles($directory, '*', $localEnumOptions)
                    
                    foreach ($filePath in $fileEnumerator) {
                        try {
                            $fileInfo = [System.IO.FileInfo]::new($filePath)
                            
                            # Check if it's a symbolic link (simplified check)
                            $isSymlink = ($fileInfo.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq [System.IO.FileAttributes]::ReparsePoint
                            if ($isSymlink) {
                                $localSymlinks++
                                if (-not $IncludeSymlinks) {
                                    $localSkipped++
                                    continue
                                }
                            }
                            
                            # Apply exclusion patterns
                            $shouldExclude = $false
                            foreach ($pattern in $ExcludePatterns) {
                                if ($fileInfo.Name -like $pattern -or $fileInfo.FullName -like $pattern) {
                                    $shouldExclude = $true
                                    $localSkipped++
                                    break
                                }
                            }
                            
                            if (-not $shouldExclude) {
                                $localFiles += $fileInfo
                            }
                        }
                        catch {
                            $localErrors += @{
                                Path = $filePath
                                Error = $_.Exception.Message
                                Timestamp = Get-Date
                                Category = 'FileAccess'
                            }
                        }
                    }
                } catch {
                    $localErrors += @{
                        Path = $directory
                        Error = $_.Exception.Message
                        Timestamp = Get-Date
                        Category = 'DirectoryAccess'
                    }
                }
                
                return @{
                    Files = $localFiles
                    Errors = $localErrors
                    Skipped = $localSkipped
                    Symlinks = $localSymlinks
                    Directory = $directory
                }
            } -ThrottleLimit ([Environment]::ProcessorCount)
            
            # Combine results from parallel processing
            foreach ($result in $allFileResults) {
                $directoryIndex++
                
                foreach ($file in $result.Files) {
                    $allFiles.Add($file)
                }
                
                foreach ($error in $result.Errors) {
                    $errors.Add($error)
                }
                
                $processedCount += $result.Files.Count
                $skippedCount += $result.Skipped
                $symlinkCount += $result.Symlinks
                
                # Update progress every few directories with overwrite capability
                if ($directoryIndex % 10 -eq 0 -or $directoryIndex -eq $directories.Count) {
                    $progressMessage = "🔍 Discovered: $processedCount files | Skipped: $skippedCount | Dirs: $directoryIndex/$($directories.Count)"
                    Write-Host "`r$progressMessage" -NoNewline -ForegroundColor Cyan
                }
            }
            
            # Clear the progress line
            Write-Host "`r$(' ' * 120)`r" -NoNewline
            
        } else {
            # Use sequential discovery for PowerShell 5.1 or strict mode
            Write-HashSmithLog -Message "Using sequential file discovery" -Level INFO -Component 'DISCOVERY'
            
            # Enumerate files in streaming fashion to reduce memory usage
            $fileEnumerator = [System.IO.Directory]::EnumerateFiles($normalizedPath, '*', $enumOptions)
            $processedCount = 0
            $skippedCount = 0
            $lastProgressUpdate = Get-Date
            
            foreach ($filePath in $fileEnumerator) {
                try {
                    # Progress reporting with overwrite capability
                    if (((Get-Date) - $lastProgressUpdate).TotalSeconds -ge 1) {
                        $progressMessage = "🔍 Discovering files: $processedCount found | $skippedCount skipped"
                        Write-Host "`r$progressMessage" -NoNewline -ForegroundColor Cyan
                        $lastProgressUpdate = Get-Date
                    }
                    
                    # Check for discovery timeout
                    if (((Get-Date) - $discoveryStart).TotalMinutes -gt $timeoutMinutes) {
                        Write-Host "`r$(' ' * 80)`r" -NoNewline  # Clear progress line
                        Write-HashSmithLog -Message "Discovery timeout reached ($timeoutMinutes minutes), stopping enumeration" -Level WARN -Component 'DISCOVERY'
                        break
                    }
                    
                    # Check circuit breaker periodically
                    if ($processedCount % 1000 -eq 0 -and -not (Test-HashSmithCircuitBreaker -Component 'DISCOVERY')) {
                        Write-Host "`r$(' ' * 80)`r" -NoNewline  # Clear progress line
                        Write-HashSmithLog -Message "Discovery halted due to circuit breaker" -Level ERROR -Component 'DISCOVERY'
                        break
                    }
                    
                    $fileInfo = [System.IO.FileInfo]::new($filePath)
                    
                    # Handle symbolic links
                    $isSymlink = Test-HashSmithSymbolicLink -Path $filePath
                    if ($isSymlink) {
                        $symlinkCount++
                        if (-not $IncludeSymlinks) {
                            $skippedCount++
                            Write-HashSmithLog -Message "Skipped symbolic link: $($fileInfo.Name)" -Level DEBUG -Component 'DISCOVERY'
                            continue
                        }
                    }
                    
                    # Apply exclusion patterns
                    $shouldExclude = $false
                    foreach ($pattern in $ExcludePatterns) {
                        if ($fileInfo.Name -like $pattern -or $fileInfo.FullName -like $pattern) {
                            $shouldExclude = $true
                            $skippedCount++
                            Write-HashSmithLog -Message "Excluded by pattern '$pattern': $($fileInfo.Name)" -Level DEBUG -Component 'DISCOVERY'
                            break
                        }
                    }
                    
                    if (-not $shouldExclude) {
                        # Strict mode validation
                        if ($StrictMode) {
                            # Verify file is still accessible
                            if (-not (Test-Path -LiteralPath $fileInfo.FullName)) {
                                Write-HashSmithLog -Message "File disappeared during discovery: $($fileInfo.Name)" -Level WARN -Component 'DISCOVERY'
                                continue
                            }
                            
                            # Get integrity snapshot for later verification
                            $snapshot = Get-HashSmithFileIntegritySnapshot -Path $fileInfo.FullName
                            if ($snapshot) {
                                Add-Member -InputObject $fileInfo -NotePropertyName 'IntegritySnapshot' -NotePropertyValue $snapshot
                            }
                        }
                        
                        $allFiles.Add($fileInfo)
                        $processedCount++
                    }
                }
                catch {
                    $errorDetails = @{
                        Path = $filePath
                        Error = $_.Exception.Message
                        Timestamp = Get-Date
                        Category = 'FileAccess'
                    }
                    $errors.Add($errorDetails)
                    Write-HashSmithLog -Message "Error accessing file during discovery: $([System.IO.Path]::GetFileName($filePath)) - $($_.Exception.Message)" -Level WARN -Component 'DISCOVERY'
                    Update-HashSmithCircuitBreaker -IsFailure:$true -Component 'DISCOVERY'
                }
            }
            
            # Clear the progress line
            Write-Host "`r$(' ' * 80)`r" -NoNewline
        }
        
    }
    catch {
        Write-HashSmithLog -Message "Critical error during file discovery: $($_.Exception.Message)" -Level ERROR -Component 'DISCOVERY'
        $stats = Get-HashSmithStatistics
        $stats.DiscoveryErrors += @{
            Path = $Path
            Error = $_.Exception.Message
            Timestamp = Get-Date
            Category = 'Critical'
        }
        throw
    }
    
    $discoveryDuration = (Get-Date) - $discoveryStart
    
    # Update statistics properly using the new functions
    Set-HashSmithStatistic -Name 'FilesDiscovered' -Value $allFiles.Count
    Set-HashSmithStatistic -Name 'FilesSymlinks' -Value $symlinkCount
    
    Write-HashSmithLog -Message "File discovery completed in $($discoveryDuration.TotalSeconds.ToString('F2')) seconds" -Level SUCCESS -Component 'DISCOVERY'
    Write-HashSmithLog -Message "Files found: $($allFiles.Count)" -Level STATS -Component 'DISCOVERY'
    Write-HashSmithLog -Message "Files skipped: $skippedCount" -Level STATS -Component 'DISCOVERY'
    Write-HashSmithLog -Message "Symbolic links found: $symlinkCount" -Level STATS -Component 'DISCOVERY'
    Write-HashSmithLog -Message "Discovery errors: $($errors.Count)" -Level $(if($errors.Count -gt 0){'WARN'}else{'STATS'}) -Component 'DISCOVERY'
    
    if ($TestMode) {
        Write-HashSmithLog -Message "Test Mode: Validating file discovery completeness and integrity" -Level INFO -Component 'TEST'
        Test-HashSmithFileDiscoveryCompleteness -Path $Path -DiscoveredFiles $allFiles.ToArray() -IncludeHidden:$IncludeHidden -IncludeSymlinks:$IncludeSymlinks -StrictMode:$StrictMode
    }
    
    return @{
        Files = $allFiles.ToArray()
        Errors = $errors.ToArray()
        Statistics = @{
            TotalFound = $allFiles.Count
            TotalSkipped = $skippedCount
            TotalErrors = $errors.Count
            TotalSymlinks = $symlinkCount
            DiscoveryTime = $discoveryDuration.TotalSeconds
        }
    }
}

<#
.SYNOPSIS
    Tests file discovery completeness and accuracy

.DESCRIPTION
    Cross-validates file discovery results using multiple methods to ensure
    completeness and accuracy of the discovery process.

.PARAMETER Path
    The root path that was discovered

.PARAMETER DiscoveredFiles
    Array of discovered files to validate

.PARAMETER IncludeHidden
    Whether hidden files were included

.PARAMETER IncludeSymlinks
    Whether symbolic links were included

.PARAMETER StrictMode
    Enable strict validation mode

.EXAMPLE
    Test-HashSmithFileDiscoveryCompleteness -Path $path -DiscoveredFiles $files -StrictMode
#>
function Test-HashSmithFileDiscoveryCompleteness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        
        [Parameter(Mandatory)]
        [System.IO.FileInfo[]]$DiscoveredFiles,
        
        [switch]$IncludeHidden,
        
        [switch]$IncludeSymlinks,
        
        [switch]$StrictMode
    )
    
    Write-HashSmithLog -Message "Running enhanced file discovery completeness test" -Level INFO -Component 'TEST'
    
    # Cross-validate with PowerShell Get-ChildItem
    $psFiles = @()
    try {
        $getChildItemParams = @{
            Path = $Path
            Recurse = $true
            File = $true
            Force = $IncludeHidden
            ErrorAction = 'SilentlyContinue'
        }
        
        $psFiles = @(Get-ChildItem @getChildItemParams)
        
        # Filter out symlinks if not included
        if (-not $IncludeSymlinks) {
            $psFiles = $psFiles | Where-Object {
                -not (($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq [System.IO.FileAttributes]::ReparsePoint)
            }
        }
        
        $dotNetCount = $DiscoveredFiles.Count
        $psCount = $psFiles.Count
        
        Write-HashSmithLog -Message ".NET Discovery: $dotNetCount files" -Level INFO -Component 'TEST'
        Write-HashSmithLog -Message "PowerShell Discovery: $psCount files" -Level INFO -Component 'TEST'
        
        # Allow for small discrepancies due to timing
        $tolerance = if ($StrictMode) { 0 } else { [Math]::Max(1, [Math]::Floor($dotNetCount * 0.001)) }
        $difference = [Math]::Abs($dotNetCount - $psCount)
        
        if ($difference -gt $tolerance) {
            Write-HashSmithLog -Message "WARNING: File count mismatch detected! Difference: $difference (tolerance: $tolerance)" -Level WARN -Component 'TEST'
            Write-HashSmithLog -Message "This may indicate discovery issues or timing differences" -Level WARN -Component 'TEST'
            
            # Detailed analysis in strict mode
            if ($StrictMode) {
                $dotNetPaths = $DiscoveredFiles | ForEach-Object { $_.FullName.ToLowerInvariant() }
                $psPaths = $psFiles | ForEach-Object { $_.FullName.ToLowerInvariant() }
                
                $missingInDotNet = $psPaths | Where-Object { $_ -notin $dotNetPaths }
                $missingInPS = $dotNetPaths | Where-Object { $_ -notin $psPaths }
                
                if ($missingInDotNet) {
                    Write-HashSmithLog -Message "Files found by PowerShell but not .NET: $($missingInDotNet.Count)" -Level ERROR -Component 'TEST'
                    $missingInDotNet | Select-Object -First 10 | ForEach-Object {
                        Write-HashSmithLog -Message "  Missing: $_" -Level DEBUG -Component 'TEST'
                    }
                }
                
                if ($missingInPS) {
                    Write-HashSmithLog -Message "Files found by .NET but not PowerShell: $($missingInPS.Count)" -Level ERROR -Component 'TEST'
                    $missingInPS | Select-Object -First 10 | ForEach-Object {
                        Write-HashSmithLog -Message "  Extra: $_" -Level DEBUG -Component 'TEST'
                    }
                }
                
                if ($difference -gt 0) {
                    Set-HashSmithExitCode -ExitCode 2  # Indicate discovery issues
                }
            }
        } else {
            Write-HashSmithLog -Message "File discovery completeness test PASSED (difference: $difference, tolerance: $tolerance)" -Level SUCCESS -Component 'TEST'
        }
        
        # Additional validation in strict mode
        if ($StrictMode) {
            Write-HashSmithLog -Message "Running additional strict mode validations" -Level INFO -Component 'TEST'
            
            # Check for duplicate paths
            $duplicates = $DiscoveredFiles | Group-Object FullName | Where-Object Count -gt 1
            if ($duplicates) {
                Write-HashSmithLog -Message "WARNING: Duplicate file paths detected: $($duplicates.Count)" -Level WARN -Component 'TEST'
                $duplicates | Select-Object -First 5 | ForEach-Object {
                    Write-HashSmithLog -Message "  Duplicate: $($_.Name)" -Level DEBUG -Component 'TEST'
                }
            }
            
            # Validate path lengths
            $longPaths = $DiscoveredFiles | Where-Object { $_.FullName.Length -gt 260 }
            if ($longPaths) {
                Write-HashSmithLog -Message "Long paths detected: $($longPaths.Count)" -Level INFO -Component 'TEST'
            }
            
            # Check for potential encoding issues
            $unicodePaths = $DiscoveredFiles | Where-Object { $_.FullName -match '[^\x00-\x7F]' }
            if ($unicodePaths) {
                Write-HashSmithLog -Message "Unicode paths detected: $($unicodePaths.Count)" -Level INFO -Component 'TEST'
            }
        }
        
    }
    catch {
        Write-HashSmithLog -Message "File discovery test failed: $($_.Exception.Message)" -Level ERROR -Component 'TEST'
    }
}

#endregion

# Export public functions
Export-ModuleMember -Function @(
    'Get-HashSmithAllFiles',
    'Test-HashSmithFileDiscoveryCompleteness'
)

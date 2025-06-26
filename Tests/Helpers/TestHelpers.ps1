<#
.SYNOPSIS
    Test helper functions for HashSmith Pester test suite

.DESCRIPTION
    Provides utility functions for setting up test data, mocking dependencies,
    and common test operations across the HashSmith test suite.

.NOTES
    Version: 1.0.0
    Should be dot-sourced by main test file
#>

<#
.SYNOPSIS
    Initializes test data files in the SampleData directory
#>
function Initialize-TestData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SampleDataPath
    )
    
    Write-Verbose "Initializing test data in: $SampleDataPath"
    
    # Ensure sample data directory exists
    if (-not (Test-Path $SampleDataPath)) {
        New-Item -Path $SampleDataPath -ItemType Directory -Force | Out-Null
    }
    
    # Create small text file
    $smallTextFile = Join-Path $SampleDataPath "small_text_file.txt"
    if (-not (Test-Path $smallTextFile)) {
        $textContent = @"
This is a small test text file for HashSmith testing.
It contains multiple lines of text to verify hash computation.
Line 3: Lorem ipsum dolor sit amet, consectetur adipiscing elit.
Line 4: Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.
Line 5: Ut enim ad minim veniam, quis nostrud exercitation ullamco.
Final line: End of test file content.
"@
        $textContent | Set-Content -Path $smallTextFile -Encoding UTF8
        Write-Verbose "Created small text file: $smallTextFile"
    }
    
    # Create larger binary file (1MB)
    $binaryFile = Join-Path $SampleDataPath "binary_file.bin"
    if (-not (Test-Path $binaryFile)) {
        $binaryData = [byte[]]::new(1048576)  # 1MB
        $random = [System.Random]::new(12345)  # Seed for reproducible data
        $random.NextBytes($binaryData)
        [System.IO.File]::WriteAllBytes($binaryFile, $binaryData)
        Write-Verbose "Created binary file: $binaryFile (1MB)"
    }
    
    # Create corrupted file (simulates corruption)
    $corruptedFile = Join-Path $SampleDataPath "corrupted_file.txt"
    if (-not (Test-Path $corruptedFile)) {
        $corruptedContent = @"
This file simulates corruption scenarios.
Normal content here...
$(([char]0x00) * 10)Embedded null bytes$(([char]0x00) * 5)
Some more content with unusual characters: àáâãäåæçèéêë
Binary-like data: $([System.Text.Encoding]::ASCII.GetString(@(0x01, 0x02, 0x03, 0x04, 0xFF, 0xFE)))
End of corrupted file.
"@
        $corruptedContent | Set-Content -Path $corruptedFile -Encoding UTF8
        Write-Verbose "Created corrupted file: $corruptedFile"
    }
    
    # Create hidden test file (Windows-specific)
    $hiddenFile = Join-Path $SampleDataPath "hidden_file.txt"
    if (-not (Test-Path $hiddenFile)) {
        "Hidden file content for testing include/exclude functionality." | Set-Content -Path $hiddenFile -Encoding UTF8
        try {
            if ($IsWindows -or $env:OS -eq "Windows_NT") {
                $fileInfo = Get-Item $hiddenFile
                $fileInfo.Attributes = $fileInfo.Attributes -bor [System.IO.FileAttributes]::Hidden
                Write-Verbose "Created hidden file: $hiddenFile"
            }
        } catch {
            Write-Verbose "Could not set hidden attribute (may not be Windows): $($_.Exception.Message)"
        }
    }
    
    # Create temporary test files
    $tempFile = Join-Path $SampleDataPath "temp_file.tmp"
    if (-not (Test-Path $tempFile)) {
        "Temporary file for exclusion pattern testing." | Set-Content -Path $tempFile -Encoding UTF8
        Write-Verbose "Created temp file: $tempFile"
    }
    
    # Create subdirectory with files
    $subDir = Join-Path $SampleDataPath "SubDirectory"
    if (-not (Test-Path $subDir)) {
        New-Item -Path $subDir -ItemType Directory -Force | Out-Null
        
        # Create file in subdirectory
        $subFile = Join-Path $subDir "sub_file.txt"
        "File in subdirectory for recursive discovery testing." | Set-Content -Path $subFile -Encoding UTF8
        Write-Verbose "Created subdirectory file: $subFile"
    }
    
    # Create Unicode filename test file
    $unicodeFile = Join-Path $SampleDataPath "üñíçødé_file.txt"
    if (-not (Test-Path $unicodeFile)) {
        try {
            "Unicode filename test content: àáâãäåæçèéêëìíîïðñòóôõö÷øùúûüýþÿ" | Set-Content -Path $unicodeFile -Encoding UTF8
            Write-Verbose "Created Unicode filename file: $unicodeFile"
        } catch {
            Write-Verbose "Could not create Unicode filename file: $($_.Exception.Message)"
            # Fallback to ASCII name
            $asciiFallback = Join-Path $SampleDataPath "unicode_fallback_file.txt"
            "Unicode content test (ASCII filename): àáâãäåæçèéêëìíîïðñòóôõö÷øùúûüýþÿ" | Set-Content -Path $asciiFallback -Encoding UTF8
            Write-Verbose "Created ASCII fallback file: $asciiFallback"
        }
    }
    
    Write-Verbose "Test data initialization complete"
}

<#
.SYNOPSIS
    Creates a mock file system structure for testing
#>
function New-MockFileStructure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BasePath,
        
        [hashtable]$Structure = @{
            "file1.txt" = "Content of file 1"
            "file2.bin" = [byte[]](1..100)
            "subdir1/nested.txt" = "Nested file content"
            "subdir2/deep/deeper.txt" = "Deep nested content"
        }
    )
    
    foreach ($path in $Structure.Keys) {
        $fullPath = Join-Path $BasePath $path
        $directory = Split-Path $fullPath -Parent
        
        # Create directory if it doesn't exist
        if ($directory -and -not (Test-Path $directory)) {
            New-Item -Path $directory -ItemType Directory -Force | Out-Null
        }
        
        # Create file with appropriate content
        $content = $Structure[$path]
        if ($content -is [byte[]]) {
            [System.IO.File]::WriteAllBytes($fullPath, $content)
        } else {
            $content | Set-Content -Path $fullPath -Encoding UTF8
        }
    }
}

<#
.SYNOPSIS
    Calculates expected hash for test verification
#>
function Get-ExpectedTestHash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        
        [ValidateSet('MD5', 'SHA1', 'SHA256', 'SHA512')]
        [string]$Algorithm = 'MD5'
    )
    
    if (-not (Test-Path $FilePath)) {
        throw "Test file not found: $FilePath"
    }
    
    $hashAlgorithm = [System.Security.Cryptography.HashAlgorithm]::Create($Algorithm)
    try {
        $fileStream = [System.IO.File]::OpenRead($FilePath)
        try {
            $hashBytes = $hashAlgorithm.ComputeHash($fileStream)
            return [System.BitConverter]::ToString($hashBytes) -replace '-', '' | ForEach-Object { $_.ToLower() }
        }
        finally {
            $fileStream.Close()
        }
    }
    finally {
        $hashAlgorithm.Dispose()
    }
}

<#
.SYNOPSIS
    Creates a test configuration hashtable
#>
function New-TestConfiguration {
    [CmdletBinding()]
    param(
        [hashtable]$Overrides = @{}
    )
    
    $defaultConfig = @{
        Algorithm = 'MD5'
        TargetPath = $env:TEMP
        MaxParallelJobs = 2
        ChunkSize = 10
        RetryCount = 2
        TimeoutSeconds = 15
        TestMode = $true
        StrictMode = $false
        VerifyIntegrity = $false
        IncludeHidden = $true
        IncludeSymlinks = $false
        LogLevel = 'INFO'
        BufferSize = 65536
    }
    
    # Apply overrides
    foreach ($key in $Overrides.Keys) {
        $defaultConfig[$key] = $Overrides[$key]
    }
    
    return $defaultConfig
}

<#
.SYNOPSIS
    Validates that a hash string matches expected format
#>
function Test-HashFormat {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Hash,
        
        [ValidateSet('MD5', 'SHA1', 'SHA256', 'SHA512')]
        [string]$Algorithm = 'MD5'
    )
    
    $expectedLengths = @{
        'MD5' = 32
        'SHA1' = 40
        'SHA256' = 64
        'SHA512' = 128
    }
    
    $expectedLength = $expectedLengths[$Algorithm]
    
    # Check length
    if ($Hash.Length -ne $expectedLength) {
        return $false
    }
    
    # Check format (hex characters only)
    if ($Hash -notmatch '^[a-f0-9]+$') {
        return $false
    }
    
    return $true
}

<#
.SYNOPSIS
    Measures execution time of a script block
#>
function Measure-TestExecution {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,
        
        [hashtable]$Parameters = @{}
    )
    
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    try {
        $result = & $ScriptBlock @Parameters
        $stopwatch.Stop()
        
        return @{
            Result = $result
            Duration = $stopwatch.Elapsed
            Success = $true
            Error = $null
        }
    }
    catch {
        $stopwatch.Stop()
        return @{
            Result = $null
            Duration = $stopwatch.Elapsed
            Success = $false
            Error = $_.Exception
        }
    }
}

<#
.SYNOPSIS
    Creates a temporary test directory with cleanup registration
#>
function New-TestDirectory {
    [CmdletBinding()]
    param(
        [string]$Prefix = "HashSmithTest"
    )
    
    $testDir = Join-Path $env:TEMP "$Prefix`_$(Get-Date -Format 'yyyyMMdd_HHmmss')_$(Get-Random -Maximum 9999)"
    New-Item -Path $testDir -ItemType Directory -Force | Out-Null
    
    # Register cleanup (if running in Pester context)
    if (Get-Variable -Name "Pester" -Scope Global -ErrorAction SilentlyContinue) {
        $Global:TestCleanupPaths += $testDir
    }
    
    return $testDir
}

<#
.SYNOPSIS
    Validates log file format and content
#>
function Test-LogFileFormat {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LogPath,
        
        [string]$ExpectedAlgorithm,
        
        [string]$ExpectedSourcePath
    )
    
    if (-not (Test-Path $LogPath)) {
        return @{ IsValid = $false; Reason = "Log file does not exist" }
    }
    
    $content = Get-Content $LogPath -Raw
    
    # Check for header
    if ($content -notmatch "HashSmith") {
        return @{ IsValid = $false; Reason = "Missing HashSmith header" }
    }
    
    # Check for algorithm if specified
    if ($ExpectedAlgorithm -and $content -notmatch $ExpectedAlgorithm) {
        return @{ IsValid = $false; Reason = "Algorithm not found in header" }
    }
    
    # Check for source path if specified
    if ($ExpectedSourcePath -and $content -notmatch [regex]::Escape($ExpectedSourcePath)) {
        return @{ IsValid = $false; Reason = "Source path not found in header" }
    }
    
    # Check for valid entry format
    $lines = Get-Content $LogPath
    $entryPattern = '^.+\s*=\s*([a-f0-9]+|ERROR\(.+\)),\s*size:\s*\d+$'
    $validEntries = 0
    $invalidEntries = 0
    
    foreach ($line in $lines) {
        if ($line.StartsWith('#') -or [string]::IsNullOrWhiteSpace($line)) {
            continue  # Skip comments and empty lines
        }
        
        if ($line -match $entryPattern) {
            $validEntries++
        } else {
            $invalidEntries++
        }
    }
    
    return @{
        IsValid = $invalidEntries -eq 0
        Reason = if ($invalidEntries -gt 0) { "Found $invalidEntries invalid entries" } else { "Valid" }
        ValidEntries = $validEntries
        InvalidEntries = $invalidEntries
    }
}

<#
.SYNOPSIS
    Mock function for simulating file system errors
#>
function Invoke-MockFileSystemError {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ErrorType,
        
        [string]$FilePath = "MockPath"
    )
    
    switch ($ErrorType) {
        'FileNotFound' {
            throw [System.IO.FileNotFoundException]::new("File not found: $FilePath")
        }
        'AccessDenied' {
            throw [System.UnauthorizedAccessException]::new("Access denied: $FilePath")
        }
        'IOException' {
            throw [System.IO.IOException]::new("I/O error accessing: $FilePath")
        }
        'InvalidOperation' {
            throw [System.InvalidOperationException]::new("Invalid operation on: $FilePath")
        }
        default {
            throw [System.Exception]::new("Mock error: $ErrorType for $FilePath")
        }
    }
}

<#
.SYNOPSIS
    Compares two hashtables for equality (useful for configuration testing)
#>
function Compare-TestHashtables {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Reference,
        
        [Parameter(Mandatory)]
        [hashtable]$Difference,
        
        [string[]]$ExcludeKeys = @()
    )
    
    $differences = @()
    
    # Check keys in Reference that are missing or different in Difference
    foreach ($key in $Reference.Keys) {
        if ($key -in $ExcludeKeys) { continue }
        
        if (-not $Difference.ContainsKey($key)) {
            $differences += "Missing key: $key"
        } elseif ($Reference[$key] -ne $Difference[$key]) {
            $differences += "Key '$key': Expected '$($Reference[$key])', Got '$($Difference[$key])'"
        }
    }
    
    # Check for extra keys in Difference
    foreach ($key in $Difference.Keys) {
        if ($key -in $ExcludeKeys) { continue }
        
        if (-not $Reference.ContainsKey($key)) {
            $differences += "Extra key: $key"
        }
    }
    
    return @{
        AreEqual = $differences.Count -eq 0
        Differences = $differences
    }
}

<#
.SYNOPSIS
    Global cleanup registration for test artifacts
#>
if (-not (Get-Variable -Name "TestCleanupPaths" -Scope Global -ErrorAction SilentlyContinue)) {
    $Global:TestCleanupPaths = @()
}

<#
.SYNOPSIS
    Performs cleanup of test artifacts
#>
function Invoke-TestCleanup {
    [CmdletBinding()]
    param()
    
    if ($Global:TestCleanupPaths) {
        foreach ($path in $Global:TestCleanupPaths) {
            if (Test-Path $path) {
                try {
                    Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Verbose "Cleaned up test path: $path"
                } catch {
                    Write-Warning "Could not clean up test path: $path - $($_.Exception.Message)"
                }
            }
        }
        $Global:TestCleanupPaths = @()
    }
}

# Export functions for use in tests
Export-ModuleMember -Function @(
    'Initialize-TestData',
    'New-MockFileStructure',
    'Get-ExpectedTestHash',
    'New-TestConfiguration',
    'Test-HashFormat',
    'Measure-TestExecution',
    'New-TestDirectory',
    'Test-LogFileFormat',
    'Invoke-MockFileSystemError',
    'Compare-TestHashtables',
    'Invoke-TestCleanup'
)
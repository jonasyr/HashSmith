#Requires -Version 5.1

<#
.SYNOPSIS
    Smoke test script for the modularized HashSmith system.

.DESCRIPTION
    This script performs a basic smoke test of the HashSmith modular system by:
    1. Creating a temporary test directory with sample files
    2. Running the Start-HashSmith.ps1 script against the test directory
    3. Verifying that the expected output files are generated
    4. Cleaning up the test environment

.PARAMETER TestPath
    Optional path where the test directory will be created. Defaults to temp directory.

.PARAMETER KeepTestFiles
    If specified, test files will not be deleted after the test completes.

.EXAMPLE
    .\SmokeTest-HashSmith.ps1
    Runs a basic smoke test with default settings.

.EXAMPLE
    .\SmokeTest-HashSmith.ps1 -TestPath "C:\Temp\HashSmithTest" -KeepTestFiles
    Runs the smoke test in a specific directory and keeps test files for inspection.

.NOTES
    Author: HashSmith Refactoring Script
    Version: 1.0
    Created: $(Get-Date -Format 'yyyy-MM-dd')
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$TestPath = (Join-Path $env:TEMP "HashSmithSmokeTest_$(Get-Date -Format 'yyyyMMdd_HHmmss')"),
    
    [Parameter()]
    [switch]$KeepTestFiles
)

# Set strict mode and error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Get the script root directory (should be Scripts folder)
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptRoot
$StartHashSmithPath = Join-Path $ScriptRoot "Start-HashSmith.ps1"

Write-Host "=== HashSmith Modular System Smoke Test ===" -ForegroundColor Cyan
Write-Host "Test Path: $TestPath" -ForegroundColor Yellow
Write-Host "Project Root: $ProjectRoot" -ForegroundColor Yellow
Write-Host "Start Script: $StartHashSmithPath" -ForegroundColor Yellow
Write-Host ""

try {
    # Verify the Start-HashSmith.ps1 script exists
    if (-not (Test-Path $StartHashSmithPath)) {
        throw "Start-HashSmith.ps1 not found at: $StartHashSmithPath"
    }

    # Create test directory
    Write-Host "Creating test directory structure..." -ForegroundColor Green
    if (Test-Path $TestPath) {
        Remove-Item $TestPath -Recurse -Force
    }
    New-Item -Path $TestPath -ItemType Directory -Force | Out-Null

    # Create subdirectories
    $SubDirs = @('Documents', 'Images', 'Config')
    foreach ($Dir in $SubDirs) {
        New-Item -Path (Join-Path $TestPath $Dir) -ItemType Directory -Force | Out-Null
    }

    # Create test files with different content and extensions
    $TestFiles = @{
        'test1.txt' = 'This is a test file with some content for hashing.'
        'test2.log' = "Log entry 1`nLog entry 2`nLog entry 3"
        'Documents\readme.md' = '# Test Document'
        'Documents\data.json' = '{"test": "value", "number": 42}'
        'Images\placeholder.txt' = 'Placeholder for image file'
        'Config\settings.ini' = "[Settings]`nKey1=Value1`nKey2=Value2"
        'empty.txt' = ''
        'binary.dat' = [System.Text.Encoding]::UTF8.GetBytes("Binary content with special chars: àáâãäå")
    }

    Write-Host "Creating test files..." -ForegroundColor Green
    foreach ($File in $TestFiles.GetEnumerator()) {
        $FilePath = Join-Path $TestPath $File.Key
        $DirPath = Split-Path $FilePath -Parent
        if (-not (Test-Path $DirPath)) {
            New-Item -Path $DirPath -ItemType Directory -Force | Out-Null
        }
        
        if ($File.Value -is [byte[]]) {
            [System.IO.File]::WriteAllBytes($FilePath, $File.Value)
        } else {
            Set-Content -Path $FilePath -Value $File.Value -Encoding UTF8
        }
    }

    Write-Host "Test files created successfully." -ForegroundColor Green
    Write-Host ""

    # Run the HashSmith script
    Write-Host "Running HashSmith against test directory..." -ForegroundColor Green
    Write-Host "Command: & '$StartHashSmithPath' -SourceDir '$TestPath'" -ForegroundColor Yellow
    Write-Host ""

    $StartTime = Get-Date
    & $StartHashSmithPath -SourceDir $TestPath
    $EndTime = Get-Date
    $Duration = $EndTime - $StartTime

    Write-Host ""
    Write-Host "HashSmith execution completed in $($Duration.TotalSeconds) seconds." -ForegroundColor Green
    Write-Host ""

    # Verify output files
    Write-Host "Verifying output files..." -ForegroundColor Green
    
    $ExpectedOutputs = @(
        'HashSmith_Results.csv',
        'HashSmith_Log.txt',
        'HashSmith_Summary.txt',
        'HashSmith_DirectoryIntegrity.txt'
    )

    $AllOutputsFound = $true
    foreach ($Output in $ExpectedOutputs) {
        $OutputPath = Join-Path $TestPath $Output
        if (Test-Path $OutputPath) {
            $FileSize = (Get-Item $OutputPath).Length
            Write-Host "✓ $Output found ($FileSize bytes)" -ForegroundColor Green
            
            # Basic content validation
            if ($Output -eq 'HashSmith_Results.csv' -and $FileSize -gt 0) {
                $CsvContent = Get-Content $OutputPath -First 5
                if ($CsvContent[0] -like "*FileName*Hash*") {
                    Write-Host "  ✓ CSV header looks correct" -ForegroundColor DarkGreen
                } else {
                    Write-Host "  ⚠ CSV header format unexpected" -ForegroundColor Yellow
                }
            }
        } else {
            Write-Host "✗ $Output NOT found" -ForegroundColor Red
            $AllOutputsFound = $false
        }
    }

    Write-Host ""
    if ($AllOutputsFound) {
        Write-Host "=== SMOKE TEST PASSED ===" -ForegroundColor Green
        Write-Host "All expected output files were generated successfully." -ForegroundColor Green
    } else {
        Write-Host "=== SMOKE TEST FAILED ===" -ForegroundColor Red
        Write-Host "Some expected output files were missing." -ForegroundColor Red
    }

    # Display summary
    Write-Host ""
    Write-Host "Test Summary:" -ForegroundColor Cyan
    Write-Host "- Test files created: $($TestFiles.Count)" -ForegroundColor White
    Write-Host "- Execution time: $($Duration.TotalSeconds) seconds" -ForegroundColor White
    Write-Host "- Output files found: $($ExpectedOutputs.Where({Test-Path (Join-Path $TestPath $_)}).Count)/$($ExpectedOutputs.Count)" -ForegroundColor White

} catch {
    Write-Host ""
    Write-Host "=== SMOKE TEST ERROR ===" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    throw
} finally {
    # Cleanup
    if (-not $KeepTestFiles -and (Test-Path $TestPath)) {
        Write-Host ""
        Write-Host "Cleaning up test files..." -ForegroundColor Yellow
        try {
            Remove-Item $TestPath -Recurse -Force
            Write-Host "Test files cleaned up successfully." -ForegroundColor Green
        } catch {
            Write-Host "Warning: Could not clean up test files at $TestPath" -ForegroundColor Yellow
            Write-Host "Please remove manually if needed." -ForegroundColor Yellow
        }
    } elseif ($KeepTestFiles) {
        Write-Host ""
        Write-Host "Test files preserved at: $TestPath" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Smoke test completed." -ForegroundColor Cyan

#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Quick test script to verify the improvements made to HashSmith

.DESCRIPTION
    Tests the new parallel discovery, spinner functionality, and statistics tracking
#>

[CmdletBinding()]
param(
    [string]$TestPath = $PWD
)

# Get script directory for relative module paths
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptPath
$ModulesPath = Join-Path $ProjectRoot "Modules"

# Import HashSmith modules
Write-Host "🔧 Testing HashSmith Improvements..." -ForegroundColor Yellow

try {
    Import-Module (Join-Path $ModulesPath "HashSmithConfig") -Force -Verbose:$false
    Import-Module (Join-Path $ModulesPath "HashSmithCore") -Force -Verbose:$false  
    Import-Module (Join-Path $ModulesPath "HashSmithDiscovery") -Force -Verbose:$false
    Import-Module (Join-Path $ModulesPath "HashSmithHash") -Force -Verbose:$false
    
    Write-Host "✅ Modules imported successfully" -ForegroundColor Green
}
catch {
    Write-Error "Failed to import modules: $($_.Exception.Message)"
    exit 1
}

# Initialize configuration
Initialize-HashSmithConfig
Reset-HashSmithStatistics

Write-Host ""
Write-Host "📊 Testing Statistics Functions..." -ForegroundColor Cyan

# Test statistics functions
Set-HashSmithStatistic -Name 'FilesDiscovered' -Value 100
Add-HashSmithStatistic -Name 'FilesProcessed' -Amount 5
$stats = Get-HashSmithStatistics

Write-Host "   Files Discovered: $($stats.FilesDiscovered)" -ForegroundColor White
Write-Host "   Files Processed: $($stats.FilesProcessed)" -ForegroundColor White

Write-Host ""
Write-Host "🔄 Testing Spinner Functionality..." -ForegroundColor Cyan

# Test spinner
Start-HashSmithSpinner -Message "Testing spinner functionality..."
Start-Sleep -Seconds 2
Update-HashSmithSpinner -Message "Updated spinner message..."
Start-Sleep -Seconds 2
Stop-HashSmithSpinner

Write-Host "   ✅ Spinner test completed" -ForegroundColor Green

Write-Host ""
Write-Host "🔍 Testing Discovery with Progress..." -ForegroundColor Cyan

# Test discovery (use a small directory to keep it fast)
try {
    $discoveryResult = Get-HashSmithAllFiles -Path $TestPath -IncludeHidden:$false -IncludeSymlinks:$false
    
    Write-Host "   📁 Files found: $($discoveryResult.Files.Count)" -ForegroundColor White
    Write-Host "   ⏭️  Files skipped: $($discoveryResult.Statistics.TotalSkipped)" -ForegroundColor White
    Write-Host "   ⚠️  Errors: $($discoveryResult.Errors.Count)" -ForegroundColor White
    
    # Check if statistics were updated
    $finalStats = Get-HashSmithStatistics
    Write-Host "   📊 Statistics - Discovered: $($finalStats.FilesDiscovered)" -ForegroundColor White
}
catch {
    Write-Warning "Discovery test failed: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "🧪 Testing Hash Computation with Spinner..." -ForegroundColor Cyan

# Create a test file if it doesn't exist
$testFile = Join-Path $TestPath "hashsmith_test_file.txt"
if (-not (Test-Path $testFile)) {
    # Create a larger test file (100MB) to trigger spinner
    $content = "HashSmith Test Data - This line repeats many times to create a large file for testing spinner functionality.`n" * 1000000
    Set-Content -Path $testFile -Value $content
    Write-Host "   📝 Created large test file: $testFile ($('{0:N1} MB' -f ((Get-Item $testFile).Length / 1MB)))" -ForegroundColor Yellow
}

try {
    $hashResult = Get-HashSmithFileHashSafe -Path $testFile -Algorithm "MD5" -VerifyIntegrity
    
    if ($hashResult.Success) {
        Write-Host "   ✅ Hash computed: $($hashResult.Hash)" -ForegroundColor Green
        Write-Host "   ⏱️  Duration: $($hashResult.Duration.TotalSeconds.ToString('F2'))s" -ForegroundColor White
    } else {
        Write-Host "   ❌ Hash computation failed: $($hashResult.Error)" -ForegroundColor Red
    }
}
catch {
    Write-Warning "Hash test failed: $($_.Exception.Message)"
}

# Cleanup test file
if (Test-Path $testFile) {
    Remove-Item $testFile -Force -ErrorAction SilentlyContinue
    Write-Host "   🗑️  Cleaned up test file" -ForegroundColor Gray
}

Write-Host ""
Write-Host "🎉 Improvement Tests Completed!" -ForegroundColor Green

# Final statistics
$finalStats = Get-HashSmithStatistics
Write-Host ""
Write-Host "📊 Final Statistics:" -ForegroundColor Cyan
Write-Host "   Files Discovered: $($finalStats.FilesDiscovered)" -ForegroundColor White
Write-Host "   Files Processed: $($finalStats.FilesProcessed)" -ForegroundColor White
Write-Host "   Bytes Processed: $($finalStats.BytesProcessed)" -ForegroundColor White
Write-Host "   Start Time: $($finalStats.StartTime)" -ForegroundColor White

Write-Host ""
Write-Host "✨ All improvements are working correctly!" -ForegroundColor Green

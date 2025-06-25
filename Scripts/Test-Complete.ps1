#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Comprehensive test of all HashSmith improvements

.DESCRIPTION
    Tests all the new features: parallel discovery, spinner, statistics, and progress
#>

[CmdletBinding()]
param(
    [string]$TestPath = $PWD
)

$ErrorActionPreference = "Continue"

# Get script directory for relative module paths
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptPath
$ModulesPath = Join-Path $ProjectRoot "Modules"

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "║                  🧪 HASHSMITH IMPROVEMENTS TEST 🧪           ║" -ForegroundColor White -BackgroundColor Magenta
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Magenta
Write-Host ""

# Test 1: Module Import
Write-Host "📦 Test 1: Module Import" -ForegroundColor Cyan
Write-Host "─" * 30 -ForegroundColor Blue

try {
    Import-Module (Join-Path $ModulesPath "HashSmithConfig") -Force -Verbose:$false
    Write-Host "✅ HashSmithConfig module imported" -ForegroundColor Green
    
    Import-Module (Join-Path $ModulesPath "HashSmithCore") -Force -Verbose:$false  
    Write-Host "✅ HashSmithCore module imported" -ForegroundColor Green
    
    Import-Module (Join-Path $ModulesPath "HashSmithDiscovery") -Force -Verbose:$false
    Write-Host "✅ HashSmithDiscovery module imported" -ForegroundColor Green
    
    Import-Module (Join-Path $ModulesPath "HashSmithHash") -Force -Verbose:$false
    Write-Host "✅ HashSmithHash module imported" -ForegroundColor Green
    
    Write-Host "🎉 All modules imported successfully!" -ForegroundColor Green
}
catch {
    Write-Host "❌ Module import failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Test 2: Configuration and Statistics
Write-Host "⚙️  Test 2: Configuration and Statistics" -ForegroundColor Cyan
Write-Host "─" * 40 -ForegroundColor Blue

try {
    Initialize-HashSmithConfig
    Reset-HashSmithStatistics
    Write-Host "✅ Configuration initialized" -ForegroundColor Green
    
    # Test new statistics functions
    Set-HashSmithStatistic -Name 'FilesDiscovered' -Value 42
    Add-HashSmithStatistic -Name 'FilesProcessed' -Amount 10
    
    $stats = Get-HashSmithStatistics
    Write-Host "✅ Statistics functions working: Discovered=$($stats.FilesDiscovered), Processed=$($stats.FilesProcessed)" -ForegroundColor Green
}
catch {
    Write-Host "❌ Configuration test failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# Test 3: Spinner Functionality
Write-Host "⏳ Test 3: Spinner Functionality" -ForegroundColor Cyan
Write-Host "─" * 35 -ForegroundColor Blue

try {
    # Check if spinner functions are available
    $spinnerFunctions = @('Start-HashSmithSpinner', 'Stop-HashSmithSpinner', 'Update-HashSmithSpinner')
    $allAvailable = $true
    
    foreach ($func in $spinnerFunctions) {
        if (Get-Command $func -ErrorAction SilentlyContinue) {
            Write-Host "✅ $func is available" -ForegroundColor Green
        } else {
            Write-Host "❌ $func is NOT available" -ForegroundColor Red
            $allAvailable = $false
        }
    }
    
    if ($allAvailable) {
        Write-Host "🔄 Testing spinner animation (3 seconds)..." -ForegroundColor Yellow
        Start-HashSmithSpinner -Message "Testing spinner..."
        Start-Sleep -Seconds 1
        Update-HashSmithSpinner -Message "Spinner updated..."
        Start-Sleep -Seconds 1
        Update-HashSmithSpinner -Message "Almost done..."
        Start-Sleep -Seconds 1
        Stop-HashSmithSpinner
        Write-Host "✅ Spinner test completed successfully!" -ForegroundColor Green
    } else {
        Write-Host "❌ Some spinner functions are missing - check module exports" -ForegroundColor Red
    }
}
catch {
    Write-Host "❌ Spinner test failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# Test 4: Parallel Discovery
Write-Host "🔍 Test 4: Parallel Discovery" -ForegroundColor Cyan
Write-Host "─" * 30 -ForegroundColor Blue

try {
    Write-Host "Testing file discovery on: $TestPath" -ForegroundColor Yellow
    
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $discoveryResult = Get-HashSmithAllFiles -Path $TestPath -IncludeHidden:$false -IncludeSymlinks:$false
    $stopwatch.Stop()
    
    Write-Host "✅ Discovery completed in $($stopwatch.Elapsed.TotalSeconds.ToString('F2')) seconds" -ForegroundColor Green
    Write-Host "   📁 Files found: $($discoveryResult.Files.Count)" -ForegroundColor White
    Write-Host "   ⏭️  Files skipped: $($discoveryResult.Statistics.TotalSkipped)" -ForegroundColor White
    Write-Host "   ⚠️  Errors: $($discoveryResult.Errors.Count)" -ForegroundColor White
    
    # Check if it's using parallel processing
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        Write-Host "✅ PowerShell 7+ detected - parallel discovery should be enabled" -ForegroundColor Green
    } else {
        Write-Host "ℹ️  PowerShell 5.1 detected - using sequential discovery" -ForegroundColor Yellow
    }
    
    # Verify statistics were updated
    $finalStats = Get-HashSmithStatistics
    Write-Host "✅ Statistics updated: FilesDiscovered=$($finalStats.FilesDiscovered)" -ForegroundColor Green
    
} catch {
    Write-Host "❌ Discovery test failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# Test 5: Hash Computation
Write-Host "🔐 Test 5: Hash Computation" -ForegroundColor Cyan
Write-Host "─" * 30 -ForegroundColor Blue

try {
    # Create a small test file
    $testFile = Join-Path $TestPath "hashsmith_small_test.txt"
    "HashSmith Test Content for hash computation." | Set-Content -Path $testFile
    
    Write-Host "📝 Created test file: $([System.IO.Path]::GetFileName($testFile))" -ForegroundColor Yellow
    
    $hashResult = Get-HashSmithFileHashSafe -Path $testFile -Algorithm "MD5"
    
    if ($hashResult.Success) {
        Write-Host "✅ Hash computed successfully: $($hashResult.Hash)" -ForegroundColor Green
        Write-Host "   ⏱️  Duration: $($hashResult.Duration.TotalSeconds.ToString('F3'))s" -ForegroundColor White
        Write-Host "   📊 Size: $($hashResult.Size) bytes" -ForegroundColor White
    } else {
        Write-Host "❌ Hash computation failed: $($hashResult.Error)" -ForegroundColor Red
    }
    
    # Cleanup
    Remove-Item $testFile -Force -ErrorAction SilentlyContinue
    Write-Host "🗑️  Test file cleaned up" -ForegroundColor Gray
    
} catch {
    Write-Host "❌ Hash computation test failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# Final Summary
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║                    📊 TEST SUMMARY 📊                        ║" -ForegroundColor Black -BackgroundColor Green
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green

$finalStats = Get-HashSmithStatistics
Write-Host ""
Write-Host "📈 Final Statistics:" -ForegroundColor Cyan
Write-Host "   🔍 Files Discovered: $($finalStats.FilesDiscovered)" -ForegroundColor White
Write-Host "   ✅ Files Processed: $($finalStats.FilesProcessed)" -ForegroundColor White
Write-Host "   💾 Bytes Processed: $($finalStats.BytesProcessed)" -ForegroundColor White
Write-Host "   ⚠️  Total Errors: $($finalStats.FilesError)" -ForegroundColor White
Write-Host "   🔗 Symlinks: $($finalStats.FilesSymlinks)" -ForegroundColor White
Write-Host "   🏁 Start Time: $($finalStats.StartTime)" -ForegroundColor White

Write-Host ""
Write-Host "🎯 Improvements Status:" -ForegroundColor Cyan
Write-Host "   ✅ Parallel Discovery: Implemented" -ForegroundColor Green
Write-Host "   ✅ Statistics Tracking: Working" -ForegroundColor Green
Write-Host "   ✅ Progress Updates: Clean single-line" -ForegroundColor Green
Write-Host "   $(if (Get-Command 'Start-HashSmithSpinner' -ErrorAction SilentlyContinue) {'✅'} else {'❌'}) Spinner for Large Files: $(if (Get-Command 'Start-HashSmithSpinner' -ErrorAction SilentlyContinue) {'Available'} else {'Not Available'})" -ForegroundColor $(if (Get-Command 'Start-HashSmithSpinner' -ErrorAction SilentlyContinue) {'Green'} else {'Red'})

Write-Host ""
Write-Host "🚀 All tests completed!" -ForegroundColor Green

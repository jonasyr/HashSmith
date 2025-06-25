#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Quick test of the improved parallel processing with visible progress

.DESCRIPTION
    Tests a small subset of files to verify the spinner and progress improvements
#>

param(
    [string]$TestDir = $env:TEMP
)

# Get script directory for relative module paths
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptPath
$ModulesPath = Join-Path $ProjectRoot "Modules"

Write-Host "🚀 Testing HashSmith Parallel Processing Improvements..." -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Cyan

try {
    # Import modules in correct order
    $moduleOrder = @(
        'HashSmithLogging',
        'HashSmithConfig', 
        'HashSmithCore',
        'HashSmithDiscovery',
        'HashSmithHash',
        'HashSmithProcessor'
    )

    Write-Host "`n📦 Importing HashSmith modules..." -ForegroundColor Yellow
    foreach ($module in $moduleOrder) {
        $modulePath = Join-Path $ModulesPath $module "$module.psm1"
        if (Test-Path $modulePath) {
            Import-Module $modulePath -Force -Verbose:$false
        }
    }
    Write-Host "✅ All modules imported successfully" -ForegroundColor Green

    # Initialize configuration
    Write-Host "`n⚙️  Initializing configuration..." -ForegroundColor Yellow
    Initialize-HashSmithConfig
    
    # Set small test parameters to see the progress quickly
    Set-HashSmithConfig -Key 'TargetPath' -Value $TestDir
    Set-HashSmithConfig -Key 'Algorithm' -Value 'MD5'
    Set-HashSmithConfig -Key 'EnableParallelProcessing' -Value $true
    Set-HashSmithConfig -Key 'MaxParallelJobs' -Value 6
    Set-HashSmithConfig -Key 'ChunkSize' -Value 20  # Small chunks for testing
    
    Write-Host "✅ Configuration initialized" -ForegroundColor Green

    # Discover some files for testing
    Write-Host "`n🔍 Discovering files for testing..." -ForegroundColor Yellow
    $discoveryResult = Get-HashSmithAllFiles -Path $TestDir
    $allFiles = if ($discoveryResult.Files) { $discoveryResult.Files } else { @() }
    
    # Limit to first 50 files for quick testing
    $testFiles = $allFiles | Select-Object -First 50
    
    if ($testFiles.Count -eq 0) {
        Write-Host "❌ No files found for testing in $TestDir" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "✅ Found $($testFiles.Count) files for testing" -ForegroundColor Green

    # Create a temporary log file
    $logPath = Join-Path $PWD "test_processing.log"
    
    Write-Host "`n🔄 Starting parallel processing test..." -ForegroundColor Yellow
    Write-Host "You should see:" -ForegroundColor Cyan
    Write-Host "  • Spinner animation during chunk processing" -ForegroundColor Cyan  
    Write-Host "  • Live progress with completion percentage" -ForegroundColor Cyan
    Write-Host "  • Chunk completion messages with processing rate" -ForegroundColor Cyan
    Write-Host "  • Brief pauses between chunks" -ForegroundColor Cyan
    Write-Host ""
    
    # Start processing with our improvements
    $processingResult = Start-HashSmithFileProcessing -Files $testFiles -LogPath $logPath -Algorithm 'MD5' -BasePath $TestDir -UseParallel -ShowProgress
    
    Write-Host "`n✅ Processing completed!" -ForegroundColor Green
    Write-Host "   Processed $($processingResult.Count) files successfully" -ForegroundColor Gray
    
} catch {
    Write-Host "`n❌ Test failed!" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Stack Trace:" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
} finally {
    # Cleanup
    Write-Host "`n🧹 Cleaning up..." -ForegroundColor Gray
    if (Test-Path "test_processing.log") {
        Remove-Item "test_processing.log" -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "`n🎉 Test completed!" -ForegroundColor Green

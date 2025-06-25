#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Simple test to verify the working manual spinner

.DESCRIPTION
    Tests only the manual spinner that we know works
#>

# Get script directory for relative module paths
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptPath
$ModulesPath = Join-Path $ProjectRoot "Modules"

Write-Host "🔄 Testing Simple Spinner..." -ForegroundColor Yellow

try {
    Import-Module (Join-Path $ModulesPath "HashSmithCore") -Force -Verbose:$false
    Write-Host "✅ Module imported successfully" -ForegroundColor Green
}
catch {
    Write-Error "Failed to import module: $($_.Exception.Message)"
    exit 1
}

Write-Host ""
Write-Host "🎬 Demo: Manual Spinner (5 seconds)" -ForegroundColor Cyan
Write-Host "You should see spinning characters: ⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏" -ForegroundColor Yellow

Show-HashSmithSpinner -Message "Processing files, please wait..." -Seconds 5

Write-Host "✅ Spinner test completed!" -ForegroundColor Green

Write-Host ""
Write-Host "🧪 Testing Hash Function Integration..." -ForegroundColor Cyan

# Create a large test file to trigger the spinner
$testFile = Join-Path $PWD "large_test_file.txt"
try {
    # Create a 60MB file to trigger spinner
    $content = "HashSmith Test Data - Large file content.`n" * 2000000
    Set-Content -Path $testFile -Value $content
    $fileSize = (Get-Item $testFile).Length
    Write-Host "📝 Created test file: $('{0:N1} MB' -f ($fileSize / 1MB))" -ForegroundColor Yellow
    
    # Import hash module
    Import-Module (Join-Path $ModulesPath "HashSmithHash") -Force -Verbose:$false
    Import-Module (Join-Path $ModulesPath "HashSmithConfig") -Force -Verbose:$false
    Initialize-HashSmithConfig
    
    Write-Host "🔐 Computing hash (should show spinner)..." -ForegroundColor Yellow
    $hashResult = Get-HashSmithFileHashSafe -Path $testFile -Algorithm "MD5"
    
    if ($hashResult.Success) {
        Write-Host "✅ Hash computed: $($hashResult.Hash)" -ForegroundColor Green
        Write-Host "   ⏱️  Duration: $($hashResult.Duration.TotalSeconds.ToString('F2'))s" -ForegroundColor White
    } else {
        Write-Host "❌ Hash failed: $($hashResult.Error)" -ForegroundColor Red
    }
}
catch {
    Write-Host "❌ Test failed: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    # Cleanup
    if (Test-Path $testFile) {
        Remove-Item $testFile -Force -ErrorAction SilentlyContinue
        Write-Host "🗑️  Test file cleaned up" -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "🎉 All tests completed!" -ForegroundColor Green

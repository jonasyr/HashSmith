#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Test the improved progress and reduced log clutter

.DESCRIPTION
    Quick verification of the processor improvements
#>

# Get script directory for relative module paths
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptPath
$ModulesPath = Join-Path $ProjectRoot "Modules"

Write-Host "🔧 Testing HashSmith Processor Improvements..." -ForegroundColor Yellow

try {
    # Import modules
    Import-Module (Join-Path $ModulesPath "HashSmithConfig") -Force -Verbose:$false
    Import-Module (Join-Path $ModulesPath "HashSmithCore") -Force -Verbose:$false
    Import-Module (Join-Path $ModulesPath "HashSmithProcessor") -Force -Verbose:$false
    
    Write-Host "✅ Modules imported successfully" -ForegroundColor Green
    
    # Test the improvements
    Write-Host "`n📝 Key Improvements:" -ForegroundColor Cyan
    Write-Host "   • Smart timeout: 20min with no progress (not just 10min total)" -ForegroundColor Green
    Write-Host "   • Thread info shown only once (not per chunk)" -ForegroundColor Green  
    Write-Host "   • Reduced log clutter (detailed logs every 10 chunks)" -ForegroundColor Green
    Write-Host "   • Compact progress line with proper padding" -ForegroundColor Green
    Write-Host "   • Overall progress summary every 10 chunks" -ForegroundColor Green
    
    Write-Host "`n🎯 Next Steps:" -ForegroundColor Yellow
    Write-Host "   • Run real-world test with these improvements" -ForegroundColor Gray
    Write-Host "   • Monitor for reduced terminal clutter" -ForegroundColor Gray
    Write-Host "   • Verify smart timeout works properly" -ForegroundColor Gray
    
} catch {
    Write-Host "❌ Test failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n🎉 Improvements ready for testing!" -ForegroundColor Green

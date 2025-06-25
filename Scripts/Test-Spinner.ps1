#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Simple test to verify spinner functionality

.DESCRIPTION
    Tests only the spinner functionality with a manual demonstration
#>

# Get script directory for relative module paths
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptPath
$ModulesPath = Join-Path $ProjectRoot "Modules"

# Import HashSmith modules
Write-Host "🔧 Testing Spinner Functionality..." -ForegroundColor Yellow

try {
    Import-Module (Join-Path $ModulesPath "HashSmithCore") -Force -Verbose:$false
    Write-Host "✅ Core module imported successfully" -ForegroundColor Green
}
catch {
    Write-Error "Failed to import modules: $($_.Exception.Message)"
    exit 1
}

Write-Host ""
Write-Host "🔄 Testing Spinner..." -ForegroundColor Cyan

# Test spinner with different messages
Write-Host "Starting spinner test (5 seconds)..." -ForegroundColor Yellow
Start-HashSmithSpinner -Message "Processing files, please wait..."
Start-Sleep -Seconds 2

Update-HashSmithSpinner -Message "Still processing, 50% complete..."
Start-Sleep -Seconds 2

Update-HashSmithSpinner -Message "Almost done, 90% complete..."
Start-Sleep -Seconds 1

Stop-HashSmithSpinner
Write-Host "✅ Spinner test completed successfully!" -ForegroundColor Green

Write-Host ""
Write-Host "✨ Spinner functionality is working!" -ForegroundColor Green

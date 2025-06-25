#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Visual test of the spinner functionality

.DESCRIPTION
    Shows different types of spinners to verify they work
#>

# Get script directory for relative module paths
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptPath
$ModulesPath = Join-Path $ProjectRoot "Modules"

Write-Host "🔄 Testing Spinner Visibility..." -ForegroundColor Yellow

try {
    Import-Module (Join-Path $ModulesPath "HashSmithCore") -Force -Verbose:$false
    Write-Host "✅ Module imported successfully" -ForegroundColor Green
}
catch {
    Write-Error "Failed to import module: $($_.Exception.Message)"
    exit 1
}

Write-Host ""
Write-Host "📺 Demo 1: Simple Spinner (5 seconds)" -ForegroundColor Cyan
Write-Host "Watch for the spinning animation..." -ForegroundColor Yellow

Show-HashSmithSpinnerDemo -Message "Loading files, please wait..." -Seconds 5

Write-Host "✅ Demo 1 completed!" -ForegroundColor Green

Write-Host ""
Write-Host "📺 Demo 2: Timer-based Spinner (3 seconds)" -ForegroundColor Cyan
Write-Host "Testing the timer-based spinner..." -ForegroundColor Yellow

try {
    Start-HashSmithSpinner -Message "Processing data..."
    Start-Sleep -Seconds 1
    
    Update-HashSmithSpinner -Message "Still processing..."
    Start-Sleep -Seconds 1
    
    Update-HashSmithSpinner -Message "Almost done..."
    Start-Sleep -Seconds 1
    
    Stop-HashSmithSpinner
    Write-Host "✅ Demo 2 completed!" -ForegroundColor Green
}
catch {
    Write-Host "❌ Timer-based spinner failed: $($_.Exception.Message)" -ForegroundColor Red
    Stop-HashSmithSpinner
}

Write-Host ""
Write-Host "📺 Demo 3: Manual Animation (shows you exactly what you should see)" -ForegroundColor Cyan

$chars = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
$message = "Manual spinner test - you should see rotating chars"

Write-Host "Starting manual animation..." -ForegroundColor Yellow

for ($i = 0; $i -lt 30; $i++) {
    $char = $chars[$i % $chars.Length]
    Write-Host "`r$char $message" -NoNewline -ForegroundColor Yellow
    Start-Sleep -Milliseconds 150
}

Write-Host "`r$(' ' * 80)`r" -NoNewline  # Clear line
Write-Host "✅ Demo 3 completed!" -ForegroundColor Green

Write-Host ""
Write-Host "🎉 All spinner tests completed!" -ForegroundColor Green
Write-Host ""
Write-Host "If you saw rotating characters (⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏) then the spinner is working!" -ForegroundColor Cyan

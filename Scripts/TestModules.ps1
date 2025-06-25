#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$TestDir = $env:TEMP
)

Write-Host "=== HashSmith Module Test ===" -ForegroundColor Cyan

# Get the script root and modules path
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptRoot
$ModulesPath = Join-Path $ProjectRoot "Modules"

Write-Host "Project Root: $ProjectRoot" -ForegroundColor Yellow
Write-Host "Modules Path: $ModulesPath" -ForegroundColor Yellow

try {
    Write-Host "Importing modules..." -ForegroundColor Green
    
    Import-Module (Join-Path $ModulesPath "HashSmithConfig") -Force
    Write-Host "✓ HashSmithConfig imported" -ForegroundColor Green
    
    Import-Module (Join-Path $ModulesPath "HashSmithCore") -Force
    Write-Host "✓ HashSmithCore imported" -ForegroundColor Green
    
    Import-Module (Join-Path $ModulesPath "HashSmithLogging") -Force
    Write-Host "✓ HashSmithLogging imported" -ForegroundColor Green
    
    Import-Module (Join-Path $ModulesPath "HashSmithDiscovery") -Force
    Write-Host "✓ HashSmithDiscovery imported" -ForegroundColor Green
    
    # Test basic functions
    Write-Host ""
    Write-Host "Testing functions..." -ForegroundColor Green
    
    # Initialize config
    Initialize-HashSmithConfig
    Write-Host "✓ Config initialized" -ForegroundColor Green
    
    # Test statistics
    $stats = Get-HashSmithStatistics
    Write-Host "✓ Statistics retrieved" -ForegroundColor Green
    
    # Test file discovery on a small directory
    if (Test-Path $TestDir) {
        Write-Host "Testing file discovery on: $TestDir" -ForegroundColor Yellow
        $result = Get-HashSmithAllFiles -Path $TestDir
        Write-Host "✓ File discovery completed - Found $($result.Files.Count) files" -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "=== ALL TESTS PASSED ===" -ForegroundColor Green
    
} catch {
    Write-Host ""
    Write-Host "=== TEST FAILED ===" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Stack Trace: $($_.ScriptStackTrace)" -ForegroundColor Red
    exit 1
}

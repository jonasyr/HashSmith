#Requires -Version 5.1

Write-Host "=== Quick HashSmith Test ===" -ForegroundColor Cyan

try {
    # Create a small test directory
    $TestPath = Join-Path $env:TEMP "QuickHashTest"
    if (Test-Path $TestPath) { Remove-Item $TestPath -Recurse -Force }
    New-Item -Path $TestPath -ItemType Directory -Force | Out-Null
    "Test content" | Out-File -FilePath (Join-Path $TestPath "test.txt") -Encoding UTF8
    
    Write-Host "Test directory created: $TestPath" -ForegroundColor Green
    
    # Try to run Start-HashSmith
    $StartScript = ".\Scripts\Start-HashSmith.ps1"
    Write-Host "Running: $StartScript -SourceDir $TestPath" -ForegroundColor Yellow
    
    & $StartScript -SourceDir $TestPath
    
    Write-Host "=== SUCCESS ===" -ForegroundColor Green
    
} catch {
    Write-Host "=== ERROR ===" -ForegroundColor Red
    Write-Host "Exception Type: $($_.Exception.GetType().Name)" -ForegroundColor Red
    Write-Host "Message: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Line: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
    Write-Host "Position: $($_.InvocationInfo.PositionMessage)" -ForegroundColor Red
    
    if ($_.ScriptStackTrace) {
        Write-Host "Stack Trace:" -ForegroundColor Red
        Write-Host $_.ScriptStackTrace -ForegroundColor Red
    }
} finally {
    # Cleanup
    if (Test-Path $TestPath) {
        Remove-Item $TestPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Test parallel vs sequential processing
param([string]$TestPath = "C:\Users\JW\AppData\Local\Temp\HashSmithParallelTest")

# Clean up and create test directory
if (Test-Path $TestPath) { Remove-Item $TestPath -Recurse -Force }
New-Item $TestPath -ItemType Directory | Out-Null
"test content" | Out-File (Join-Path $TestPath "test.txt")

Write-Host "Testing parallel vs sequential processing..." -ForegroundColor Yellow

# Test with UseParallel = $false (sequential)
Write-Host "`nTesting SEQUENTIAL processing:" -ForegroundColor Cyan
& ".\Scripts\Start-HashSmith.ps1" -SourceDir $TestPath -MaxThreads 1

# Clean up
Remove-Item $TestPath -Recurse -Force -ErrorAction SilentlyContinue

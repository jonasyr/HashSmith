# Debug script to troubleshoot HashSmith issues
param(
    [string]$TestPath = "C:\Users\JW\AppData\Local\Temp\HashSmithDebug"
)

# Clean up any existing test directory
if (Test-Path $TestPath) {
    Remove-Item $TestPath -Recurse -Force
}

# Create test directory and files
New-Item -Path $TestPath -ItemType Directory -Force | Out-Null
"Test content 1" | Out-File -FilePath (Join-Path $TestPath "test1.txt") -Encoding UTF8
"Test content 2" | Out-File -FilePath (Join-Path $TestPath "test2.txt") -Encoding UTF8

Write-Host "Created test files in: $TestPath" -ForegroundColor Green
Get-ChildItem $TestPath | Format-Table Name, Length, LastWriteTime

# Import modules manually to test
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptPath
$ModulesPath = Join-Path $ProjectRoot "Modules"

try {
    Write-Host "Importing modules..." -ForegroundColor Yellow
    Import-Module (Join-Path $ModulesPath "HashSmithConfig") -Force -Verbose
    Import-Module (Join-Path $ModulesPath "HashSmithCore") -Force -Verbose
    Import-Module (Join-Path $ModulesPath "HashSmithHash") -Force -Verbose
    
    Write-Host "Testing hash function..." -ForegroundColor Yellow
    $testFile = Join-Path $TestPath "test1.txt"
    $result = Get-HashSmithFileHashSafe -Path $testFile -Algorithm "MD5" -RetryCount 1 -TimeoutSeconds 10
    
    Write-Host "Result:" -ForegroundColor Green
    $result | Format-List
    
} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
}

# Clean up
Remove-Item $TestPath -Recurse -Force -ErrorAction SilentlyContinue

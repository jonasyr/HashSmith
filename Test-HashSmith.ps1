# Save as Test-HashSmith.ps1
param(
    [string]$ScriptPath = ".\HashSmith.ps1",
    [string]$TestRoot = "C:\MD5Testing"
)

$results = @()

# Setup test environment
Write-Host "Setting up test environment..." -ForegroundColor Cyan

# Create test directories
$testDirs = @(
    "$TestRoot\Normal",
    "$TestRoot\LongPaths",
    "$TestRoot\Unicode",
    "$TestRoot\Locked"
)

foreach ($dir in $testDirs) {
    if (-not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
        Write-Host "Created: $dir" -ForegroundColor Gray
    }
}

# Create sample files
$sampleFiles = @{
    "$TestRoot\Normal\test1.txt" = "Sample content for testing MD5 generation."
    "$TestRoot\Normal\test2.dat" = "Binary-like content with special chars: àáâãäå çèéêë"
    "$TestRoot\Normal\subfolder\nested.txt" = "Nested file content for recursive testing."
    "$TestRoot\Unicode\файл.txt" = "Unicode filename content (Cyrillic)"
    "$TestRoot\Unicode\测试.txt" = "Unicode filename content (Chinese)"
    "$TestRoot\LongPaths\$(('a' * 200)).txt" = "Long filename test content"
}

foreach ($file in $sampleFiles.Keys) {
    $dir = Split-Path $file -Parent
    if (-not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
    Set-Content -Path $file -Value $sampleFiles[$file] -Encoding UTF8
    Write-Host "Created: $(Split-Path $file -Leaf)" -ForegroundColor Gray
}

# Create a locked file for error testing (best effort)
try {
    $lockedFile = "$TestRoot\Locked\locked.txt"
    Set-Content -Path $lockedFile -Value "This file will be locked for testing"
    # Note: Actual file locking would require a separate process
    Write-Host "Created locked file test structure" -ForegroundColor Gray
}
catch {
    Write-Host "Warning: Could not create locked file scenario" -ForegroundColor Yellow
}

Write-Host "Test environment ready!`n" -ForegroundColor Green

# Test function
function Test-Scenario {
    param($Name, $ScriptBlock)
    
    try {
        $result = & $ScriptBlock
        $script:results += [PSCustomObject]@{
            Test = $Name
            Status = "PASS"
            Message = $result
        }
        Write-Host "✓ $Name" -ForegroundColor Green
    }
    catch {
        $script:results += [PSCustomObject]@{
            Test = $Name
            Status = "FAIL"
            Message = $_.Exception.Message
        }
        Write-Host ("✗ {0}: {1}" -f $Name, $_.Exception.Message) -ForegroundColor Red
    }
}

# Run all tests
Test-Scenario "Basic Execution" {
    & $ScriptPath -SourceDir $TestRoot -WhatIf
    "WhatIf mode executed successfully"
}

Test-Scenario "MD5 Generation" {
    & $ScriptPath -SourceDir "$TestRoot\Normal"
    if (Test-Path "$TestRoot\Normal\*.log") { "Log created" } else { throw "No log file" }
}

Test-Scenario "SHA256 Algorithm" {
    & $ScriptPath -SourceDir "$TestRoot\Normal" -HashAlgorithm SHA256
}

Test-Scenario "Resume Function" {
    & $ScriptPath -SourceDir "$TestRoot\Normal" -Resume
}

Test-Scenario "Long Path Support" {
    & $ScriptPath -SourceDir "$TestRoot\LongPaths"
}

Test-Scenario "Unicode Support" {
    & $ScriptPath -SourceDir "$TestRoot\Unicode"
}

Test-Scenario "Error Handling" {
    & $ScriptPath -SourceDir "$TestRoot\Locked"
}

Test-Scenario "JSON Output" {
    & $ScriptPath -SourceDir "$TestRoot\Normal" -UseJsonLog
    if (Test-Path "$TestRoot\Normal\*.json") { "JSON created" } else { throw "No JSON file" }
}

# Summary
$results | Format-Table -AutoSize
$passCount = ($results | Where-Object Status -eq "PASS").Count
$failCount = ($results | Where-Object Status -eq "FAIL").Count

Write-Host "`nTest Summary: $passCount passed, $failCount failed" -ForegroundColor $(if($failCount -eq 0){'Green'}else{'Red'})
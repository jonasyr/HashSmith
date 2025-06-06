# Production MD5 Script Testing Guide

## Test Environment Setup

### Prerequisites
- PowerShell 7+ (for parallel testing)
- PowerShell 5.1 (for compatibility testing)
- Test directories with various file types
- Administrative privileges (for some tests)

### Test Data Preparation

```powershell
# Create test directory structure
$testRoot = "C:\MD5Testing"
New-Item -Path $testRoot -ItemType Directory -Force

# Create subdirectories
@('Normal', 'LongPaths', 'Unicode', 'Large', 'Locked', 'Special') | ForEach-Object {
    New-Item -Path "$testRoot\$_" -ItemType Directory -Force
}
```

## Test Scenarios

### 1. Basic Functionality Tests

```powershell
# Test 1.1: Simple directory processing
.\MD5-Checksum.ps1 -SourceDir "$testRoot\Normal" -WhatIf
.\MD5-Checksum.ps1 -SourceDir "$testRoot\Normal"

# Test 1.2: Custom log file location
.\MD5-Checksum.ps1 -SourceDir "$testRoot\Normal" -LogFile "C:\Logs\test.log"

# Test 1.3: Different hash algorithms
.\MD5-Checksum.ps1 -SourceDir "$testRoot\Normal" -HashAlgorithm SHA256
.\MD5-Checksum.ps1 -SourceDir "$testRoot\Normal" -HashAlgorithm SHA512
```

### 2. Edge Case Testing

#### 2.1 Long Path Testing
```powershell
# Create paths >260 characters
$longPath = "$testRoot\LongPaths"
$deepPath = $longPath
for ($i = 1; $i -le 20; $i++) {
    $deepPath = Join-Path $deepPath "VeryLongFolderName$i"
}
New-Item -Path $deepPath -ItemType Directory -Force
"Test content" | Out-File "$deepPath\testfile.txt"

# Test long paths
.\MD5-Checksum.ps1 -SourceDir "$testRoot\LongPaths"
```

#### 2.2 Unicode and Special Characters
```powershell
# Create files with Unicode names
$unicodePath = "$testRoot\Unicode"
@(
    "测试文件.txt",
    "тест.dat",
    "ファイル.log",
    "file with spaces.txt",
    "file'with'quotes.txt",
    "file`$with`$special.txt"
) | ForEach-Object {
    "Content" | Out-File "$unicodePath\$_" -Encoding UTF8
}

# Test Unicode handling
.\MD5-Checksum.ps1 -SourceDir "$testRoot\Unicode"
```

#### 2.3 Large File Testing
```powershell
# Create large files
$largePath = "$testRoot\Large"

# 1GB file
$bytes = New-Object byte[] (1GB)
[System.IO.File]::WriteAllBytes("$largePath\1GB.bin", $bytes)

# Many small files
1..10000 | ForEach-Object {
    "Small file $_" | Out-File "$largePath\small_$_.txt"
}

# Test performance
Measure-Command {
    .\MD5-Checksum.ps1 -SourceDir "$testRoot\Large" -MaxThreads 16
}
```

### 3. Error Handling Tests

#### 3.1 Locked File Testing
```powershell
# Create and lock a file
$lockedFile = "$testRoot\Locked\locked.txt"
"Locked content" | Out-File $lockedFile
$fileStream = [System.IO.File]::Open($lockedFile, 'Open', 'Read', 'None')

# Test with locked file (should handle gracefully)
.\MD5-Checksum.ps1 -SourceDir "$testRoot\Locked"

# Clean up
$fileStream.Close()
```

#### 3.2 Permission Testing
```powershell
# Create read-only file
$readOnlyFile = "$testRoot\Special\readonly.txt"
"Read only" | Out-File $readOnlyFile
Set-ItemProperty $readOnlyFile -Name IsReadOnly -Value $true

# Create no-access file (requires admin)
$noAccessFile = "$testRoot\Special\noaccess.txt"
"No access" | Out-File $noAccessFile
$acl = Get-Acl $noAccessFile
$acl.SetAccessRuleProtection($true, $false)
$acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) }
Set-Acl $noAccessFile $acl

# Test error handling
.\MD5-Checksum.ps1 -SourceDir "$testRoot\Special"
```

### 4. Resume and FixErrors Testing

#### 4.1 Resume Testing
```powershell
# Start processing and interrupt
$job = Start-Job {
    .\MD5-Checksum.ps1 -SourceDir "C:\LargeDirectory"
}
Start-Sleep -Seconds 10
Stop-Job $job

# Resume processing
.\MD5-Checksum.ps1 -SourceDir "C:\LargeDirectory" -Resume
```

#### 4.2 FixErrors Testing
```powershell
# Create scenario with errors
$errorPath = "$testRoot\Errors"
1..5 | ForEach-Object {
    "Content $_" | Out-File "$errorPath\file$_.txt"
}

# First run with locked file
$locked = [System.IO.File]::Open("$errorPath\file3.txt", 'Open', 'Read', 'None')
.\MD5-Checksum.ps1 -SourceDir $errorPath
$locked.Close()

# Fix errors
.\MD5-Checksum.ps1 -SourceDir $errorPath -FixErrors
```

### 5. Concurrency Testing

```powershell
# Test multiple instances
$sourceDir = "$testRoot\Normal"

# Start multiple instances
1..3 | ForEach-Object {
    Start-Job {
        param($num)
        .\MD5-Checksum.ps1 -SourceDir $using:sourceDir -LogFile "$using:sourceDir\log_$num.log"
    } -ArgumentList $_
}

# Wait and check for conflicts
Get-Job | Wait-Job
Get-Job | Receive-Job
```

### 6. Performance Benchmarking

```powershell
# Compare thread counts
@(1, 2, 4, 8, 16, 32) | ForEach-Object {
    $threads = $_
    $time = Measure-Command {
        .\MD5-Checksum.ps1 -SourceDir "$testRoot\Large" -MaxThreads $threads
    }
    
    [PSCustomObject]@{
        Threads = $threads
        TotalSeconds = $time.TotalSeconds
        FilesPerSecond = (Get-ChildItem "$testRoot\Large" -File).Count / $time.TotalSeconds
    }
}
```

### 7. Stress Testing

#### 7.1 Memory Stress Test
```powershell
# Create directory with millions of files
$stressPath = "$testRoot\Stress"
1..1000000 | ForEach-Object -Parallel {
    "x" | Out-File "$using:stressPath\f$_.txt"
} -ThrottleLimit 50

# Monitor memory usage
$before = (Get-Process -Id $PID).WorkingSet64
.\MD5-Checksum.ps1 -SourceDir $stressPath
$after = (Get-Process -Id $PID).WorkingSet64
"Memory increase: $(($after - $before) / 1MB) MB"
```

#### 7.2 Network Path Testing
```powershell
# Test with network share
.\MD5-Checksum.ps1 -SourceDir "\\server\share\folder"

# Test with disconnection simulation
# (Manually disconnect network during processing)
```

### 8. Validation Testing

#### 8.1 Hash Verification
```powershell
# Generate hashes
.\MD5-Checksum.ps1 -SourceDir "$testRoot\Normal" -LogFile "test1.log"

# Verify manually
Get-ChildItem "$testRoot\Normal" -File | ForEach-Object {
    $hash = (Get-FileHash $_.FullName -Algorithm MD5).Hash.ToLower()
    $logEntry = Get-Content "test1.log" | Where-Object { $_ -match [regex]::Escape($_.FullName) }
    
    if ($logEntry -match "=\s*([a-f0-9]{32})") {
        if ($matches[1] -eq $hash) {
            "OK: $($_.Name)"
        } else {
            "MISMATCH: $($_.Name)"
        }
    }
}
```

#### 8.2 JSON Log Validation
```powershell
# Generate with JSON
.\MD5-Checksum.ps1 -SourceDir "$testRoot\Normal" -UseJsonLog

# Validate JSON
$json = Get-Content "*.json" | ConvertFrom-Json
$json.Files | ForEach-Object {
    if (Test-Path $_.Path) {
        $actualHash = (Get-FileHash $_.Path -Algorithm MD5).Hash.ToLower()
        if ($_.Hash -ne $actualHash) {
            "Hash mismatch: $($_.Path)"
        }
    }
}
```

## Expected Results

### Success Criteria
1. All files processed without crashes
2. Error files logged appropriately
3. Resume works correctly
4. FixErrors updates only failed entries
5. No log corruption
6. Performance scales with thread count
7. Memory usage remains stable
8. Unicode paths handled correctly
9. Long paths processed successfully
10. Concurrent instances don't conflict

### Performance Baselines
- Small files (<1MB): >1000 files/second
- Medium files (1-100MB): >100 files/second  
- Large files (>1GB): Limited by disk I/O
- Parallel speedup: Near-linear up to CPU count

## Automated Test Suite

```powershell
# Save as Test-MD5Script.ps1
param(
    [string]$ScriptPath = ".\MD5-Checksum.ps1",
    [string]$TestRoot = "C:\MD5Testing"
)

$results = @()

# Test function
function Test-Scenario {
    param($Name, $ScriptBlock)
    
    try {
        $result = & $ScriptBlock
        $results += [PSCustomObject]@{
            Test = $Name
            Status = "PASS"
            Message = $result
        }
        Write-Host "✓ $Name" -ForegroundColor Green
    }
    catch {
        $results += [PSCustomObject]@{
            Test = $Name
            Status = "FAIL"
            Message = $_.Exception.Message
        }
        Write-Host "✗ $Name: $_" -ForegroundColor Red
    }
}

# Run all tests
Test-Scenario "Basic Execution" {
    & $ScriptPath -SourceDir $TestRoot -WhatIf
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
```

## Production Deployment Checklist

- [ ] All automated tests pass
- [ ] Performance meets requirements
- [ ] Error handling verified
- [ ] Logging format validated
- [ ] Resume/FixErrors tested
- [ ] Security review completed
- [ ] Documentation updated
- [ ] Rollback plan prepared
- [ ] Monitoring configured
- [ ] Support team trained
<#
.SYNOPSIS
    Validates the HashSmith test environment and dependencies

.DESCRIPTION
    Comprehensive validation script that checks all prerequisites, dependencies,
    and environment setup required for running the HashSmith test suite.

.PARAMETER Fix
    Attempt to fix common issues automatically

.PARAMETER Detailed
    Show detailed validation output

.PARAMETER SkipPerformance
    Skip performance-related validations

.EXAMPLE
    .\Validate-TestEnvironment.ps1 -Detailed

.EXAMPLE
    .\Validate-TestEnvironment.ps1 -Fix -Detailed
#>

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$Fix,
    
    [Parameter()]
    [switch]$Detailed,
    
    [Parameter()]
    [switch]$SkipPerformance
)

# Initialize validation results
$ValidationResults = @{
    PowerShell = @{ Status = 'Unknown'; Details = @(); Issues = @() }
    Pester = @{ Status = 'Unknown'; Details = @(); Issues = @() }
    Modules = @{ Status = 'Unknown'; Details = @(); Issues = @() }
    TestData = @{ Status = 'Unknown'; Details = @(); Issues = @() }
    Permissions = @{ Status = 'Unknown'; Details = @(); Issues = @() }
    Performance = @{ Status = 'Unknown'; Details = @(); Issues = @() }
    Overall = @{ Status = 'Unknown'; Details = @(); Issues = @() }
}

function Write-ValidationResult {
    [CmdletBinding()]
    param(
        [string]$Category,
        [ValidateSet('Pass', 'Fail', 'Warning', 'Info')]
        [string]$Status,
        [string]$Message,
        [string]$Details = $null
    )
    
    $color = switch ($Status) {
        'Pass' { 'Green' }
        'Fail' { 'Red' }
        'Warning' { 'Yellow' }
        'Info' { 'Cyan' }
    }
    
    $icon = switch ($Status) {
        'Pass' { '✅' }
        'Fail' { '❌' }
        'Warning' { '⚠️ ' }
        'Info' { 'ℹ️ ' }
    }
    
    Write-Host "$icon [$Category] $Message" -ForegroundColor $color
    
    if ($Details -and $Detailed) {
        Write-Host "   $Details" -ForegroundColor Gray
    }
    
    # Store result
    $ValidationResults[$Category].Details += $Message
    if ($Status -eq 'Fail') {
        $ValidationResults[$Category].Issues += $Message
        $ValidationResults[$Category].Status = 'Fail'
    } elseif ($Status -eq 'Warning' -and $ValidationResults[$Category].Status -ne 'Fail') {
        $ValidationResults[$Category].Status = 'Warning'
    } elseif ($Status -eq 'Pass' -and $ValidationResults[$Category].Status -eq 'Unknown') {
        $ValidationResults[$Category].Status = 'Pass'
    }
}

function Test-PowerShellEnvironment {
    Write-Host ""
    Write-Host "🔍 Validating PowerShell Environment" -ForegroundColor Cyan
    Write-Host "=" * 50
    
    # PowerShell version
    $psVersion = $PSVersionTable.PSVersion
    if ($psVersion.Major -ge 7) {
        Write-ValidationResult -Category 'PowerShell' -Status 'Pass' -Message "PowerShell version: $psVersion (Excellent)" -Details "PowerShell 7+ provides optimal performance and features"
    } elseif ($psVersion.Major -eq 5 -and $psVersion.Minor -ge 1) {
        Write-ValidationResult -Category 'PowerShell' -Status 'Pass' -Message "PowerShell version: $psVersion (Compatible)" -Details "PowerShell 5.1+ is supported but 7+ recommended"
    } else {
        Write-ValidationResult -Category 'PowerShell' -Status 'Fail' -Message "PowerShell version: $psVersion (Unsupported)" -Details "Requires PowerShell 5.1 or higher"
    }
    
    # Execution policy
    $executionPolicy = Get-ExecutionPolicy
    if ($executionPolicy -in @('RemoteSigned', 'Unrestricted', 'Bypass')) {
        Write-ValidationResult -Category 'PowerShell' -Status 'Pass' -Message "Execution policy: $executionPolicy" -Details "Allows script execution"
    } else {
        Write-ValidationResult -Category 'PowerShell' -Status 'Warning' -Message "Execution policy: $executionPolicy" -Details "May prevent script execution"
        
        if ($Fix) {
            try {
                Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
                Write-ValidationResult -Category 'PowerShell' -Status 'Pass' -Message "Fixed execution policy to RemoteSigned"
            } catch {
                Write-ValidationResult -Category 'PowerShell' -Status 'Fail' -Message "Failed to fix execution policy: $($_.Exception.Message)"
            }
        }
    }
    
    # Module paths
    $modulePathCount = $env:PSModulePath.Split([IO.Path]::PathSeparator).Count
    Write-ValidationResult -Category 'PowerShell' -Status 'Info' -Message "Module paths configured: $modulePathCount" -Details $env:PSModulePath
    
    # Current location
    $currentLocation = Get-Location
    Write-ValidationResult -Category 'PowerShell' -Status 'Info' -Message "Current location: $currentLocation"
}

function Test-PesterModule {
    Write-Host ""
    Write-Host "🧪 Validating Pester Module" -ForegroundColor Cyan
    Write-Host "=" * 50
    
    # Check if Pester is installed
    $pesterModules = Get-Module Pester -ListAvailable | Sort-Object Version -Descending
    
    if (-not $pesterModules) {
        Write-ValidationResult -Category 'Pester' -Status 'Fail' -Message "Pester module not found"
        
        if ($Fix) {
            try {
                Write-Host "Installing Pester module..." -ForegroundColor Yellow
                Install-Module -Name Pester -Force -SkipPublisherCheck -Scope CurrentUser
                $pesterModules = Get-Module Pester -ListAvailable | Sort-Object Version -Descending
                Write-ValidationResult -Category 'Pester' -Status 'Pass' -Message "Pester module installed successfully"
            } catch {
                Write-ValidationResult -Category 'Pester' -Status 'Fail' -Message "Failed to install Pester: $($_.Exception.Message)"
                return
            }
        } else {
            Write-ValidationResult -Category 'Pester' -Status 'Info' -Message "Run with -Fix to install Pester automatically"
            return
        }
    }
    
    # Check Pester version
    $latestPester = $pesterModules[0]
    if ($latestPester.Version.Major -ge 5) {
        Write-ValidationResult -Category 'Pester' -Status 'Pass' -Message "Pester version: $($latestPester.Version) (Compatible)" -Details "Pester 5.x provides optimal testing features"
    } elseif ($latestPester.Version.Major -eq 4) {
        Write-ValidationResult -Category 'Pester' -Status 'Warning' -Message "Pester version: $($latestPester.Version) (Outdated)" -Details "Pester 5.x recommended for best compatibility"
        
        if ($Fix) {
            try {
                Write-Host "Updating to Pester 5.x..." -ForegroundColor Yellow
                Install-Module -Name Pester -Force -SkipPublisherCheck -Scope CurrentUser -AllowClobber
                Write-ValidationResult -Category 'Pester' -Status 'Pass' -Message "Pester updated to latest version"
            } catch {
                Write-ValidationResult -Category 'Pester' -Status 'Warning' -Message "Failed to update Pester: $($_.Exception.Message)"
            }
        }
    } else {
        Write-ValidationResult -Category 'Pester' -Status 'Fail' -Message "Pester version: $($latestPester.Version) (Incompatible)" -Details "Requires Pester 4.x or higher"
    }
    
    # Test Pester functionality
    try {
        Import-Module Pester -Force
        $pesterConfig = New-PesterConfiguration
        $pesterConfig.Run.PassThru = $true
        $pesterConfig.Output.Verbosity = 'None'
        Write-ValidationResult -Category 'Pester' -Status 'Pass' -Message "Pester module imports and functions correctly"
    } catch {
        Write-ValidationResult -Category 'Pester' -Status 'Fail' -Message "Pester module import failed: $($_.Exception.Message)"
    }
}

function Test-HashSmithModules {
    Write-Host ""
    Write-Host "📦 Validating HashSmith Modules" -ForegroundColor Cyan
    Write-Host "=" * 50
    
    # Get project structure
    $projectRoot = Split-Path $PSScriptRoot -Parent
    $modulesPath = Join-Path $projectRoot "Modules"
    
    if (-not (Test-Path $modulesPath)) {
        Write-ValidationResult -Category 'Modules' -Status 'Fail' -Message "Modules directory not found: $modulesPath"
        return
    }
    
    Write-ValidationResult -Category 'Modules' -Status 'Pass' -Message "Modules directory found: $modulesPath"
    
    # Expected modules
    $expectedModules = @(
        'HashSmithConfig',
        'HashSmithCore',
        'HashSmithDiscovery',
        'HashSmithHash',
        'HashSmithLogging',
        'HashSmithIntegrity',
        'HashSmithProcessor'
    )
    
    $missingModules = @()
    $validModules = @()
    
    foreach ($moduleName in $expectedModules) {
        $modulePath = Join-Path $modulesPath $moduleName
        $manifestPath = Join-Path $modulePath "$moduleName.psd1"
        $moduleFilePath = Join-Path $modulePath "$moduleName.psm1"
        
        if (Test-Path $manifestPath) {
            try {
                # Test manifest
                $manifest = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
                Write-ValidationResult -Category 'Modules' -Status 'Pass' -Message "$moduleName manifest valid (v$($manifest.Version))"
                
                # Test module file
                if (Test-Path $moduleFilePath) {
                    Write-ValidationResult -Category 'Modules' -Status 'Pass' -Message "$moduleName module file found"
                    $validModules += $moduleName
                } else {
                    Write-ValidationResult -Category 'Modules' -Status 'Warning' -Message "$moduleName module file missing: $moduleFilePath"
                }
            } catch {
                Write-ValidationResult -Category 'Modules' -Status 'Fail' -Message "$moduleName manifest invalid: $($_.Exception.Message)"
                $missingModules += $moduleName
            }
        } else {
            Write-ValidationResult -Category 'Modules' -Status 'Fail' -Message "$moduleName manifest not found: $manifestPath"
            $missingModules += $moduleName
        }
    }
    
    # Test module imports
    $importErrors = @()
    foreach ($moduleName in $validModules) {
        try {
            $modulePath = Join-Path $modulesPath $moduleName
            Import-Module $modulePath -Force -DisableNameChecking -ErrorAction Stop
            Write-ValidationResult -Category 'Modules' -Status 'Pass' -Message "$moduleName imports successfully"
        } catch {
            Write-ValidationResult -Category 'Modules' -Status 'Fail' -Message "$moduleName import failed: $($_.Exception.Message)"
            $importErrors += $moduleName
        }
    }
    
    # Summary
    $workingModules = $validModules.Count - $importErrors.Count
    Write-ValidationResult -Category 'Modules' -Status 'Info' -Message "Module validation: $workingModules/$($expectedModules.Count) modules working"
    
    if ($missingModules.Count -gt 0) {
        Write-ValidationResult -Category 'Modules' -Status 'Fail' -Message "Missing modules: $($missingModules -join ', ')"
    }
    
    if ($importErrors.Count -gt 0) {
        Write-ValidationResult -Category 'Modules' -Status 'Fail' -Message "Import errors: $($importErrors -join ', ')"
    }
}

function Test-TestEnvironment {
    Write-Host ""
    Write-Host "🧪 Validating Test Environment" -ForegroundColor Cyan
    Write-Host "=" * 50
    
    # Test directory structure
    $testsPath = $PSScriptRoot
    $helpersPath = Join-Path $testsPath "Helpers"
    $sampleDataPath = Join-Path $testsPath "SampleData"
    
    # Test main test file
    $mainTestFile = Join-Path $testsPath "HashSmith.Tests.ps1"
    if (Test-Path $mainTestFile) {
        Write-ValidationResult -Category 'TestData' -Status 'Pass' -Message "Main test file found: HashSmith.Tests.ps1"
    } else {
        Write-ValidationResult -Category 'TestData' -Status 'Fail' -Message "Main test file missing: $mainTestFile"
    }
    
    # Test helpers
    if (Test-Path $helpersPath) {
        $helpersScript = Join-Path $helpersPath "TestHelpers.ps1"
        $helpersModule = Join-Path $helpersPath "TestHelpers.psm1"
        
        if (Test-Path $helpersScript) {
            Write-ValidationResult -Category 'TestData' -Status 'Pass' -Message "Test helpers script found"
        } else {
            Write-ValidationResult -Category 'TestData' -Status 'Fail' -Message "Test helpers script missing"
        }
        
        if (Test-Path $helpersModule) {
            Write-ValidationResult -Category 'TestData' -Status 'Pass' -Message "Test helpers module found"
        } else {
            Write-ValidationResult -Category 'TestData' -Status 'Info' -Message "Test helpers module not found (optional)"
        }
    } else {
        Write-ValidationResult -Category 'TestData' -Status 'Fail' -Message "Helpers directory missing: $helpersPath"
    }
    
    # Test sample data
    if (Test-Path $sampleDataPath) {
        Write-ValidationResult -Category 'TestData' -Status 'Pass' -Message "Sample data directory found"
        
        # Check for generator script
        $generatorScript = Join-Path $sampleDataPath "Generate-TestData.ps1"
        if (Test-Path $generatorScript) {
            Write-ValidationResult -Category 'TestData' -Status 'Pass' -Message "Test data generator found"
            
            # Check for required test files
            $requiredFiles = @(
                "small_text_file.txt",
                "binary_file.bin",
                "corrupted_file.txt"
            )
            
            $missingFiles = @()
            foreach ($file in $requiredFiles) {
                $filePath = Join-Path $sampleDataPath $file
                if (Test-Path $filePath) {
                    $fileSize = (Get-Item $filePath).Length
                    Write-ValidationResult -Category 'TestData' -Status 'Pass' -Message "Test file found: $file ($fileSize bytes)"
                } else {
                    $missingFiles += $file
                }
            }
            
            if ($missingFiles.Count -gt 0) {
                Write-ValidationResult -Category 'TestData' -Status 'Warning' -Message "Missing test files: $($missingFiles -join ', ')"
                
                if ($Fix) {
                    try {
                        Write-Host "Generating missing test data..." -ForegroundColor Yellow
                        & $generatorScript -OutputPath $sampleDataPath -Force
                        Write-ValidationResult -Category 'TestData' -Status 'Pass' -Message "Test data generated successfully"
                    } catch {
                        Write-ValidationResult -Category 'TestData' -Status 'Fail' -Message "Failed to generate test data: $($_.Exception.Message)"
                    }
                }
            }
        } else {
            Write-ValidationResult -Category 'TestData' -Status 'Warning' -Message "Test data generator not found"
        }
    } else {
        Write-ValidationResult -Category 'TestData' -Status 'Fail' -Message "Sample data directory missing: $sampleDataPath"
        
        if ($Fix) {
            try {
                New-Item -Path $sampleDataPath -ItemType Directory -Force | Out-Null
                Write-ValidationResult -Category 'TestData' -Status 'Pass' -Message "Created sample data directory"
            } catch {
                Write-ValidationResult -Category 'TestData' -Status 'Fail' -Message "Failed to create sample data directory"
            }
        }
    }
}

function Test-Permissions {
    Write-Host ""
    Write-Host "🔐 Validating Permissions" -ForegroundColor Cyan
    Write-Host "=" * 50
    
    # Test write permissions to temp directory
    $tempTestFile = Join-Path $env:TEMP "HashSmithPermissionTest_$(Get-Random).txt"
    try {
        "Test content" | Set-Content -Path $tempTestFile -ErrorAction Stop
        Remove-Item $tempTestFile -Force -ErrorAction SilentlyContinue
        Write-ValidationResult -Category 'Permissions' -Status 'Pass' -Message "Temp directory write access confirmed"
    } catch {
        Write-ValidationResult -Category 'Permissions' -Status 'Fail' -Message "Cannot write to temp directory: $($_.Exception.Message)"
    }
    
    # Test current directory permissions
    $currentTestFile = Join-Path $PSScriptRoot "PermissionTest_$(Get-Random).txt"
    try {
        "Test content" | Set-Content -Path $currentTestFile -ErrorAction Stop
        Remove-Item $currentTestFile -Force -ErrorAction SilentlyContinue
        Write-ValidationResult -Category 'Permissions' -Status 'Pass' -Message "Current directory write access confirmed"
    } catch {
        Write-ValidationResult -Category 'Permissions' -Status 'Warning' -Message "Limited write access to current directory: $($_.Exception.Message)"
    }
    
    # Check if running as administrator (Windows)
    if ($IsWindows -or $env:OS -eq "Windows_NT") {
        $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        
        if ($isAdmin) {
            Write-ValidationResult -Category 'Permissions' -Status 'Info' -Message "Running with administrator privileges"
        } else {
            Write-ValidationResult -Category 'Permissions' -Status 'Info' -Message "Running with standard user privileges"
        }
    }
}

function Test-Performance {
    if ($SkipPerformance) {
        Write-Host ""
        Write-Host "⚡ Skipping Performance Validation" -ForegroundColor Yellow
        return
    }
    
    Write-Host ""
    Write-Host "⚡ Validating Performance Environment" -ForegroundColor Cyan
    Write-Host "=" * 50
    
    # System information
    $cpuCores = [Environment]::ProcessorCount
    Write-ValidationResult -Category 'Performance' -Status 'Info' -Message "CPU cores available: $cpuCores"
    
    # Memory information
    $memoryGB = 0
    try {
        if ($IsWindows -or $env:OS -eq "Windows_NT") {
            if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
                $memory = Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue | Measure-Object -Property Capacity -Sum
                $memoryGB = [Math]::Round($memory.Sum / 1GB, 1)
            } else {
                $memory = Get-WmiObject Win32_PhysicalMemory -ErrorAction SilentlyContinue | Measure-Object -Property Capacity -Sum
                $memoryGB = [Math]::Round($memory.Sum / 1GB, 1)
            }
        } elseif (Test-Path '/proc/meminfo') {
            $memInfo = Get-Content '/proc/meminfo' | Where-Object { $_ -match '^MemTotal:' }
            if ($memInfo -match '(\d+)\s*kB') {
                $memoryGB = [Math]::Round(([int64]$matches[1] * 1024 / 1GB), 1)
            }
        }
        
        Write-ValidationResult -Category 'Performance' -Status 'Info' -Message "System memory: $memoryGB GB"
        
        if ($memoryGB -lt 4) {
            Write-ValidationResult -Category 'Performance' -Status 'Warning' -Message "Low memory system - some performance tests may be skipped"
        } elseif ($memoryGB -ge 8) {
            Write-ValidationResult -Category 'Performance' -Status 'Pass' -Message "Adequate memory for all performance tests"
        }
    } catch {
        Write-ValidationResult -Category 'Performance' -Status 'Warning' -Message "Could not determine system memory"
    }
    
    # Disk speed test
    try {
        $testFile = Join-Path $env:TEMP "HashSmithDiskSpeedTest_$(Get-Random).bin"
        $testData = [byte[]]::new(1MB)
        [System.Random]::new().NextBytes($testData)
        
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        [System.IO.File]::WriteAllBytes($testFile, $testData)
        $stopwatch.Stop()
        
        $writeMBps = (1 / $stopwatch.Elapsed.TotalSeconds)
        
        $stopwatch.Restart()
        $readData = [System.IO.File]::ReadAllBytes($testFile)
        $stopwatch.Stop()
        
        $readMBps = (1 / $stopwatch.Elapsed.TotalSeconds)
        
        Remove-Item $testFile -Force -ErrorAction SilentlyContinue
        
        Write-ValidationResult -Category 'Performance' -Status 'Info' -Message "Disk performance: Write $($writeMBps.ToString('F1')) MB/s, Read $($readMBps.ToString('F1')) MB/s"
        
        if ($writeMBps -lt 10 -or $readMBps -lt 10) {
            Write-ValidationResult -Category 'Performance' -Status 'Warning' -Message "Slow disk performance detected - tests may take longer"
        } else {
            Write-ValidationResult -Category 'Performance' -Status 'Pass' -Message "Adequate disk performance for testing"
        }
    } catch {
        Write-ValidationResult -Category 'Performance' -Status 'Warning' -Message "Could not perform disk speed test: $($_.Exception.Message)"
    }
}

function Show-ValidationSummary {
    Write-Host ""
    Write-Host "📋 Validation Summary" -ForegroundColor Cyan
    Write-Host "=" * 50
    
    $totalIssues = 0
    $categories = @('PowerShell', 'Pester', 'Modules', 'TestData', 'Permissions')
    if (-not $SkipPerformance) {
        $categories += 'Performance'
    }
    
    foreach ($category in $categories) {
        $result = $ValidationResults[$category]
        $icon = switch ($result.Status) {
            'Pass' { '✅' }
            'Warning' { '⚠️ ' }
            'Fail' { '❌' }
            default { '❓' }
        }
        
        $color = switch ($result.Status) {
            'Pass' { 'Green' }
            'Warning' { 'Yellow' }
            'Fail' { 'Red' }
            default { 'Gray' }
        }
        
        Write-Host "$icon $category : $($result.Status)" -ForegroundColor $color
        
        if ($result.Issues.Count -gt 0) {
            $totalIssues += $result.Issues.Count
            if ($Detailed) {
                foreach ($issue in $result.Issues) {
                    Write-Host "     • $issue" -ForegroundColor DarkRed
                }
            }
        }
        
        if ($result.Status -eq 'Fail') {
            $ValidationResults.Overall.Status = 'Fail'
        } elseif ($result.Status -eq 'Warning' -and $ValidationResults.Overall.Status -ne 'Fail') {
            $ValidationResults.Overall.Status = 'Warning'
        }
    }
    
    if ($ValidationResults.Overall.Status -eq 'Unknown') {
        $ValidationResults.Overall.Status = 'Pass'
    }
    
    Write-Host ""
    Write-Host "Overall Status: " -NoNewline
    switch ($ValidationResults.Overall.Status) {
        'Pass' { 
            Write-Host "READY FOR TESTING ✅" -ForegroundColor Green
            Write-Host "All validations passed. The test environment is properly configured." -ForegroundColor Green
        }
        'Warning' { 
            Write-Host "READY WITH WARNINGS ⚠️" -ForegroundColor Yellow
            Write-Host "Test environment is functional but some optimizations could be made." -ForegroundColor Yellow
        }
        'Fail' { 
            Write-Host "NOT READY ❌" -ForegroundColor Red
            Write-Host "Critical issues found. Please resolve them before running tests." -ForegroundColor Red
        }
    }
    
    if ($totalIssues -gt 0) {
        Write-Host ""
        Write-Host "Found $totalIssues issue(s) total." -ForegroundColor Yellow
        if (-not $Fix) {
            Write-Host "Run with -Fix parameter to attempt automatic resolution." -ForegroundColor Cyan
        }
    }
    
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Cyan
    Write-Host "• Run tests: Invoke-Pester -Path Tests\HashSmith.Tests.ps1" -ForegroundColor White
    Write-Host "• Quick tests: .\Tests\HashSmith.PesterConfig.ps1 -QuickRun" -ForegroundColor White
    Write-Host "• Full tests: .\Tests\HashSmith.PesterConfig.ps1 -WithCoverage" -ForegroundColor White
    Write-Host "• Performance: .\Tests\HashSmith.PesterConfig.ps1 -PerformanceOnly" -ForegroundColor White
}

# Main execution
Write-Host ""
Write-Host "🔍 HashSmith Test Environment Validator" -ForegroundColor Blue
Write-Host "=" * 80 -ForegroundColor Blue
Write-Host "Comprehensive validation of test environment and dependencies" -ForegroundColor Gray
Write-Host ""

# Run all validations
Test-PowerShellEnvironment
Test-PesterModule
Test-HashSmithModules
Test-TestEnvironment
Test-Permissions
Test-Performance

# Show summary
Show-ValidationSummary

# Exit with appropriate code
switch ($ValidationResults.Overall.Status) {
    'Pass' { exit 0 }
    'Warning' { exit 0 }  # Warnings don't fail validation
    'Fail' { exit 1 }
    default { exit 2 }
}
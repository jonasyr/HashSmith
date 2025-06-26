<#
.SYNOPSIS
    Fixes cross-platform compatibility issues for HashSmith tests

.DESCRIPTION
    Addresses common issues when running HashSmith tests on Linux/macOS/Unix systems:
    - Temp directory environment variable differences
    - Path separator differences
    - Filesystem limitations (long filenames)
    - Permission issues

.EXAMPLE
    .\Tests\Fix-CrossPlatform.ps1

.EXAMPLE
    .\Tests\Fix-CrossPlatform.ps1 -WhatIf
#>

[CmdletBinding(SupportsShouldProcess)]
param()

function Write-FixResult {
    param(
        [string]$Action,
        [string]$Status,
        [string]$Details = ""
    )
    
    $color = switch ($Status) {
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error' { 'Red' }
        'Info' { 'Cyan' }
    }
    
    $icon = switch ($Status) {
        'Success' { '✅' }
        'Warning' { '⚠️ ' }
        'Error' { '❌' }
        'Info' { 'ℹ️ ' }
    }
    
    Write-Host "$icon $Action" -ForegroundColor $color
    if ($Details) {
        Write-Host "   $Details" -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "🔧 HashSmith Cross-Platform Compatibility Fixer" -ForegroundColor Blue
Write-Host "=" * 60 -ForegroundColor Blue
Write-Host ""

# Detect operating system
$IsLinuxCustom = $PSVersionTable.PSVersion.Major -ge 6 ? $IsLinux : $false
$IsMacOSCustom = $PSVersionTable.PSVersion.Major -ge 6 ? $IsMacOS : $false
$IsWindowsCustom = $PSVersionTable.PSVersion.Major -ge 6 ? $IsWindows : ($env:OS -eq "Windows_NT")

Write-FixResult -Action "Detected OS: $(if($IsWindowsCustom){'Windows'}elseif($IsLinuxCustom){'Linux'}elseif($IsMacOSCustom){'macOS'}else{'Unknown'})" -Status 'Info'

# Check temp directory
$TempDir = if ($env:TEMP) { 
    $env:TEMP 
} elseif ($env:TMPDIR) { 
    $env:TMPDIR 
} else { 
    '/tmp' 
}

if (Test-Path $TempDir) {
    Write-FixResult -Action "Temp directory available: $TempDir" -Status 'Success'
} else {
    Write-FixResult -Action "Temp directory not accessible: $TempDir" -Status 'Error'
    
    if ($PSCmdlet.ShouldProcess("Temp directory", "Create")) {
        try {
            New-Item -Path $TempDir -ItemType Directory -Force | Out-Null
            Write-FixResult -Action "Created temp directory: $TempDir" -Status 'Success'
        } catch {
            Write-FixResult -Action "Failed to create temp directory" -Status 'Error' -Details $_.Exception.Message
        }
    }
}

# Test temp directory write permissions
$testFile = Join-Path $TempDir "HashSmithCompatTest_$(Get-Random).txt"
try {
    if ($PSCmdlet.ShouldProcess($testFile, "Test write permissions")) {
        "Test" | Set-Content -Path $testFile
        Remove-Item $testFile -Force
        Write-FixResult -Action "Temp directory write permissions verified" -Status 'Success'
    }
} catch {
    Write-FixResult -Action "Temp directory write test failed" -Status 'Error' -Details $_.Exception.Message
}

# Check for problematic long filenames in test data
$ProjectRoot = Split-Path $PSScriptRoot -Parent
$SampleDataPath = Join-Path $ProjectRoot "Tests/SampleData"

if (Test-Path $SampleDataPath) {
    $longFiles = Get-ChildItem -Path $SampleDataPath -Recurse | Where-Object { $_.Name.Length -gt 200 }
    
    if ($longFiles) {
        Write-FixResult -Action "Found problematic long filenames: $($longFiles.Count)" -Status 'Warning'
        
        foreach ($file in $longFiles) {
            Write-FixResult -Action "Long filename: $($file.Name) ($($file.Name.Length) chars)" -Status 'Warning'
            
            if ($PSCmdlet.ShouldProcess($file.FullName, "Rename to shorter name")) {
                try {
                    $newName = "long_filename_" + ("x" * 50) + $file.Extension
                    $newPath = Join-Path $file.DirectoryName $newName
                    Move-Item -Path $file.FullName -Destination $newPath -Force
                    Write-FixResult -Action "Renamed to: $newName" -Status 'Success'
                } catch {
                    Write-FixResult -Action "Failed to rename long filename" -Status 'Error' -Details $_.Exception.Message
                }
            }
        }
    } else {
        Write-FixResult -Action "No problematic long filenames found" -Status 'Success'
    }
}

# Check PowerShell execution policy (Unix systems should be OK)
if ($IsWindowsCustom) {
    $execPolicy = Get-ExecutionPolicy
    if ($execPolicy -notin @('RemoteSigned', 'Unrestricted', 'Bypass')) {
        Write-FixResult -Action "Execution policy needs adjustment: $execPolicy" -Status 'Warning'
        
        if ($PSCmdlet.ShouldProcess("ExecutionPolicy", "Set to RemoteSigned")) {
            try {
                Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
                Write-FixResult -Action "Execution policy set to RemoteSigned" -Status 'Success'
            } catch {
                Write-FixResult -Action "Failed to set execution policy" -Status 'Error' -Details $_.Exception.Message
            }
        }
    } else {
        Write-FixResult -Action "Execution policy is acceptable: $execPolicy" -Status 'Success'
    }
} else {
    Write-FixResult -Action "Execution policy not applicable on Unix systems" -Status 'Info'
}

# Verify required modules can be loaded
$ProjectRoot = Split-Path $PSScriptRoot -Parent
$ModulesPath = Join-Path $ProjectRoot "Modules"

$expectedModules = @(
    'HashSmithConfig',
    'HashSmithCore',
    'HashSmithDiscovery',
    'HashSmithHash',
    'HashSmithLogging',
    'HashSmithIntegrity',
    'HashSmithProcessor'
)

$moduleIssues = @()

foreach ($moduleName in $expectedModules) {
    $modulePath = Join-Path $ModulesPath $moduleName
    try {
        if ($PSCmdlet.ShouldProcess($moduleName, "Test module import")) {
            Import-Module $modulePath -Force -DisableNameChecking -ErrorAction Stop
            Write-FixResult -Action "Module imports successfully: $moduleName" -Status 'Success'
        }
    } catch {
        Write-FixResult -Action "Module import failed: $moduleName" -Status 'Error' -Details $_.Exception.Message
        $moduleIssues += $moduleName
    }
}

# Check if Pester is compatible
try {
    $pesterVersion = Get-Module Pester -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
    if ($pesterVersion -and $pesterVersion.Version.Major -ge 5) {
        Write-FixResult -Action "Pester version compatible: $($pesterVersion.Version)" -Status 'Success'
    } else {
        Write-FixResult -Action "Pester version incompatible or missing" -Status 'Warning' -Details "Requires Pester 5.x"
        
        if ($PSCmdlet.ShouldProcess("Pester", "Install/Update")) {
            try {
                Install-Module -Name Pester -Force -SkipPublisherCheck -Scope CurrentUser
                Write-FixResult -Action "Pester installed/updated successfully" -Status 'Success'
            } catch {
                Write-FixResult -Action "Failed to install/update Pester" -Status 'Error' -Details $_.Exception.Message
            }
        }
    }
} catch {
    Write-FixResult -Action "Error checking Pester" -Status 'Error' -Details $_.Exception.Message
}

# Generate clean test data if needed
$GenerateScript = Join-Path $SampleDataPath "Generate-TestData.ps1"
if (Test-Path $GenerateScript) {
    $requiredFiles = @(
        "small_text_file.txt",
        "binary_file.bin",
        "corrupted_file.txt"
    )
    
    $missingFiles = $requiredFiles | Where-Object { -not (Test-Path (Join-Path $SampleDataPath $_)) }
    
    if ($missingFiles.Count -gt 0) {
        Write-FixResult -Action "Missing test data files: $($missingFiles.Count)" -Status 'Warning'
        
        if ($PSCmdlet.ShouldProcess("Test data", "Generate")) {
            try {
                & $GenerateScript -OutputPath $SampleDataPath -Force
                Write-FixResult -Action "Test data generated successfully" -Status 'Success'
            } catch {
                Write-FixResult -Action "Failed to generate test data" -Status 'Error' -Details $_.Exception.Message
            }
        }
    } else {
        Write-FixResult -Action "All required test data files present" -Status 'Success'
    }
}

# Summary
Write-Host ""
Write-Host "🏁 Cross-Platform Compatibility Check Complete" -ForegroundColor Green
Write-Host ""

if ($moduleIssues.Count -eq 0) {
    Write-Host "✅ All modules compatible and ready for testing" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "• Run validation: ./Tests/Validate-TestEnvironment.ps1 -Fix" -ForegroundColor White
    Write-Host "• Run quick tests: ./Tests/HashSmith.PesterConfig.ps1 -QuickRun" -ForegroundColor White
    Write-Host "• Run full tests: Invoke-Pester -Path Tests/HashSmith.Tests.ps1" -ForegroundColor White
} else {
    Write-Host "⚠️  Some modules have compatibility issues: $($moduleIssues -join ', ')" -ForegroundColor Yellow
    Write-Host "Please review the errors above and ensure all HashSmith modules are properly configured." -ForegroundColor Yellow
}

Write-Host ""
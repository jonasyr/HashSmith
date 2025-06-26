<#
.SYNOPSIS
    Simple test runner for HashSmith that bypasses configuration complexity

.DESCRIPTION
    A straightforward test runner that works across platforms without complex
    configuration dependencies. Ideal for quick validation and CI/CD.

.PARAMETER TestType
    Type of tests to run (Quick, Full, Unit, Integration)

.PARAMETER ShowOutput
    Control output verbosity (None, Normal, Detailed)

.PARAMETER Tag
    Specific test tags to include

.PARAMETER ExcludeTag
    Specific test tags to exclude

.EXAMPLE
    .\Tests\Run-SimpleTests.ps1 -TestType Quick

.EXAMPLE
    .\Tests\Run-SimpleTests.ps1 -TestType Unit -ShowOutput Detailed
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('Quick', 'Full', 'Unit', 'Integration', 'Performance')]
    [string]$TestType = 'Quick',
    
    [Parameter()]
    [ValidateSet('None', 'Normal', 'Detailed')]
    [string]$ShowOutput = 'Normal',
    
    [Parameter()]
    [string[]]$Tag = @(),
    
    [Parameter()]
    [string[]]$ExcludeTag = @()
)

function Write-TestMessage {
    param(
        [string]$Message,
        [string]$Level = 'Info'
    )
    
    $color = switch ($Level) {
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error' { 'Red' }
        'Info' { 'Cyan' }
        'Header' { 'Blue' }
    }
    
    $icon = switch ($Level) {
        'Success' { '✅' }
        'Warning' { '⚠️ ' }
        'Error' { '❌' }
        'Info' { 'ℹ️ ' }
        'Header' { '🧪' }
    }
    
    Write-Host "$icon $Message" -ForegroundColor $color
}

# Initialize
Write-Host ""
Write-TestMessage -Message "HashSmith Simple Test Runner" -Level 'Header'
Write-Host "=" * 50 -ForegroundColor Blue
Write-Host ""

# Validate environment
$ProjectRoot = Split-Path $PSScriptRoot -Parent
$TestsPath = $PSScriptRoot
$ModulesPath = Join-Path $ProjectRoot "Modules"

Write-TestMessage -Message "Project root: $ProjectRoot" -Level 'Info'
Write-TestMessage -Message "Test type: $TestType" -Level 'Info'

# Check Pester
try {
    Import-Module Pester -Force
    $pesterVersion = (Get-Module Pester).Version
    Write-TestMessage -Message "Pester version: $pesterVersion" -Level 'Success'
} catch {
    Write-TestMessage -Message "Failed to import Pester: $($_.Exception.Message)" -Level 'Error'
    exit 1
}

# Verify test file exists
$mainTestFile = Join-Path $TestsPath "HashSmith.Tests.ps1"
if (-not (Test-Path $mainTestFile)) {
    Write-TestMessage -Message "Main test file not found: $mainTestFile" -Level 'Error'
    exit 1
}

Write-TestMessage -Message "Main test file found" -Level 'Success'

# Check modules briefly
$expectedModules = @('HashSmithConfig', 'HashSmithCore', 'HashSmithDiscovery', 'HashSmithHash', 'HashSmithLogging', 'HashSmithIntegrity', 'HashSmithProcessor')
$missingModules = @()

foreach ($module in $expectedModules) {
    $modulePath = Join-Path $ModulesPath $module
    if (-not (Test-Path $modulePath)) {
        $missingModules += $module
    }
}

if ($missingModules.Count -gt 0) {
    Write-TestMessage -Message "Missing modules: $($missingModules -join ', ')" -Level 'Error'
    exit 1
}

Write-TestMessage -Message "All required modules found" -Level 'Success'

# Build Pester configuration
$config = New-PesterConfiguration

# Basic settings
$config.Run.Path = $mainTestFile
$config.Run.PassThru = $true
$config.Output.Verbosity = $ShowOutput
$config.TestResult.Enabled = $true
$config.TestResult.OutputPath = Join-Path $TestsPath "TestResults.xml"

# Configure tags based on test type
switch ($TestType) {
    'Quick' {
        $config.Filter.ExcludeTag = @('Performance', 'Stress', 'E2E', 'Integration')
        Write-TestMessage -Message "Running quick unit tests only" -Level 'Info'
    }
    'Unit' {
        $config.Filter.Tag = @('Unit')
        Write-TestMessage -Message "Running unit tests only" -Level 'Info'
    }
    'Integration' {
        $config.Filter.Tag = @('Integration')
        Write-TestMessage -Message "Running integration tests only" -Level 'Info'
    }
    'Performance' {
        $config.Filter.Tag = @('Performance', 'Stress')
        Write-TestMessage -Message "Running performance tests only" -Level 'Info'
    }
    'Full' {
        Write-TestMessage -Message "Running all tests" -Level 'Info'
    }
}

# Apply custom tags if specified
if ($Tag.Count -gt 0) {
    $config.Filter.Tag = $Tag
    Write-TestMessage -Message "Including tags: $($Tag -join ', ')" -Level 'Info'
}

if ($ExcludeTag.Count -gt 0) {
    $config.Filter.ExcludeTag = $ExcludeTag
    Write-TestMessage -Message "Excluding tags: $($ExcludeTag -join ', ')" -Level 'Info'
}

# Disable code coverage for simplicity
$config.CodeCoverage.Enabled = $false

Write-Host ""
Write-TestMessage -Message "Starting test execution..." -Level 'Header'
Write-Host ""

# Execute tests
try {
    $result = Invoke-Pester -Configuration $config
    
    Write-Host ""
    Write-TestMessage -Message "Test Execution Complete" -Level 'Header'
    Write-Host "=" * 50 -ForegroundColor Blue
    
    # Results summary
    Write-Host "Total Tests: $($result.TotalCount)" -ForegroundColor White
    Write-Host "Passed: $($result.PassedCount)" -ForegroundColor Green
    Write-Host "Failed: $($result.FailedCount)" -ForegroundColor $(if ($result.FailedCount -eq 0) { 'Green' } else { 'Red' })
    Write-Host "Skipped: $($result.SkippedCount)" -ForegroundColor Yellow
    Write-Host "Duration: $($result.Duration)" -ForegroundColor White
    
    # Show failed tests
    if ($result.FailedCount -gt 0) {
        Write-Host ""
        Write-TestMessage -Message "Failed Tests:" -Level 'Error'
        foreach ($test in $result.Failed) {
            Write-Host "• $($test.FullName)" -ForegroundColor Red
            if ($test.ErrorRecord -and $ShowOutput -eq 'Detailed') {
                Write-Host "  Error: $($test.ErrorRecord.Exception.Message)" -ForegroundColor DarkRed
            }
        }
    }
    
    Write-Host ""
    Write-Host "Test results saved to: $($config.TestResult.OutputPath)" -ForegroundColor Gray
    
    # Exit with appropriate code
    if ($result.FailedCount -eq 0) {
        Write-TestMessage -Message "All tests passed!" -Level 'Success'
        exit 0
    } else {
        Write-TestMessage -Message "$($result.FailedCount) test(s) failed" -Level 'Error'
        exit 1
    }
    
} catch {
    Write-TestMessage -Message "Test execution failed: $($_.Exception.Message)" -Level 'Error'
    Write-Host "Stack trace:" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
    exit 2
}
<#
.SYNOPSIS
    Pester configuration for HashSmith test suite

.DESCRIPTION
    Configures Pester v5 settings for optimal HashSmith testing including:
    - Test discovery and execution settings
    - Code coverage configuration  
    - Output formatting options
    - Performance optimization

.EXAMPLE
    # Run tests using this configuration
    $config = New-PesterConfiguration -FilePath "Tests\HashSmith.PesterConfig.ps1"
    Invoke-Pester -Configuration $config

.EXAMPLE
    # Quick test run
    .\Tests\HashSmith.PesterConfig.ps1 -QuickRun

.EXAMPLE
    # Full test run with coverage
    .\Tests\HashSmith.PesterConfig.ps1 -WithCoverage
#>

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$QuickRun,
    
    [Parameter()]
    [switch]$WithCoverage,
    
    [Parameter()]
    [switch]$PerformanceOnly,
    
    [Parameter()]
    [string[]]$Tags = @(),
    
    [Parameter()]
    [string[]]$ExcludeTags = @(),
    
    [Parameter()]
    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$Output = 'Detailed'
)

# Ensure we're running from the correct location
$ProjectRoot = Split-Path $PSScriptRoot -Parent
$TestsPath = Join-Path $ProjectRoot "Tests"
$ModulesPath = Join-Path $ProjectRoot "Modules"

if (-not (Test-Path $TestsPath) -or -not (Test-Path $ModulesPath)) {
    throw "This script must be run from the HashSmith project root or Tests directory"
}

# Create Pester configuration
$pesterConfig = New-PesterConfiguration

# Test Discovery Configuration
$pesterConfig.Run.Path = Join-Path $TestsPath "HashSmith.Tests.ps1"
$pesterConfig.Run.PassThru = $true

# Output Configuration
$pesterConfig.Output.Verbosity = $Output
$pesterConfig.Output.StackTraceVerbosity = 'Filtered'
$pesterConfig.Output.CIFormat = 'Auto'

# Test Selection Configuration
if ($QuickRun) {
    # Quick run excludes slow tests
    $pesterConfig.Filter.ExcludeTag = @('Performance', 'Stress', 'E2E') + $ExcludeTags
    Write-Host "🚀 Quick run mode: Excluding Performance, Stress, and E2E tests" -ForegroundColor Yellow
} elseif ($PerformanceOnly) {
    # Performance-only run
    $pesterConfig.Filter.Tag = @('Performance', 'Stress')
    Write-Host "⚡ Performance-only mode: Running Performance and Stress tests" -ForegroundColor Cyan
} else {
    # Normal run configuration
    if ($Tags.Count -gt 0) {
        $pesterConfig.Filter.Tag = $Tags
        Write-Host "🏷️  Running tests with tags: $($Tags -join ', ')" -ForegroundColor Green
    }
    if ($ExcludeTags.Count -gt 0) {
        $pesterConfig.Filter.ExcludeTag = $ExcludeTags
        Write-Host "🚫 Excluding tests with tags: $($ExcludeTags -join ', ')" -ForegroundColor Yellow
    }
}

# Code Coverage Configuration
if ($WithCoverage) {
    $pesterConfig.CodeCoverage.Enabled = $true
    $pesterConfig.CodeCoverage.Path = @(
        Join-Path $ModulesPath "HashSmithConfig\*.ps1"
        Join-Path $ModulesPath "HashSmithCore\*.ps1"
        Join-Path $ModulesPath "HashSmithDiscovery\*.ps1"
        Join-Path $ModulesPath "HashSmithHash\*.ps1"
        Join-Path $ModulesPath "HashSmithLogging\*.ps1"
        Join-Path $ModulesPath "HashSmithIntegrity\*.ps1"
        Join-Path $ModulesPath "HashSmithProcessor\*.ps1"
    )
    $pesterConfig.CodeCoverage.OutputFormat = @('JaCoCo', 'CoverageGutters')
    $pesterConfig.CodeCoverage.OutputPath = Join-Path $TestsPath "CodeCoverage.xml"
    $pesterConfig.CodeCoverage.CoveragePercentTarget = 80
    Write-Host "📊 Code coverage enabled (target: 80%)" -ForegroundColor Cyan
}

# Test Result Configuration  
$pesterConfig.TestResult.Enabled = $true
$pesterConfig.TestResult.OutputFormat = 'NUnitXml'
$pesterConfig.TestResult.OutputPath = Join-Path $TestsPath "TestResults.xml"

# Performance Configuration
$pesterConfig.Should.ErrorAction = 'Continue'  # Continue on assertion failures
$pesterConfig.Run.Throw = $false  # Don't throw on test failures

# Debug Configuration
if ($PSBoundParameters.ContainsKey('Debug') -and $Debug) {
    $pesterConfig.Debug.ShowFullErrors = $true
    $pesterConfig.Debug.WriteDebugMessages = $true
    $pesterConfig.Output.Verbosity = 'Diagnostic'
}

# Environment Setup
Write-Host ""
Write-Host "🧪 HashSmith Test Suite Configuration" -ForegroundColor Cyan
Write-Host "=" * 50 -ForegroundColor Blue

# Verify Pester version
$pesterVersion = Get-Module Pester -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
if (-not $pesterVersion -or $pesterVersion.Version.Major -lt 5) {
    Write-Warning "Pester 5.x required. Current version: $($pesterVersion.Version)"
    Write-Host "Install with: Install-Module Pester -Force -SkipPublisherCheck" -ForegroundColor Yellow
    exit 1
}

Write-Host "✅ Pester Version: $($pesterVersion.Version)" -ForegroundColor Green

# Verify PowerShell version
$psVersion = $PSVersionTable.PSVersion
Write-Host "✅ PowerShell Version: $psVersion" -ForegroundColor Green

# Check for test dependencies
$testDependencies = @(
    @{ Path = $TestsPath; Name = "Tests directory" }
    @{ Path = $ModulesPath; Name = "Modules directory" }
    @{ Path = (Join-Path $TestsPath "Helpers\TestHelpers.ps1"); Name = "Test helpers" }
    @{ Path = (Join-Path $TestsPath "SampleData"); Name = "Sample data directory" }
)

foreach ($dependency in $testDependencies) {
    if (Test-Path $dependency.Path) {
        Write-Host "✅ $($dependency.Name): Found" -ForegroundColor Green
    } else {
        Write-Host "❌ $($dependency.Name): Missing" -ForegroundColor Red
        $hasMissing = $true
    }
}

if ($hasMissing) {
    Write-Host ""
    Write-Host "❌ Missing dependencies detected. Please ensure all required files are present." -ForegroundColor Red
    exit 1
}

# Generate test data if needed
$sampleDataPath = Join-Path $TestsPath "SampleData"
$requiredTestFiles = @(
    "small_text_file.txt"
    "binary_file.bin" 
    "corrupted_file.txt"
)

$missingTestFiles = $requiredTestFiles | Where-Object { -not (Test-Path (Join-Path $sampleDataPath $_)) }
if ($missingTestFiles.Count -gt 0) {
    Write-Host ""
    Write-Host "⚠️  Missing test data files: $($missingTestFiles -join ', ')" -ForegroundColor Yellow
    Write-Host "🔧 Generating test data..." -ForegroundColor Cyan
    
    $generateScript = Join-Path $sampleDataPath "Generate-TestData.ps1"
    if (Test-Path $generateScript) {
        try {
            & $generateScript -OutputPath $sampleDataPath -Force
            Write-Host "✅ Test data generated successfully" -ForegroundColor Green
        } catch {
            Write-Host "❌ Failed to generate test data: $($_.Exception.Message)" -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "❌ Test data generator not found: $generateScript" -ForegroundColor Red
        exit 1
    }
}

# Display configuration summary
Write-Host ""
Write-Host "📋 Test Configuration Summary:" -ForegroundColor Yellow
Write-Host "   Test Path: $($pesterConfig.Run.Path)" -ForegroundColor White
Write-Host "   Output Level: $($pesterConfig.Output.Verbosity)" -ForegroundColor White
Write-Host "   Code Coverage: $(if ($pesterConfig.CodeCoverage.Enabled) { 'Enabled' } else { 'Disabled' })" -ForegroundColor White

if ($pesterConfig.Filter.Tag.Count -gt 0) {
    Write-Host "   Include Tags: $($pesterConfig.Filter.Tag -join ', ')" -ForegroundColor Green
}
if ($pesterConfig.Filter.ExcludeTag.Count -gt 0) {
    Write-Host "   Exclude Tags: $($pesterConfig.Filter.ExcludeTag -join ', ')" -ForegroundColor Red
}

Write-Host ""

# If script is being executed directly, run the tests
if ($MyInvocation.InvocationName -ne '.') {
    Write-Host "🚀 Starting test execution..." -ForegroundColor Green
    Write-Host ""
    
    # Run the tests
    $result = Invoke-Pester -Configuration $pesterConfig
    
    # Display results summary
    Write-Host ""
    Write-Host "📊 Test Execution Summary:" -ForegroundColor Cyan
    Write-Host "=" * 50 -ForegroundColor Blue
    Write-Host "   Total Tests: $($result.TotalCount)" -ForegroundColor White
    Write-Host "   Passed: $($result.PassedCount)" -ForegroundColor Green
    Write-Host "   Failed: $($result.FailedCount)" -ForegroundColor $(if ($result.FailedCount -eq 0) { 'Green' } else { 'Red' })
    Write-Host "   Skipped: $($result.SkippedCount)" -ForegroundColor Yellow
    Write-Host "   Duration: $($result.Duration)" -ForegroundColor White
    
    if ($WithCoverage -and $result.CodeCoverage) {
        $coveragePercent = [Math]::Round(($result.CodeCoverage.NumberOfCommandsExecuted / $result.CodeCoverage.NumberOfCommandsAnalyzed) * 100, 2)
        Write-Host "   Code Coverage: $coveragePercent%" -ForegroundColor $(if ($coveragePercent -ge 80) { 'Green' } else { 'Yellow' })
    }
    
    # Display failed tests if any
    if ($result.FailedCount -gt 0) {
        Write-Host ""
        Write-Host "❌ Failed Tests:" -ForegroundColor Red
        foreach ($failedTest in $result.Failed) {
            Write-Host "   • $($failedTest.FullName)" -ForegroundColor Red
            if ($failedTest.ErrorRecord) {
                Write-Host "     Error: $($failedTest.ErrorRecord.Exception.Message)" -ForegroundColor DarkRed
            }
        }
    }
    
    # Output file locations
    Write-Host ""
    Write-Host "📄 Output Files:" -ForegroundColor Yellow
    Write-Host "   Test Results: $($pesterConfig.TestResult.OutputPath)" -ForegroundColor White
    if ($WithCoverage) {
        Write-Host "   Coverage Report: $($pesterConfig.CodeCoverage.OutputPath)" -ForegroundColor White
    }
    
    # Exit with appropriate code
    if ($result.FailedCount -gt 0) {
        Write-Host ""
        Write-Host "❌ Some tests failed. Please review the results above." -ForegroundColor Red
        exit 1
    } else {
        Write-Host ""
        Write-Host "✅ All tests passed successfully!" -ForegroundColor Green
        exit 0
    }
} else {
    # Script was dot-sourced, return the configuration
    return $pesterConfig
}
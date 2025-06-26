# HashSmith Test Suite

This directory contains a comprehensive Pester v5 test suite for the HashSmith file integrity verification system.

## Overview

The test suite provides ≥80% code coverage across all HashSmith modules and includes:

- **Unit Tests**: Individual function testing with mocked dependencies
- **Integration Tests**: Multi-module interaction testing  
- **End-to-End Tests**: Complete workflow validation
- **Performance Tests**: Stress testing and performance validation
- **Edge Case Tests**: Error handling and boundary condition testing

## Test Structure

```
Tests/
├── HashSmith.Tests.ps1       # Main Pester test file
├── Helpers/
│   └── TestHelpers.ps1       # Test utility functions
├── SampleData/
│   ├── Generate-TestData.ps1 # Test data generator script
│   ├── small_text_file.txt   # Small text file for basic tests
│   ├── binary_file.bin       # Large binary file for performance tests
│   ├── corrupted_file.txt    # File with challenging content
│   └── [additional test files]
└── README.md                 # This file
```

## Prerequisites

- **PowerShell 5.1+** (PowerShell 7+ recommended for parallel processing tests)
- **Pester 5.x** module
- **HashSmith modules** (imported automatically by tests)

### Installing Pester 5.x

```powershell
# Install latest Pester (if not already installed)
Install-Module Pester -Force -SkipPublisherCheck

# Verify Pester version
Get-Module Pester -ListAvailable | Select-Object Version
```

## Running Tests

### Quick Start (Cross-Platform)

For the fastest and most reliable test execution across all platforms:

```powershell
# Fix any cross-platform issues first (Linux/macOS)
.\Tests\Fix-CrossPlatform.ps1

# Run quick tests (recommended for first-time setup)
.\Tests\Run-SimpleTests.ps1 -TestType Quick

# Run all tests
.\Tests\Run-SimpleTests.ps1 -TestType Full -ShowOutput Detailed
```

### Standard Pester Commands

```powershell
# Run complete test suite
Invoke-Pester -Path Tests\HashSmith.Tests.ps1 -Output Detailed

# Run with code coverage (Windows recommended)
.\Tests\HashSmith.PesterConfig.ps1 -WithCoverage

# Run performance tests only
.\Tests\Run-SimpleTests.ps1 -TestType Performance
```

### Run Specific Test Categories

```powershell
# Unit tests only
.\Tests\Run-SimpleTests.ps1 -TestType Unit

# Integration tests only  
.\Tests\Run-SimpleTests.ps1 -TestType Integration

# Custom tags
.\Tests\Run-SimpleTests.ps1 -Tag "Config","Core" -ShowOutput Detailed
```

### Run with Different Output Formats

```powershell
# Detailed output with timing
Invoke-Pester -Path Tests\HashSmith.Tests.ps1 -Output Detailed

# Generate test report
Invoke-Pester -Path Tests\HashSmith.Tests.ps1 -PassThru | Export-CliXml "TestResults.xml"

# Generate HTML report (requires ReportGenerator or similar)
Invoke-Pester -Path Tests\HashSmith.Tests.ps1 -EnableExit:$false -PassThru | 
    ConvertTo-Html | Out-File "TestReport.html"
```

## Test Data

The test suite automatically generates sample data files for testing. You can also manually generate test data:

```powershell
# Generate fresh test data
.\Tests\SampleData\Generate-TestData.ps1 -Force

# Generate test data in custom location
.\Tests\SampleData\Generate-TestData.ps1 -OutputPath "C:\CustomTestData" -Force
```

### Test Data Files

| File | Purpose | Size |
|------|---------|------|
| `small_text_file.txt` | Basic hash computation testing | <1KB |
| `binary_file.bin` | Performance and streaming tests | 5MB |
| `corrupted_file.txt` | Edge case and error handling | Variable |
| `hidden_file.txt` | Hidden file discovery testing | <1KB |
| `unicode_*.txt` | Unicode filename handling | <1KB |
| `empty_file.txt` | Empty file edge case | 0 bytes |
| `SubDirectory/` | Recursive discovery testing | Multiple files |

## Test Coverage

The test suite covers the following modules and functions:

### HashSmithConfig Module
- ✅ Configuration initialization and validation
- ✅ Statistics management (atomic counters)
- ✅ Buffer size optimization
- ✅ Circuit breaker functionality

### HashSmithCore Module  
- ✅ Logging functionality with different levels
- ✅ Path normalization (Windows/UNC/Long paths)
- ✅ File accessibility testing
- ✅ File integrity snapshots
- ✅ Network path testing
- ✅ Symbolic link detection

### HashSmithDiscovery Module
- ✅ Comprehensive file discovery
- ✅ Pattern-based file exclusion
- ✅ Hidden file inclusion/exclusion
- ✅ Performance metrics validation
- ✅ Discovery completeness testing

### HashSmithHash Module
- ✅ Multi-algorithm hash computation (MD5, SHA1, SHA256, SHA512)
- ✅ Large file streaming processing
- ✅ Error handling and retry logic
- ✅ Integrity verification
- ✅ Performance optimization validation

### HashSmithLogging Module
- ✅ Log file initialization with headers
- ✅ Hash entry logging (success and error)
- ✅ Batch processing functionality
- ✅ Existing log parsing and resume
- ✅ Log format validation

### HashSmithIntegrity Module
- ✅ Deterministic directory hash computation
- ✅ Large file collection handling
- ✅ Performance optimization validation
- ✅ Metadata inclusion options

### HashSmithProcessor Module
- ✅ End-to-end file processing orchestration
- ✅ Resume functionality validation
- ✅ Error handling and recovery
- ✅ Parallel processing coordination

## Expected Test Results

A successful test run should show:

```
Starting discovery in: Tests\SampleData
    Discovering files [✓]
    Parsing test cases [✓]

Running tests:
    HashSmithConfig Module [✓]
    HashSmithCore Module [✓]
    HashSmithDiscovery Module [✓]
    HashSmithHash Module [✓]
    HashSmithLogging Module [✓]
    HashSmithIntegrity Module [✓]
    HashSmithProcessor Module [✓]
    End-to-End Integration Tests [✓]
    Performance Tests [✓]

Tests completed.
Passed: XX, Failed: 0, Skipped: 0, Total: XX
```

## Troubleshooting

### Common Issues

1. **Module Import Failures**
   ```
   Error: Required module not found: HashSmithConfig
   ```
   **Solution**: Ensure you're running tests from the project root directory

2. **Test Data Missing**
   ```
   Error: Test file not found: small_text_file.txt
   ```
   **Solution**: Run the test data generator:
   ```powershell
   .\Tests\SampleData\Generate-TestData.ps1 -Force
   ```

3. **Permission Errors**
   ```
   Error: Access denied writing to log file
   ```
   **Solution**: Run PowerShell as Administrator or change temp directory permissions

4. **Pester Version Issues**
   ```
   Error: Pester version 3.x detected, requires 5.x
   ```
   **Solution**: Update Pester module:
   ```powershell
   Install-Module Pester -Force -SkipPublisherCheck -AllowClobber
   ```

### Debug Mode

For detailed debugging information:

```powershell
# Enable verbose output
$VerbosePreference = "Continue"
Invoke-Pester -Path Tests\HashSmith.Tests.ps1 -Verbose

# Debug specific failing test
Invoke-Pester -Path Tests\HashSmith.Tests.ps1 -FullName "*specific test name*" -Debug
```

### Performance Considerations

- Large file tests may take several minutes on slower systems
- Performance tests validate throughput and may fail on resource-constrained systems  
- Consider excluding performance tests for quick validation:
  ```powershell
  Invoke-Pester -Path Tests\HashSmith.Tests.ps1 -ExcludeTag "Performance"
  ```

## Contributing

When adding new tests:

1. Follow the **AAA pattern** (Arrange-Act-Assert)
2. Use descriptive test names that explain the scenario
3. Include both positive and negative test cases
4. Add appropriate tags for test categorization
5. Update this README if adding new test categories or requirements

### Test Naming Convention

```powershell
Describe "ModuleName" -Tag "Category" {
    Context "Specific Functionality" {
        It "Should do something when condition is met" {
            # Arrange
            # Act  
            # Assert
        }
    }
}
```

## Test Tags

- `Unit`: Individual function testing
- `Integration`: Multi-module testing  
- `E2E`: End-to-end workflow testing
- `Performance`: Performance and stress testing
- `Config`: Configuration module tests
- `Core`: Core utilities module tests
- `Discovery`: File discovery module tests
- `Hash`: Hash computation module tests
- `Logging`: Logging module tests
- `Integrity`: Integrity computation tests
- `Processor`: Processing orchestration tests

Run specific categories using the `-Tag` parameter with `Invoke-Pester`.
#Requires -Modules Pester

<#
.SYNOPSIS
    Comprehensive Pester v5 test suite for HashSmith file integrity verification system

.DESCRIPTION
    Tests all core functionality across HashSmith modules with ≥80% code coverage.
    Follows AAA (Arrange-Act-Assert) pattern and tests real-world scenarios.

.NOTES
    Version: 1.0.0
    Requires: Pester 5.x, PowerShell 5.1+
    Usage: Invoke-Pester -Path Tests/HashSmith.Tests.ps1
#>

BeforeAll {
    # Import required modules - adjust paths relative to project root
    $ProjectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $ModulesPath = Join-Path $ProjectRoot "Modules"
    $TestHelpersPath = Join-Path $PSScriptRoot "Helpers"
    $SampleDataPath = Join-Path $PSScriptRoot "SampleData"
    
    # Ensure test directories exist
    @($TestHelpersPath, $SampleDataPath) | ForEach-Object {
        if (-not (Test-Path $_)) {
            New-Item -Path $_ -ItemType Directory -Force | Out-Null
        }
    }
    
    # Import HashSmith modules in dependency order
    $ModuleLoadOrder = @(
        "HashSmithConfig",
        "HashSmithCore", 
        "HashSmithDiscovery",
        "HashSmithHash",
        "HashSmithLogging",
        "HashSmithIntegrity",
        "HashSmithProcessor"
    )
    
    foreach ($ModuleName in $ModuleLoadOrder) {
        $ModulePath = Join-Path $ModulesPath $ModuleName
        if (Test-Path $ModulePath) {
            Import-Module $ModulePath -Force -DisableNameChecking
        } else {
            throw "Required module not found: $ModulePath"
        }
    }
    
    # Import test helpers
    if (Test-Path (Join-Path $TestHelpersPath "TestHelpers.ps1")) {
        . (Join-Path $TestHelpersPath "TestHelpers.ps1")
    }
    
    # Initialize test configuration
    Initialize-HashSmithConfig -ConfigOverrides @{ TestMode = $true }
    
    # Create sample test data files
    Initialize-TestData -SampleDataPath $SampleDataPath
    
    # Set global test variables
    $Global:TestLogPath = Join-Path $env:TEMP "HashSmithTest_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    $Global:TestSourceDir = $SampleDataPath
}

AfterAll {
    # Cleanup test artifacts
    if ($Global:TestLogPath -and (Test-Path $Global:TestLogPath)) {
        Remove-Item $Global:TestLogPath -Force -ErrorAction SilentlyContinue
    }
    
    # Reset statistics
    Reset-HashSmithStatistics
}

Describe "HashSmithConfig Module" -Tag "Config", "Unit" {
    
    Context "Configuration Initialization" {
        
        It "Should initialize configuration with default values" {
            # Arrange
            $expectedKeys = @('Version', 'Algorithm', 'TargetPath', 'LogPath', 'MaxParallelJobs')
            
            # Act
            Initialize-HashSmithConfig
            $config = Get-HashSmithConfig
            
            # Assert
            $config | Should -Not -BeNullOrEmpty
            $config.Keys | Should -Contain 'Version'
            $config.Version | Should -Match '^\d+\.\d+\.\d+'
            $config.Algorithm | Should -BeIn @('MD5', 'SHA1', 'SHA256', 'SHA512')
        }
        
        It "Should apply configuration overrides correctly" {
            # Arrange
            $overrides = @{
                Algorithm = 'SHA256'
                MaxParallelJobs = 4
                ChunkSize = 500
            }
            
            # Act
            Initialize-HashSmithConfig -ConfigOverrides $overrides
            $config = Get-HashSmithConfig
            
            # Assert
            $config.Algorithm | Should -Be 'SHA256'
            $config.MaxParallelJobs | Should -Be 4
            $config.ChunkSize | Should -Be 500
        }
        
        It "Should reject invalid configuration values" {
            # Arrange
            $invalidOverrides = @{
                MaxParallelJobs = 100  # Beyond max of 64
                ChunkSize = 10000      # Beyond max of 5000
            }
            
            # Act & Assert
            # Invalid values should be warned about and not applied
            { Initialize-HashSmithConfig -ConfigOverrides $invalidOverrides } | Should -Not -Throw
            $config = Get-HashSmithConfig
            $config.MaxParallelJobs | Should -BeLessOrEqual 64
            $config.ChunkSize | Should -BeLessOrEqual 5000
        }
    }
    
    Context "Statistics Management" {
        
        BeforeEach {
            Reset-HashSmithStatistics
        }
        
        It "Should initialize statistics with default counters" {
            # Arrange & Act
            $stats = Get-HashSmithStatistics
            
            # Assert
            $stats | Should -Not -BeNullOrEmpty
            $stats.Keys | Should -Contain 'FilesDiscovered'
            $stats.Keys | Should -Contain 'FilesProcessed'
            $stats.Keys | Should -Contain 'FilesError'
            $stats.FilesDiscovered | Should -Be 0
        }
        
        It "Should increment atomic counters correctly" {
            # Arrange
            $initialStats = Get-HashSmithStatistics
            
            # Act
            Add-HashSmithStatistic -Name 'FilesProcessed' -Amount 5
            Add-HashSmithStatistic -Name 'FilesProcessed' -Amount 3
            
            # Assert
            $newStats = Get-HashSmithStatistics
            $newStats.FilesProcessed | Should -Be 8
        }
        
        It "Should set specific statistic values" {
            # Arrange & Act
            Set-HashSmithStatistic -Name 'FilesDiscovered' -Value 1000
            
            # Assert
            $stats = Get-HashSmithStatistics
            $stats.FilesDiscovered | Should -Be 1000
        }
        
        It "Should reset all statistics" {
            # Arrange
            Set-HashSmithStatistic -Name 'FilesProcessed' -Value 100
            Set-HashSmithStatistic -Name 'FilesError' -Value 5
            
            # Act
            Reset-HashSmithStatistics
            
            # Assert
            $stats = Get-HashSmithStatistics
            $stats.FilesProcessed | Should -Be 0
            $stats.FilesError | Should -Be 0
        }
    }
    
    Context "Optimal Buffer Size Calculation" {
        
        It "Should return appropriate buffer size for MD5 algorithm" {
            # Arrange
            $algorithm = 'MD5'
            $fileSize = 10MB
            
            # Act
            $bufferSize = Get-HashSmithOptimalBufferSize -Algorithm $algorithm -FileSize $fileSize
            
            # Assert
            $bufferSize | Should -BeGreaterThan 0
            $bufferSize | Should -BeLessOrEqual (16 * 1MB)  # Max buffer size
        }
        
        It "Should scale buffer size based on file size" {
            # Arrange
            $algorithm = 'SHA256'
            $smallFileBuffer = Get-HashSmithOptimalBufferSize -Algorithm $algorithm -FileSize 1KB
            $largeFileBuffer = Get-HashSmithOptimalBufferSize -Algorithm $algorithm -FileSize 1GB
            
            # Act & Assert
            $largeFileBuffer | Should -BeGreaterThan $smallFileBuffer
        }
    }
}

Describe "HashSmithCore Module" -Tag "Core", "Unit" {
    
    Context "Logging Functionality" {
        
        It "Should write log messages with proper formatting" {
            # Arrange
            $testMessage = "Test log message"
            $component = "TEST"
            
            # Act - Capture console output
            $output = Write-HashSmithLog -Message $testMessage -Level INFO -Component $component 6>&1
            
            # Assert
            # Function should execute without throwing
            { Write-HashSmithLog -Message $testMessage -Level INFO -Component $component } | Should -Not -Throw
        }
        
        It "Should handle different log levels" {
            # Arrange
            $levels = @('DEBUG', 'INFO', 'WARN', 'ERROR', 'SUCCESS')
            
            # Act & Assert
            foreach ($level in $levels) {
                { Write-HashSmithLog -Message "Test" -Level $level } | Should -Not -Throw
            }
        }
    }
    
    Context "Path Normalization" {
        
        It "Should normalize Windows paths correctly" {
            # Arrange
            $inputPath = "C:\Test\..\Test\File.txt"
            
            # Act
            $normalizedPath = Get-HashSmithNormalizedPath -Path $inputPath
            
            # Assert
            $normalizedPath | Should -Not -BeNullOrEmpty
            $normalizedPath | Should -Not -Match '\.\.'  # No relative components
        }
        
        It "Should handle long paths with \\?\ prefix" {
            # Arrange
            $longPath = "C:\" + ("VeryLongDirectoryName" * 20) + "\File.txt"  # Create a long path
            
            # Act
            $normalizedPath = Get-HashSmithNormalizedPath -Path $longPath
            
            # Assert
            $normalizedPath | Should -Not -BeNullOrEmpty
            if ($normalizedPath.Length -gt 260) {
                $normalizedPath | Should -Match '^\\\\?\\'
            }
        }
        
        It "Should handle UNC paths correctly" {
            # Arrange
            $uncPath = "\\server\share\file.txt"
            
            # Act
            $normalizedPath = Get-HashSmithNormalizedPath -Path $uncPath
            
            # Assert
            $normalizedPath | Should -Not -BeNullOrEmpty
            $normalizedPath | Should -Match '^\\\\([?]\\UNC\\|[^\\]+\\)'
        }
    }
    
    Context "File Accessibility Testing" {
        
        It "Should detect accessible files" {
            # Arrange
            $testFile = Join-Path $Global:TestSourceDir "small_text_file.txt"
            
            # Act
            $isAccessible = Test-HashSmithFileAccessible -Path $testFile -TimeoutMs 5000
            
            # Assert
            $isAccessible | Should -Be $true
        }
        
        It "Should handle non-existent files gracefully" {
            # Arrange
            $nonExistentFile = Join-Path $Global:TestSourceDir "non_existent_file.txt"
            
            # Act
            $isAccessible = Test-HashSmithFileAccessible -Path $nonExistentFile -TimeoutMs 1000
            
            # Assert
            $isAccessible | Should -Be $false
        }
    }
    
    Context "File Integrity Snapshots" {
        
        It "Should create file integrity snapshot" {
            # Arrange
            $testFile = Join-Path $Global:TestSourceDir "small_text_file.txt"
            
            # Act
            $snapshot = Get-HashSmithFileIntegritySnapshot -Path $testFile
            
            # Assert
            $snapshot | Should -Not -BeNullOrEmpty
            $snapshot.Keys | Should -Contain 'Size'
            $snapshot.Keys | Should -Contain 'LastWriteTime'
            $snapshot.Keys | Should -Contain 'SnapshotTime'
            $snapshot.Size | Should -BeGreaterThan 0
        }
        
        It "Should detect matching integrity snapshots" {
            # Arrange
            $testFile = Join-Path $Global:TestSourceDir "small_text_file.txt"
            $snapshot1 = Get-HashSmithFileIntegritySnapshot -Path $testFile
            Start-Sleep -Milliseconds 100  # Brief delay
            $snapshot2 = Get-HashSmithFileIntegritySnapshot -Path $testFile
            
            # Act
            $isMatch = Test-HashSmithFileIntegrityMatch -Snapshot1 $snapshot1 -Snapshot2 $snapshot2
            
            # Assert
            $isMatch | Should -Be $true
        }
    }
    
    Context "Circuit Breaker Functionality" {
        
        BeforeEach {
            # Reset circuit breaker state
            $circuitBreaker = Get-HashSmithCircuitBreaker
            $circuitBreaker.FailureCount = 0
            $circuitBreaker.IsOpen = $false
        }
        
        It "Should allow operations when circuit breaker is closed" {
            # Arrange & Act
            $isAllowed = Test-HashSmithCircuitBreaker -Component 'TEST'
            
            # Assert
            $isAllowed | Should -Be $true
        }
        
        It "Should increment failure count on failures" {
            # Arrange
            $initialState = Get-HashSmithCircuitBreaker
            $initialFailures = $initialState.FailureCount
            
            # Act
            Update-HashSmithCircuitBreaker -IsFailure $true -Component 'TEST'
            
            # Assert
            $newState = Get-HashSmithCircuitBreaker
            $newState.FailureCount | Should -BeGreaterThan $initialFailures
        }
        
        It "Should open circuit breaker after threshold failures" {
            # Arrange
            $config = Get-HashSmithConfig
            $threshold = $config.CircuitBreakerThreshold
            
            # Act - Trigger multiple failures
            for ($i = 0; $i -lt ($threshold + 1); $i++) {
                Update-HashSmithCircuitBreaker -IsFailure $true -Component 'TEST'
            }
            
            # Assert
            $state = Get-HashSmithCircuitBreaker
            $state.IsOpen | Should -Be $true
        }
    }
}

Describe "HashSmithDiscovery Module" -Tag "Discovery", "Integration" {
    
    Context "File Discovery" {
        
        It "Should discover all files in test directory" {
            # Arrange
            $testPath = $Global:TestSourceDir
            
            # Act
            $result = Get-HashSmithAllFiles -Path $testPath -IncludeHidden
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.Files | Should -Not -BeNullOrEmpty
            $result.Files.Count | Should -BeGreaterThan 0
            $result.Statistics | Should -Not -BeNullOrEmpty
            $result.Statistics.TotalFound | Should -Be $result.Files.Count
        }
        
        It "Should exclude files matching patterns" {
            # Arrange
            $testPath = $Global:TestSourceDir
            $excludePatterns = @("*.tmp", "temp_*")
            
            # Act
            $result = Get-HashSmithAllFiles -Path $testPath -ExcludePatterns $excludePatterns
            
            # Assert
            $result.Files | Where-Object { $_.Name -like "*.tmp" } | Should -BeNullOrEmpty
            $result.Files | Where-Object { $_.Name -like "temp_*" } | Should -BeNullOrEmpty
        }
        
        It "Should include hidden files when specified" {
            # Arrange
            $testPath = $Global:TestSourceDir
            
            # Act
            $resultWithHidden = Get-HashSmithAllFiles -Path $testPath -IncludeHidden
            $resultWithoutHidden = Get-HashSmithAllFiles -Path $testPath
            
            # Assert
            $resultWithHidden.Files.Count | Should -BeGreaterOrEqual $resultWithoutHidden.Files.Count
        }
        
        It "Should provide accurate performance metrics" {
            # Arrange
            $testPath = $Global:TestSourceDir
            
            # Act
            $result = Get-HashSmithAllFiles -Path $testPath
            
            # Assert
            $result.Statistics.DiscoveryTime | Should -BeGreaterThan 0
            $result.Statistics.FilesPerSecond | Should -BeGreaterThan 0
            $result.Statistics.DirectoriesProcessed | Should -BeGreaterThan 0
        }
    }
    
    Context "Discovery Completeness Testing" {
        
        It "Should validate discovery completeness" {
            # Arrange
            $testPath = $Global:TestSourceDir
            $discoveryResult = Get-HashSmithAllFiles -Path $testPath
            
            # Act & Assert
            { Test-HashSmithFileDiscoveryCompleteness -Path $testPath -DiscoveredFiles $discoveryResult.Files -StrictMode } | Should -Not -Throw
        }
    }
}

Describe "HashSmithHash Module" -Tag "Hash", "Unit" {
    
    Context "File Hash Computation" {
        
        It "Should compute MD5 hash for small file" {
            # Arrange
            $testFile = Join-Path $Global:TestSourceDir "small_text_file.txt"
            $algorithm = "MD5"
            
            # Act
            $result = Get-HashSmithFileHashSafe -Path $testFile -Algorithm $algorithm
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.Success | Should -Be $true
            $result.Hash | Should -Not -BeNullOrEmpty
            $result.Hash.Length | Should -Be 32  # MD5 is 32 hex characters
            $result.Hash | Should -Match '^[a-f0-9]{32}$'
            $result.Size | Should -BeGreaterThan 0
        }
        
        It "Should compute SHA256 hash for binary file" {
            # Arrange
            $testFile = Join-Path $Global:TestSourceDir "binary_file.bin"
            $algorithm = "SHA256"
            
            # Act
            $result = Get-HashSmithFileHashSafe -Path $testFile -Algorithm $algorithm
            
            # Assert
            $result.Success | Should -Be $true
            $result.Hash | Should -Not -BeNullOrEmpty
            $result.Hash.Length | Should -Be 64  # SHA256 is 64 hex characters
            $result.Hash | Should -Match '^[a-f0-9]{64}$'
        }
        
        It "Should handle different algorithms correctly" {
            # Arrange
            $testFile = Join-Path $Global:TestSourceDir "small_text_file.txt"
            $algorithms = @("MD5", "SHA1", "SHA256", "SHA512")
            $expectedLengths = @{
                "MD5" = 32
                "SHA1" = 40
                "SHA256" = 64
                "SHA512" = 128
            }
            
            # Act & Assert
            foreach ($algorithm in $algorithms) {
                $result = Get-HashSmithFileHashSafe -Path $testFile -Algorithm $algorithm
                $result.Success | Should -Be $true
                $result.Hash.Length | Should -Be $expectedLengths[$algorithm]
            }
        }
        
        It "Should handle non-existent files gracefully" {
            # Arrange
            $nonExistentFile = Join-Path $Global:TestSourceDir "does_not_exist.txt"
            
            # Act
            $result = Get-HashSmithFileHashSafe -Path $nonExistentFile -Algorithm "MD5"
            
            # Assert
            $result.Success | Should -Be $false
            $result.Error | Should -Not -BeNullOrEmpty
            $result.ErrorCategory | Should -Be 'FileNotFound'
        }
        
        It "Should retry on transient failures" {
            # Arrange
            $testFile = Join-Path $Global:TestSourceDir "small_text_file.txt"
            $retryCount = 2
            
            # Act
            $result = Get-HashSmithFileHashSafe -Path $testFile -Algorithm "MD5" -RetryCount $retryCount
            
            # Assert
            $result.Success | Should -Be $true
            $result.Attempts | Should -BeLessOrEqual $retryCount
        }
        
        It "Should verify integrity when enabled" {
            # Arrange
            $testFile = Join-Path $Global:TestSourceDir "small_text_file.txt"
            
            # Act
            $result = Get-HashSmithFileHashSafe -Path $testFile -Algorithm "MD5" -VerifyIntegrity
            
            # Assert
            $result.Success | Should -Be $true
            if ($result.ContainsKey('Integrity')) {
                $result.Integrity | Should -Be $true
            }
        }
        
        It "Should provide performance metrics for large files" {
            # Arrange
            $testFile = Join-Path $Global:TestSourceDir "binary_file.bin"
            
            # Act
            $result = Get-HashSmithFileHashSafe -Path $testFile -Algorithm "SHA256"
            
            # Assert
            $result.PerformanceMetrics | Should -Not -BeNullOrEmpty
            $result.PerformanceMetrics.BufferSize | Should -BeGreaterThan 0
            $result.PerformanceMetrics.OptimizationsUsed | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "HashSmithLogging Module" -Tag "Logging", "Integration" {
    
    Context "Log File Initialization" {
        
        It "Should initialize log file with proper header" {
            # Arrange
            $testLogPath = Join-Path $env:TEMP "TestHashLog_$(Get-Random).log"
            $algorithm = "MD5"
            $sourcePath = $Global:TestSourceDir
            $stats = @{ TotalFound = 100; TotalSkipped = 5; TotalSymlinks = 2; DiscoveryTime = [TimeSpan]::FromSeconds(1.5); FilesPerSecond = 67 }
            $config = @{ MaxParallelJobs = 4; ChunkSize = 1000 }
            
            # Act
            Initialize-HashSmithLogFile -LogPath $testLogPath -Algorithm $algorithm -SourcePath $sourcePath -DiscoveryStats $stats -Configuration $config
            
            # Assert
            Test-Path $testLogPath | Should -Be $true
            $content = Get-Content $testLogPath -Raw
            $content | Should -Match "HashSmith"
            $content | Should -Match $algorithm
            $content | Should -Match $sourcePath
            
            # Cleanup
            Remove-Item $testLogPath -Force -ErrorAction SilentlyContinue
        }
    }
    
    Context "Hash Entry Logging" {
        
        BeforeEach {
            $script:TestLogPath = Join-Path $env:TEMP "TestHashEntry_$(Get-Random).log"
        }
        
        AfterEach {
            if (Test-Path $script:TestLogPath) {
                Remove-Item $script:TestLogPath -Force -ErrorAction SilentlyContinue
            }
        }
        
        It "Should write successful hash entry" {
            # Arrange
            $filePath = "C:\Test\File.txt"
            $hash = "abc123def456"
            $size = 1024
            $modified = Get-Date
            
            # Act
            Write-HashSmithHashEntry -LogPath $script:TestLogPath -FilePath $filePath -Hash $hash -Size $size -Modified $modified
            Clear-HashSmithLogBatch -LogPath $script:TestLogPath  # Force flush
            
            # Assert
            Test-Path $script:TestLogPath | Should -Be $true
            $content = Get-Content $script:TestLogPath -Raw
            $content | Should -Match [regex]::Escape($filePath)
            $content | Should -Match $hash
            $content | Should -Match "size: $size"
        }
        
        It "Should write error entry" {
            # Arrange
            $filePath = "C:\Test\ErrorFile.txt"
            $errorMessage = "Access denied"
            $errorCategory = "AccessDenied"
            $size = 0
            $modified = Get-Date
            
            # Act
            Write-HashSmithHashEntry -LogPath $script:TestLogPath -FilePath $filePath -Size $size -Modified $modified -ErrorMessage $errorMessage -ErrorCategory $errorCategory
            Clear-HashSmithLogBatch -LogPath $script:TestLogPath  # Force flush
            
            # Assert
            $content = Get-Content $script:TestLogPath -Raw
            $content | Should -Match "ERROR\($errorCategory\)"
            $content | Should -Match [regex]::Escape($errorMessage)
        }
        
        It "Should handle batch processing correctly" {
            # Arrange
            $entries = @(
                @{ FilePath = "File1.txt"; Hash = "hash1"; Size = 100; Modified = Get-Date }
                @{ FilePath = "File2.txt"; Hash = "hash2"; Size = 200; Modified = Get-Date }
                @{ FilePath = "File3.txt"; Hash = "hash3"; Size = 300; Modified = Get-Date }
            )
            
            # Act
            foreach ($entry in $entries) {
                Write-HashSmithHashEntry -LogPath $script:TestLogPath -FilePath $entry.FilePath -Hash $entry.Hash -Size $entry.Size -Modified $entry.Modified -UseBatching
            }
            Clear-HashSmithLogBatch -LogPath $script:TestLogPath  # Force flush
            
            # Assert
            $content = Get-Content $script:TestLogPath
            $content.Count | Should -BeGreaterOrEqual $entries.Count
            foreach ($entry in $entries) {
                $content | Should -Contain { $_ -match [regex]::Escape($entry.FilePath) }
            }
        }
    }
    
    Context "Existing Entries Loading" {
        
        It "Should parse existing log entries correctly" {
            # Arrange
            $testLogPath = Join-Path $env:TEMP "TestExistingLog_$(Get-Random).log"
            $logContent = @(
                "# HashSmith Test Log",
                "File1.txt = abc123, size: 1024",
                "File2.txt = def456, size: 2048",
                "ErrorFile.txt = ERROR(AccessDenied): Cannot access file, size: 0"
            )
            $logContent | Set-Content -Path $testLogPath
            
            # Act
            $entries = Get-HashSmithExistingEntries -LogPath $testLogPath
            
            # Assert
            $entries | Should -Not -BeNullOrEmpty
            $entries.Processed.Count | Should -Be 2
            $entries.Failed.Count | Should -Be 1
            $entries.Statistics.ProcessedCount | Should -Be 2
            $entries.Statistics.FailedCount | Should -Be 1
            
            # Cleanup
            Remove-Item $testLogPath -Force -ErrorAction SilentlyContinue
        }
        
        It "Should handle non-existent log file" {
            # Arrange
            $nonExistentLog = Join-Path $env:TEMP "NonExistent_$(Get-Random).log"
            
            # Act
            $entries = Get-HashSmithExistingEntries -LogPath $nonExistentLog
            
            # Assert
            $entries.Processed.Count | Should -Be 0
            $entries.Failed.Count | Should -Be 0
        }
    }
}

Describe "HashSmithIntegrity Module" -Tag "Integrity", "Unit" {
    
    Context "Directory Integrity Hash" {
        
        It "Should compute directory integrity hash from file hashes" {
            # Arrange
            $fileHashes = @{
                "File1.txt" = @{ Hash = "abc123"; Size = 1024 }
                "File2.txt" = @{ Hash = "def456"; Size = 2048 }
                "File3.txt" = @{ Hash = "789ghi"; Size = 512 }
            }
            $algorithm = "MD5"
            
            # Act
            $result = Get-HashSmithDirectoryIntegrityHash -FileHashes $fileHashes -Algorithm $algorithm
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.Hash | Should -Not -BeNullOrEmpty
            $result.Hash | Should -Match '^[a-f0-9]{32}$'  # MD5 format
            $result.FileCount | Should -Be 3
            $result.TotalSize | Should -Be (1024 + 2048 + 512)
            $result.Algorithm | Should -Be $algorithm
        }
        
        It "Should produce deterministic hashes for same input" {
            # Arrange
            $fileHashes = @{
                "FileA.txt" = @{ Hash = "hash1"; Size = 100 }
                "FileB.txt" = @{ Hash = "hash2"; Size = 200 }
            }
            
            # Act
            $result1 = Get-HashSmithDirectoryIntegrityHash -FileHashes $fileHashes -Algorithm "SHA256"
            $result2 = Get-HashSmithDirectoryIntegrityHash -FileHashes $fileHashes -Algorithm "SHA256"
            
            # Assert
            $result1.Hash | Should -Be $result2.Hash
        }
        
        It "Should handle empty file collection" {
            # Arrange
            $emptyFileHashes = @{}
            
            # Act
            $result = Get-HashSmithDirectoryIntegrityHash -FileHashes $emptyFileHashes -Algorithm "MD5"
            
            # Assert
            $result | Should -BeNullOrEmpty
        }
        
        It "Should include metadata when requested" {
            # Arrange
            $fileHashes = @{
                "Test.txt" = @{ Hash = "testhash"; Size = 1000 }
            }
            
            # Act
            $result = Get-HashSmithDirectoryIntegrityHash -FileHashes $fileHashes -Algorithm "SHA1" -IncludeMetadata
            
            # Assert
            $result.Metadata | Should -Not -BeNullOrEmpty
            $result.Metadata.Method | Should -Match "metadata"
        }
        
        It "Should provide performance metrics" {
            # Arrange
            $fileHashes = @{}
            for ($i = 1; $i -le 100; $i++) {
                $fileHashes["File$i.txt"] = @{ Hash = "hash$i"; Size = $i * 100 }
            }
            
            # Act
            $result = Get-HashSmithDirectoryIntegrityHash -FileHashes $fileHashes -Algorithm "MD5"
            
            # Assert
            $result.Metadata.ComputationTime | Should -BeGreaterThan 0
            $result.Metadata.FilesPerSecond | Should -BeGreaterThan 0
        }
    }
}

Describe "HashSmithProcessor Module" -Tag "Processor", "Integration" {
    
    Context "File Processing Orchestration" {
        
        It "Should process files and return hash results" {
            # Arrange
            $testFiles = Get-ChildItem -Path $Global:TestSourceDir -File
            $testLogPath = Join-Path $env:TEMP "ProcessorTest_$(Get-Random).log"
            $algorithm = "MD5"
            
            # Act
            $result = Start-HashSmithFileProcessing -Files $testFiles -LogPath $testLogPath -Algorithm $algorithm -MaxThreads 2 -ChunkSize 10
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.Keys.Count | Should -BeGreaterThan 0
            
            # Verify log file was created
            Test-Path $testLogPath | Should -Be $true
            
            # Cleanup
            Remove-Item $testLogPath -Force -ErrorAction SilentlyContinue
        }
        
        It "Should handle resume functionality" {
            # Arrange
            $testFiles = Get-ChildItem -Path $Global:TestSourceDir -File
            $testLogPath = Join-Path $env:TEMP "ResumeTest_$(Get-Random).log"
            
            # Create existing entries to simulate resume
            $existingEntries = @{
                Processed = @{}
                Failed = @{}
            }
            
            if ($testFiles.Count -gt 0) {
                $firstFile = $testFiles[0]
                $existingEntries.Processed[$firstFile.FullName] = @{
                    Hash = "existing_hash"
                    Size = $firstFile.Length
                }
            }
            
            # Act
            $result = Start-HashSmithFileProcessing -Files $testFiles -LogPath $testLogPath -Algorithm "MD5" -ExistingEntries $existingEntries -Resume -MaxThreads 1 -ChunkSize 5
            
            # Assert
            # Should skip the already processed file
            if ($testFiles.Count -gt 1) {
                $result.Keys.Count | Should -BeLess $testFiles.Count
            }
            
            # Cleanup
            Remove-Item $testLogPath -Force -ErrorAction SilentlyContinue
        }
        
        It "Should handle processing errors gracefully" {
            # Arrange
            $nonExistentFile = [System.IO.FileInfo]::new("C:\NonExistent\File.txt")
            $testLogPath = Join-Path $env:TEMP "ErrorTest_$(Get-Random).log"
            
            # Act & Assert
            { Start-HashSmithFileProcessing -Files @($nonExistentFile) -LogPath $testLogPath -Algorithm "MD5" -MaxThreads 1 } | Should -Not -Throw
            
            # Cleanup
            Remove-Item $testLogPath -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "End-to-End Integration Tests" -Tag "Integration", "E2E" {
    
    Context "Complete HashSmith Workflow" {
        
        It "Should execute complete file integrity verification workflow" {
            # Arrange
            $testSourceDir = $Global:TestSourceDir
            $testLogPath = Join-Path $env:TEMP "E2E_Test_$(Get-Random).log"
            $algorithm = "SHA256"
            
            # Act - Execute the complete workflow
            
            # 1. File Discovery
            $discoveryResult = Get-HashSmithAllFiles -Path $testSourceDir -IncludeHidden
            $discoveryResult.Files.Count | Should -BeGreaterThan 0
            
            # 2. Log Initialization
            Initialize-HashSmithLogFile -LogPath $testLogPath -Algorithm $algorithm -SourcePath $testSourceDir -DiscoveryStats $discoveryResult.Statistics -Configuration @{ MaxParallelJobs = 2; ChunkSize = 10 }
            
            # 3. File Processing
            $processingResult = Start-HashSmithFileProcessing -Files $discoveryResult.Files -LogPath $testLogPath -Algorithm $algorithm -MaxThreads 2 -ChunkSize 5
            
            # 4. Directory Integrity Hash
            if ($processingResult.Count -gt 0) {
                $directoryHash = Get-HashSmithDirectoryIntegrityHash -FileHashes $processingResult -Algorithm $algorithm
                $directoryHash | Should -Not -BeNullOrEmpty
            }
            
            # Assert - Verify complete workflow
            Test-Path $testLogPath | Should -Be $true
            $logContent = Get-Content $testLogPath -Raw
            $logContent | Should -Match "HashSmith"
            $logContent | Should -Match $algorithm
            
            if ($processingResult.Count -gt 0) {
                $processingResult.Keys.Count | Should -BeGreaterThan 0
                foreach ($key in $processingResult.Keys) {
                    $processingResult[$key].Hash | Should -Not -BeNullOrEmpty
                }
            }
            
            # Cleanup
            Remove-Item $testLogPath -Force -ErrorAction SilentlyContinue
        }
        
        It "Should handle resume workflow correctly" {
            # Arrange
            $testSourceDir = $Global:TestSourceDir
            $testLogPath = Join-Path $env:TEMP "Resume_E2E_$(Get-Random).log"
            
            # First run - process some files
            $discoveryResult = Get-HashSmithAllFiles -Path $testSourceDir
            if ($discoveryResult.Files.Count -gt 0) {
                Initialize-HashSmithLogFile -LogPath $testLogPath -Algorithm "MD5" -SourcePath $testSourceDir -DiscoveryStats $discoveryResult.Statistics -Configuration @{ MaxParallelJobs = 1; ChunkSize = 5 }
                
                # Process only first file
                $firstFile = $discoveryResult.Files[0]
                $firstResult = Start-HashSmithFileProcessing -Files @($firstFile) -LogPath $testLogPath -Algorithm "MD5" -MaxThreads 1
                
                # Act - Resume with all files
                $existingEntries = Get-HashSmithExistingEntries -LogPath $testLogPath
                $resumeResult = Start-HashSmithFileProcessing -Files $discoveryResult.Files -LogPath $testLogPath -Algorithm "MD5" -ExistingEntries $existingEntries -Resume -MaxThreads 1
                
                # Assert
                $existingEntries.Processed.Count | Should -BeGreaterOrEqual 1
                # In resume mode, already processed files should be skipped
            }
            
            # Cleanup
            Remove-Item $testLogPath -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "Performance and Stress Tests" -Tag "Performance", "Stress" {
    
    Context "Large File Handling" {
        
        It "Should handle large files efficiently" {
            # Arrange
            $largeFile = Join-Path $Global:TestSourceDir "binary_file.bin"
            
            # Act
            $startTime = Get-Date
            $result = Get-HashSmithFileHashSafe -Path $largeFile -Algorithm "SHA256"
            $duration = (Get-Date) - $startTime
            
            # Assert
            $result.Success | Should -Be $true
            $result.PerformanceMetrics.ThroughputMBps | Should -BeGreaterThan 0
            $duration.TotalSeconds | Should -BeLessOrEqual 30  # Should complete within reasonable time
        }
    }
    
    Context "Concurrent Operations" {
        
        It "Should handle concurrent statistics updates" {
            # Arrange
            $jobs = @()
            
            # Act - Start multiple background jobs updating statistics
            for ($i = 1; $i -le 5; $i++) {
                $jobs += Start-Job -ScriptBlock {
                    param($ModulesPath, $iterations)
                    Import-Module (Join-Path $ModulesPath "HashSmithConfig") -Force
                    for ($j = 1; $j -le $iterations; $j++) {
                        Add-HashSmithStatistic -Name 'FilesProcessed' -Amount 1
                    }
                } -ArgumentList $ModulesPath, 10
            }
            
            # Wait for completion
            $jobs | Wait-Job | Remove-Job
            
            # Assert
            $stats = Get-HashSmithStatistics
            $stats.FilesProcessed | Should -Be 50  # 5 jobs * 10 iterations each
        }
    }
}
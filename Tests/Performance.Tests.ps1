#Requires -Modules Pester

<#
.SYNOPSIS
    Performance and benchmark tests for HashSmith file integrity verification system

.DESCRIPTION
    Specialized Pester test suite focused on performance testing, benchmarking,
    and stress testing of HashSmith components under various load conditions.

.NOTES
    Version: 1.0.0
    Requires: Pester 5.x, PowerShell 5.1+
    Usage: Invoke-Pester -Path Tests/Performance.Tests.ps1 -Tag "Performance"
#>

BeforeAll {
    # Import required modules
    $ProjectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $ModulesPath = Join-Path $ProjectRoot "Modules"
    $TestHelpersPath = Join-Path $PSScriptRoot "Helpers"
    
    # Import HashSmith modules
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
        Import-Module $ModulePath -Force -DisableNameChecking
    }
    
    # Import test helpers
    Import-Module (Join-Path $TestHelpersPath "TestHelpers") -Force
    
    # Initialize configuration for performance testing
    Initialize-HashSmithConfig -ConfigOverrides @{ 
        TestMode = $true
        MaxParallelJobs = [Environment]::ProcessorCount
        ChunkSize = 1000
    }
    
    # Performance test configuration
    $Global:PerformanceConfig = @{
        SmallFileSize = 1KB
        MediumFileSize = 1MB
        LargeFileSize = 10MB
        VeryLargeFileSize = 100MB
        MaxTestDuration = [TimeSpan]::FromMinutes(5)
        MinThroughputMBps = 10  # Minimum acceptable throughput
        MaxMemoryUsageMB = 1000  # Maximum acceptable memory usage
        FileCountThreshold = 1000  # Files per second threshold
    }
    
    # Create performance test environment
    $Global:PerfTestEnv = New-TestEnvironment -IncludeComplexData
    
    Write-Host "🚀 Performance test environment initialized" -ForegroundColor Green
    Write-Host "   Test Path: $($Global:PerfTestEnv.Path)" -ForegroundColor Gray
    Write-Host "   CPU Cores: $([Environment]::ProcessorCount)" -ForegroundColor Gray
    
    # Get system capabilities
    $memoryGB = 0
    try {
        if ($IsWindows -or $env:OS -eq "Windows_NT") {
            $memory = Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue | Measure-Object -Property Capacity -Sum
            $memoryGB = [Math]::Round($memory.Sum / 1GB, 1)
        }
    } catch {
        $memoryGB = 8  # Default assumption
    }
    
    Write-Host "   System RAM: $memoryGB GB" -ForegroundColor Gray
    
    # Adjust performance expectations based on system capabilities
    if ($memoryGB -lt 8) {
        $Global:PerformanceConfig.MaxMemoryUsageMB = 500
        $Global:PerformanceConfig.MinThroughputMBps = 5
        Write-Host "   ⚠️  Adjusted expectations for lower-memory system" -ForegroundColor Yellow
    }
}

AfterAll {
    # Cleanup performance test environment
    if ($Global:PerfTestEnv) {
        Remove-TestEnvironment -EnvironmentPath $Global:PerfTestEnv.Path
    }
    
    # Reset statistics
    Reset-HashSmithStatistics
}

Describe "HashSmith Performance Tests" -Tag "Performance", "Benchmark" {
    
    Context "File Discovery Performance" {
        
        It "Should discover files quickly in large directories" {
            # Arrange
            $testDir = New-TestDirectory -Prefix "PerfDiscovery"
            $fileCount = 5000
            
            # Create many small files
            Write-Host "Creating $fileCount test files..." -ForegroundColor Yellow
            for ($i = 1; $i -le $fileCount; $i++) {
                $fileName = "testfile_$($i.ToString('D5')).txt"
                $filePath = Join-Path $testDir $fileName
                "Test content $i" | Set-Content -Path $filePath -NoNewline
                
                if ($i % 1000 -eq 0) {
                    Write-Host "  Created $i files..." -ForegroundColor Gray
                }
            }
            
            # Act
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Get-HashSmithAllFiles -Path $testDir -IncludeHidden
            $stopwatch.Stop()
            
            # Assert
            $result.Files.Count | Should -Be $fileCount
            $result.Statistics.DiscoveryTime | Should -BeLessOrEqual 30  # Should complete within 30 seconds
            $result.Statistics.FilesPerSecond | Should -BeGreaterThan $Global:PerformanceConfig.FileCountThreshold
            
            Write-Host "✅ Discovery Performance: $($result.Statistics.FilesPerSecond) files/sec" -ForegroundColor Green
            
            # Cleanup
            Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        It "Should handle deep directory structures efficiently" {
            # Arrange
            $testDir = New-TestDirectory -Prefix "PerfDeepDirs"
            $maxDepth = 20
            $filesPerLevel = 5
            
            # Create deep directory structure
            $currentPath = $testDir
            for ($depth = 1; $depth -le $maxDepth; $depth++) {
                $levelDir = Join-Path $currentPath "Level$depth"
                New-Item -Path $levelDir -ItemType Directory -Force | Out-Null
                
                # Add files at this level
                for ($f = 1; $f -le $filesPerLevel; $f++) {
                    $fileName = "file_depth${depth}_${f}.txt"
                    $filePath = Join-Path $levelDir $fileName
                    "Content at depth $depth, file $f" | Set-Content -Path $filePath
                }
                
                $currentPath = $levelDir
            }
            
            # Act
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Get-HashSmithAllFiles -Path $testDir
            $stopwatch.Stop()
            
            # Assert
            $expectedFiles = $maxDepth * $filesPerLevel
            $result.Files.Count | Should -Be $expectedFiles
            $stopwatch.Elapsed.TotalSeconds | Should -BeLessOrEqual 10  # Should handle depth efficiently
            
            Write-Host "✅ Deep Directory Performance: $($result.Statistics.FilesPerSecond) files/sec at depth $maxDepth" -ForegroundColor Green
            
            # Cleanup
            Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    Context "Hash Computation Performance" {
        
        It "Should compute hashes efficiently for small files" {
            # Arrange
            $testFile = Join-Path $Global:PerfTestEnv.DataPath "small_perf_test.txt"
            "Small test content for performance testing" | Set-Content -Path $testFile
            
            # Act & Assert
            $execution = Measure-TestExecution -ScriptBlock {
                Get-HashSmithFileHashSafe -Path $using:testFile -Algorithm "MD5"
            }
            
            $execution.Success | Should -Be $true
            $execution.Result.Success | Should -Be $true
            $execution.Duration.TotalMilliseconds | Should -BeLessOrEqual 100  # Should be very fast for small files
            
            Write-Host "✅ Small File Hash: $($execution.Duration.TotalMilliseconds)ms" -ForegroundColor Green
        }
        
        It "Should achieve acceptable throughput for medium files" {
            # Arrange
            $testFile = Join-Path $Global:PerfTestEnv.DataPath "medium_perf_test.bin"
            $testData = [byte[]]::new($Global:PerformanceConfig.MediumFileSize)
            [System.Random]::new(42).NextBytes($testData)
            [System.IO.File]::WriteAllBytes($testFile, $testData)
            
            # Act
            $execution = Measure-TestExecution -ScriptBlock {
                Get-HashSmithFileHashSafe -Path $using:testFile -Algorithm "SHA256"
            }
            
            # Assert
            $execution.Success | Should -Be $true
            $execution.Result.Success | Should -Be $true
            
            if ($execution.Result.PerformanceMetrics) {
                $throughput = $execution.Result.PerformanceMetrics.ThroughputMBps
                $throughput | Should -BeGreaterThan $Global:PerformanceConfig.MinThroughputMBps
                Write-Host "✅ Medium File Throughput: $throughput MB/s" -ForegroundColor Green
            }
            
            $execution.Duration.TotalSeconds | Should -BeLessOrEqual 10  # Should complete within reasonable time
        }
        
        It "Should handle large files with streaming efficiently" -Skip:($Global:PerformanceConfig.MaxTestDuration.TotalMinutes -lt 3) {
            # Arrange
            $testFile = Join-Path $Global:PerfTestEnv.DataPath "large_perf_test.bin"
            
            # Skip if file already exists and is large enough
            if (-not (Test-Path $testFile) -or (Get-Item $testFile).Length -lt $Global:PerformanceConfig.LargeFileSize) {
                Write-Host "Creating large test file ($($Global:PerformanceConfig.LargeFileSize / 1MB) MB)..." -ForegroundColor Yellow
                $testData = [byte[]]::new($Global:PerformanceConfig.LargeFileSize)
                [System.Random]::new(123).NextBytes($testData)
                [System.IO.File]::WriteAllBytes($testFile, $testData)
            }
            
            # Act
            $execution = Measure-TestExecution -ScriptBlock {
                Get-HashSmithFileHashSafe -Path $using:testFile -Algorithm "SHA256"
            }
            
            # Assert
            $execution.Success | Should -Be $true
            $execution.Result.Success | Should -Be $true
            $execution.Duration | Should -BeLessOrEqual $Global:PerformanceConfig.MaxTestDuration
            
            if ($execution.Result.PerformanceMetrics) {
                $throughput = $execution.Result.PerformanceMetrics.ThroughputMBps
                $throughput | Should -BeGreaterThan ($Global:PerformanceConfig.MinThroughputMBps / 2)  # Allow lower throughput for very large files
                Write-Host "✅ Large File Throughput: $throughput MB/s" -ForegroundColor Green
                
                # Check that streaming optimizations were used
                $execution.Result.PerformanceMetrics.OptimizationsUsed | Should -Contain "StreamingOptimized"
            }
        }
        
        It "Should scale hash computation across multiple algorithms" {
            # Arrange
            $testFile = Join-Path $Global:PerfTestEnv.DataPath "multi_algo_test.bin"
            $testData = [byte[]]::new(1MB)
            [System.Random]::new(456).NextBytes($testData)
            [System.IO.File]::WriteAllBytes($testFile, $testData)
            
            $algorithms = @('MD5', 'SHA1', 'SHA256', 'SHA512')
            $results = @{}
            
            # Act
            foreach ($algorithm in $algorithms) {
                $execution = Measure-TestExecution -ScriptBlock {
                    Get-HashSmithFileHashSafe -Path $using:testFile -Algorithm $using:algorithm
                }
                $results[$algorithm] = $execution
            }
            
            # Assert
            foreach ($algorithm in $algorithms) {
                $results[$algorithm].Success | Should -Be $true
                $results[$algorithm].Result.Success | Should -Be $true
                $results[$algorithm].Duration.TotalSeconds | Should -BeLessOrEqual 5
                
                Write-Host "✅ $algorithm Performance: $($results[$algorithm].Duration.TotalMilliseconds)ms" -ForegroundColor Green
            }
            
            # MD5 should generally be faster than SHA512
            $results['MD5'].Duration | Should -BeLessOrEqual $results['SHA512'].Duration
        }
    }
    
    Context "Parallel Processing Performance" {
        
        It "Should efficiently process multiple files in parallel" {
            # Arrange
            $testFiles = @()
            $fileCount = 20
            
            for ($i = 1; $i -le $fileCount; $i++) {
                $fileName = "parallel_test_$i.txt"
                $filePath = Join-Path $Global:PerfTestEnv.DataPath $fileName
                "Test content for parallel processing file $i" * 100 | Set-Content -Path $filePath
                $testFiles += Get-Item $filePath
            }
            
            $testLogPath = Join-Path $Global:PerfTestEnv.LogsPath "parallel_perf_test.log"
            
            # Act
            $execution = Measure-TestExecution -ScriptBlock {
                Start-HashSmithFileProcessing -Files $using:testFiles -LogPath $using:testLogPath -Algorithm "MD5" -MaxThreads 4 -ChunkSize 5 -UseParallel
            }
            
            # Assert
            $execution.Success | Should -Be $true
            $execution.Result.Keys.Count | Should -Be $fileCount
            $execution.Duration.TotalSeconds | Should -BeLessOrEqual 30
            
            # Parallel processing should be reasonably efficient
            $filesPerSecond = $fileCount / $execution.Duration.TotalSeconds
            $filesPerSecond | Should -BeGreaterThan 1
            
            Write-Host "✅ Parallel Processing: $filesPerSecond files/sec" -ForegroundColor Green
        }
        
        It "Should show performance improvement with multiple threads" {
            # Arrange
            $testFiles = @()
            $fileCount = 10
            
            for ($i = 1; $i -le $fileCount; $i++) {
                $fileName = "threading_test_$i.bin"
                $filePath = Join-Path $Global:PerfTestEnv.DataPath $fileName
                $testData = [byte[]]::new(100KB)
                [System.Random]::new($i).NextBytes($testData)
                [System.IO.File]::WriteAllBytes($filePath, $testData)
                $testFiles += Get-Item $filePath
            }
            
            # Test with 1 thread
            $singleThreadLog = Join-Path $Global:PerfTestEnv.LogsPath "single_thread_test.log"
            $singleThreadExecution = Measure-TestExecution -ScriptBlock {
                Start-HashSmithFileProcessing -Files $using:testFiles -LogPath $using:singleThreadLog -Algorithm "SHA256" -MaxThreads 1
            }
            
            # Test with multiple threads
            $multiThreadLog = Join-Path $Global:PerfTestEnv.LogsPath "multi_thread_test.log"
            $multiThreadExecution = Measure-TestExecution -ScriptBlock {
                Start-HashSmithFileProcessing -Files $using:testFiles -LogPath $using:multiThreadLog -Algorithm "SHA256" -MaxThreads 4 -UseParallel
            }
            
            # Assert
            $singleThreadExecution.Success | Should -Be $true
            $multiThreadExecution.Success | Should -Be $true
            
            # Multi-threading should provide some improvement (though not necessarily linear)
            $improvementRatio = $singleThreadExecution.Duration.TotalSeconds / $multiThreadExecution.Duration.TotalSeconds
            
            Write-Host "✅ Threading Improvement: ${improvementRatio}x speedup" -ForegroundColor Green
            
            # Should see at least some improvement with multiple threads
            $improvementRatio | Should -BeGreaterThan 1.1  # At least 10% improvement
        }
    }
    
    Context "Memory Usage Performance" {
        
        It "Should maintain reasonable memory usage during large operations" {
            # Arrange
            $initialMemory = [System.GC]::GetTotalMemory($false)
            $testFiles = @()
            $fileCount = 100
            
            # Create many small files
            for ($i = 1; $i -le $fileCount; $i++) {
                $fileName = "memory_test_$i.txt"
                $filePath = Join-Path $Global:PerfTestEnv.DataPath $fileName
                "Test content for memory usage testing - file $i" * 50 | Set-Content -Path $filePath
                $testFiles += Get-Item $filePath
            }
            
            $testLogPath = Join-Path $Global:PerfTestEnv.LogsPath "memory_test.log"
            
            # Act
            $result = Start-HashSmithFileProcessing -Files $testFiles -LogPath $testLogPath -Algorithm "MD5" -MaxThreads 2
            
            # Force garbage collection and measure
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            [System.GC]::Collect()
            
            $finalMemory = [System.GC]::GetTotalMemory($false)
            $memoryIncreaseMB = ($finalMemory - $initialMemory) / 1MB
            
            # Assert
            $result.Keys.Count | Should -Be $fileCount
            $memoryIncreaseMB | Should -BeLessOrEqual $Global:PerformanceConfig.MaxMemoryUsageMB
            
            Write-Host "✅ Memory Usage: $($memoryIncreaseMB.ToString('F1')) MB increase" -ForegroundColor Green
        }
        
        It "Should efficiently handle directory integrity computation for large file sets" {
            # Arrange
            $fileHashes = @{}
            $fileCount = 1000
            
            # Create simulated file hash collection
            for ($i = 1; $i -le $fileCount; $i++) {
                $fileName = "integrity_test_file_$i.txt"
                $hash = [System.Guid]::NewGuid().ToString("N")  # Simulate hash
                $size = Get-Random -Minimum 1KB -Maximum 1MB
                
                $fileHashes[$fileName] = @{
                    Hash = $hash
                    Size = $size
                }
            }
            
            # Act
            $execution = Measure-TestExecution -ScriptBlock {
                Get-HashSmithDirectoryIntegrityHash -FileHashes $using:fileHashes -Algorithm "SHA256"
            }
            
            # Assert
            $execution.Success | Should -Be $true
            $execution.Result.FileCount | Should -Be $fileCount
            $execution.Duration.TotalSeconds | Should -BeLessOrEqual 10  # Should be reasonably fast
            
            if ($execution.Result.Metadata.FilesPerSecond) {
                $execution.Result.Metadata.FilesPerSecond | Should -BeGreaterThan 100
                Write-Host "✅ Directory Integrity: $($execution.Result.Metadata.FilesPerSecond) files/sec" -ForegroundColor Green
            }
        }
    }
    
    Context "Stress Testing" {
        
        It "Should handle sustained load without degradation" -Skip:($Global:PerformanceConfig.MaxTestDuration.TotalMinutes -lt 5) {
            # Arrange
            $testFiles = @()
            $stressTestDir = Join-Path $Global:PerfTestEnv.DataPath "StressTest"
            New-Item -Path $stressTestDir -ItemType Directory -Force | Out-Null
            
            # Create moderate number of varied-size files
            for ($i = 1; $i -le 50; $i++) {
                $fileName = "stress_file_$i.bin"
                $filePath = Join-Path $stressTestDir $fileName
                $fileSize = Get-Random -Minimum 1KB -Maximum 1MB
                $testData = [byte[]]::new($fileSize)
                [System.Random]::new($i).NextBytes($testData)
                [System.IO.File]::WriteAllBytes($filePath, $testData)
                $testFiles += Get-Item $filePath
            }
            
            $testLogPath = Join-Path $Global:PerfTestEnv.LogsPath "stress_test.log"
            $iterations = 3
            $durations = @()
            
            # Act - Run multiple iterations
            for ($iteration = 1; $iteration -le $iterations; $iteration++) {
                Write-Host "Stress test iteration $iteration of $iterations..." -ForegroundColor Yellow
                
                $execution = Measure-TestExecution -ScriptBlock {
                    Start-HashSmithFileProcessing -Files $using:testFiles -LogPath "$using:testLogPath.$using:iteration" -Algorithm "SHA256" -MaxThreads 2
                }
                
                $execution.Success | Should -Be $true
                $durations += $execution.Duration.TotalSeconds
            }
            
            # Assert - Performance should remain consistent
            $avgDuration = ($durations | Measure-Object -Average).Average
            $maxDeviation = ($durations | ForEach-Object { [Math]::Abs($_ - $avgDuration) } | Measure-Object -Maximum).Maximum
            $deviationPercent = ($maxDeviation / $avgDuration) * 100
            
            # Performance shouldn't degrade by more than 50% across iterations
            $deviationPercent | Should -BeLessOrEqual 50
            
            Write-Host "✅ Stress Test: Avg $($avgDuration.ToString('F1'))s, Max deviation $($deviationPercent.ToString('F1'))%" -ForegroundColor Green
        }
        
        It "Should recover gracefully from resource constraints" {
            # Arrange - Create scenario that might stress memory/handles
            $testFiles = @()
            $constraintTestDir = Join-Path $Global:PerfTestEnv.DataPath "ConstraintTest"
            New-Item -Path $constraintTestDir -ItemType Directory -Force | Out-Null
            
            # Create many small files
            for ($i = 1; $i -le 500; $i++) {
                $fileName = "constraint_file_$i.txt"
                $filePath = Join-Path $constraintTestDir $fileName
                "Content $i" | Set-Content -Path $filePath
                $testFiles += Get-Item $filePath
            }
            
            $testLogPath = Join-Path $Global:PerfTestEnv.LogsPath "constraint_test.log"
            
            # Act - Process with limited resources
            $execution = Measure-TestExecution -ScriptBlock {
                Start-HashSmithFileProcessing -Files $using:testFiles -LogPath $using:testLogPath -Algorithm "MD5" -MaxThreads 1 -ChunkSize 10 -TimeoutSeconds 5
            }
            
            # Assert - Should complete successfully even under constraints
            $execution.Success | Should -Be $true
            $execution.Result.Keys.Count | Should -BeGreaterThan ($testFiles.Count * 0.8)  # At least 80% success rate
            
            # Should complete in reasonable time even with constraints
            $execution.Duration.TotalMinutes | Should -BeLessOrEqual 5
            
            Write-Host "✅ Constraint Recovery: $($execution.Result.Keys.Count)/$($testFiles.Count) files processed" -ForegroundColor Green
        }
    }
}

Describe "HashSmith Benchmark Tests" -Tag "Benchmark", "Performance" {
    
    Context "Baseline Performance Benchmarks" {
        
        It "Should establish hash computation baselines" {
            # Arrange
            $benchmarkSizes = @(1KB, 10KB, 100KB, 1MB)
            $algorithms = @('MD5', 'SHA256')
            $results = @{}
            
            foreach ($algorithm in $algorithms) {
                $results[$algorithm] = @{}
                
                foreach ($size in $benchmarkSizes) {
                    # Create test file
                    $testFile = Join-Path $Global:PerfTestEnv.DataPath "benchmark_${algorithm}_${size}.bin"
                    $testData = [byte[]]::new($size)
                    [System.Random]::new(42).NextBytes($testData)
                    [System.IO.File]::WriteAllBytes($testFile, $testData)
                    
                    # Benchmark hash computation
                    $execution = Measure-TestExecution -ScriptBlock {
                        Get-HashSmithFileHashSafe -Path $using:testFile -Algorithm $using:algorithm
                    }
                    
                    $execution.Success | Should -Be $true
                    $execution.Result.Success | Should -Be $true
                    
                    $throughputMBps = if ($execution.Duration.TotalSeconds -gt 0) {
                        ($size / 1MB) / $execution.Duration.TotalSeconds
                    } else {
                        999  # Very fast
                    }
                    
                    $results[$algorithm][$size] = @{
                        Duration = $execution.Duration
                        ThroughputMBps = $throughputMBps
                    }
                    
                    Write-Host "📊 $algorithm ${size}B: $($execution.Duration.TotalMilliseconds)ms ($($throughputMBps.ToString('F1')) MB/s)" -ForegroundColor Cyan
                }
            }
            
            # Assert - Store baseline results for comparison
            $Global:HashSmithBenchmarks = $results
            $results | Should -Not -BeNullOrEmpty
        }
        
        It "Should establish file discovery baselines" {
            # Arrange
            $directorySizes = @(100, 500, 1000)
            $results = @{}
            
            foreach ($fileCount in $directorySizes) {
                $testDir = New-TestDirectory -Prefix "DiscoveryBenchmark$fileCount"
                
                # Create files
                for ($i = 1; $i -le $fileCount; $i++) {
                    $fileName = "file_$($i.ToString('D4')).txt"
                    $filePath = Join-Path $testDir $fileName
                    "Content $i" | Set-Content -Path $filePath
                }
                
                # Benchmark discovery
                $execution = Measure-TestExecution -ScriptBlock {
                    Get-HashSmithAllFiles -Path $using:testDir
                }
                
                $execution.Success | Should -Be $true
                $execution.Result.Files.Count | Should -Be $fileCount
                
                $filesPerSecond = $fileCount / $execution.Duration.TotalSeconds
                $results[$fileCount] = @{
                    Duration = $execution.Duration
                    FilesPerSecond = $filesPerSecond
                }
                
                Write-Host "📊 Discovery $fileCount files: $($execution.Duration.TotalSeconds)s ($($filesPerSecond.ToString('F1')) files/s)" -ForegroundColor Cyan
                
                # Cleanup
                Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
            
            $Global:DiscoveryBenchmarks = $results
            $results | Should -Not -BeNullOrEmpty
        }
    }
}
# 🔐 HashSmith - Enterprise File Integrity Verification System

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue)](https://github.com/PowerShell/PowerShell)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)
[![Version](https://img.shields.io/badge/Version-4.1.0-orange)](CHANGELOG.md)

> **The bulletproof solution for enterprise file integrity verification and forensic auditing.**

HashSmith is a production-ready PowerShell system that guarantees complete file discovery and generates cryptographic hashes for entire directory trees. Built for enterprises that demand **zero tolerance for missing files** and **forensic-grade verification**.

## 🚀 Why HashSmith?

**Stop worrying about incomplete file audits.** Traditional tools miss files, skip symbolic links, or fail silently on locked files. HashSmith was engineered to eliminate these blind spots:

- ✅ **100% File Discovery Guarantee** - Advanced .NET APIs ensure no files are missed
- ⚡ **Industrial-Grade Performance** - Parallel processing with intelligent load balancing
- 🛡️ **Race Condition Protection** - Detects file changes during processing
- 🔄 **Bulletproof Resume** - Restart from exactly where you left off
- 📊 **Forensic Audit Trails** - Comprehensive logging with structured JSON output
- 🌐 **Enterprise Network Support** - Handles UNC paths, long paths, and Unicode filenames
- 🎯 **Zero Configuration** - Works out-of-the-box with intelligent defaults

## 📋 Table of Contents

- [Quick Start](#-quick-start)
- [Installation](#-installation)
- [Usage Examples](#-usage-examples)
- [Configuration Reference](#-configuration-reference)
- [Performance Tuning](#-performance-tuning)
- [Troubleshooting](#-troubleshooting)
- [Enterprise Features](#-enterprise-features)
- [Contributing](#-contributing)
- [License](#-license)

## 🏃 Quick Start

```powershell
# Basic usage - hash all files in a directory
.\Scripts\Start-HashSmith.ps1 -SourceDir "C:\Data" -HashAlgorithm SHA256

# Enterprise audit with full logging
.\Scripts\Start-HashSmith.ps1 -SourceDir "\\server\share" -StrictMode -UseJsonLog -VerifyIntegrity

# Resume interrupted operation
.\Scripts\Start-HashSmith.ps1 -SourceDir "C:\Data" -Resume

# Retry only failed files
.\Scripts\Start-HashSmith.ps1 -SourceDir "C:\Data" -FixErrors
```

**That's it!** HashSmith handles the complexity while you get reliable results.

## 💾 Installation

### Prerequisites
- **PowerShell 5.1** or higher (PowerShell 7+ recommended for optimal performance)
- **Windows 10/11** or **Windows Server 2016+**
- **.NET Framework 4.7.2** or higher

### Quick Install
```powershell
# Clone the repository
git clone https://github.com/jonasyr/hashsmith.git
cd hashsmith

# Test installation
.\Scripts\Start-HashSmith.ps1 -SourceDir "C:\Windows\System32\drivers\etc" -WhatIf
```

### Deployment Options

#### Option 1: Standalone Deployment
```powershell
# Copy HashSmith to your scripts directory
xcopy /E /I hashsmith C:\Scripts\HashSmith

# Add to PATH (optional)
$env:PATH += ";C:\Scripts\HashSmith\Scripts"
```

#### Option 2: PowerShell Gallery (Future)
```powershell
# Coming soon to PowerShell Gallery
Install-Module -Name HashSmith -Scope AllUsers
```

#### Option 3: Enterprise MSI Package
Contact your IT administrator for the enterprise MSI package with GPO deployment support.

## 🎯 Usage Examples

### Basic File Integrity Verification
```powershell
# Hash all files with MD5 (fastest)
.\Scripts\Start-HashSmith.ps1 -SourceDir "C:\Data"

# Use SHA256 for security compliance
.\Scripts\Start-HashSmith.ps1 -SourceDir "C:\Data" -HashAlgorithm SHA256
```

### Enterprise Scenarios

#### Forensic Audit with Maximum Security
```powershell
.\Scripts\Start-HashSmith.ps1 `
    -SourceDir "\\evidence-server\case-001" `
    -HashAlgorithm SHA512 `
    -StrictMode `
    -VerifyIntegrity `
    -UseJsonLog `
    -IncludeHidden $true `
    -TestMode
```

#### Large-Scale Data Migration Verification
```powershell
# Before migration
.\Scripts\Start-HashSmith.ps1 -SourceDir "\\old-server\data" -LogFile "C:\Audits\pre-migration.log"

# After migration
.\Scripts\Start-HashSmith.ps1 -SourceDir "\\new-server\data" -LogFile "C:\Audits\post-migration.log"

# Compare the TotalMD5 values to verify integrity
```

#### Network Share Monitoring
```powershell
# Daily integrity check with resume capability
.\Scripts\Start-HashSmith.ps1 `
    -SourceDir "\\fileserver\shared-data" `
    -Resume `
    -LogFile "\\audit-server\logs\daily-integrity-$(Get-Date -Format 'yyyyMMdd').log" `
    -UseJsonLog
```

#### Handling Locked Files and Errors
```powershell
# Initial scan (some files may be locked)
.\Scripts\Start-HashSmith.ps1 -SourceDir "C:\Users" -LogFile "C:\Audits\users.log"

# Retry failed files during maintenance window
.\Scripts\Start-HashSmith.ps1 -SourceDir "C:\Users" -FixErrors
```

## ⚙️ Configuration Reference

### Core Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `SourceDir` | String | **Required** | Directory to process |
| `LogFile` | String | Auto-generated | Output log file path |
| `HashAlgorithm` | String | `MD5` | Hash algorithm: MD5, SHA1, SHA256, SHA512 |
| `Resume` | Switch | False | Resume from existing log |
| `FixErrors` | Switch | False | Retry only failed files |

### Performance Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `MaxThreads` | Int | CPU cores | Maximum parallel threads |
| `ChunkSize` | Int | 1000 | Files per processing batch |
| `TimeoutSeconds` | Int | 30 | File operation timeout |
| `ProgressTimeoutMinutes` | Int | 120 | No-progress timeout for large files |
| `UseParallel` | Switch | Auto | Force parallel processing |

### Security & Compliance

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `StrictMode` | Switch | False | Maximum validation and error checking |
| `VerifyIntegrity` | Switch | False | Verify files before/after processing |
| `IncludeHidden` | Bool | True | Include hidden and system files |
| `IncludeSymlinks` | Bool | False | Include symbolic links (security risk) |
| `TestMode` | Switch | False | Extensive validation with cross-checks |

### Output & Logging

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `UseJsonLog` | Switch | False | Generate structured JSON output |
| `ShowProgress` | Switch | False | Detailed progress information |
| `ExcludePatterns` | String[] | Empty | Wildcard patterns to exclude |
| `SortFilesBySize` | Switch | False | Process smaller files first |

### Advanced Configuration

```powershell
# Custom exclusion patterns
$excludePatterns = @("*.tmp", "*.log", "Thumbs.db", ".DS_Store")
.\Scripts\Start-HashSmith.ps1 -SourceDir "C:\Data" -ExcludePatterns $excludePatterns

# Performance tuning for SSD storage
.\Scripts\Start-HashSmith.ps1 `
    -SourceDir "C:\Data" `
    -MaxThreads 16 `
    -ChunkSize 2000 `
    -TimeoutSeconds 60

# Ultra-secure forensic mode
.\Scripts\Start-HashSmith.ps1 `
    -SourceDir "\\evidence\case" `
    -HashAlgorithm SHA512 `
    -StrictMode `
    -VerifyIntegrity `
    -TestMode `
    -IncludeHidden $true `
    -IncludeSymlinks $false `
    -UseJsonLog
```

## ⚡ Performance Tuning

### Hardware Recommendations

| Scenario | CPU Cores | RAM | Storage | Network |
|----------|-----------|-----|---------|---------|
| Small office (< 100,000 files) | 4+ cores | 8 GB | SSD preferred | 1 Gbps |
| Enterprise (< 1M files) | 8+ cores | 16 GB | NVMe SSD | 10 Gbps |
| Large-scale (> 1M files) | 16+ cores | 32 GB | NVMe RAID | 25 Gbps |

### Performance Optimization

#### For SSD Storage
```powershell
# Increase parallelism and chunk size
-MaxThreads 16 -ChunkSize 2000
```

#### For Network Shares
```powershell
# Reduce parallelism to avoid network saturation
-MaxThreads 4 -ChunkSize 500 -TimeoutSeconds 60
```

#### For Very Large Files (>10 GB)
```powershell
# Enable size-based sorting for better progress indication
-SortFilesBySize -TimeoutSeconds 120
```

#### For Extremely Large Files (>50 GB)
```powershell
# Extended timeout for massive files that may take hours to hash
-ProgressTimeoutMinutes 480 -TimeoutSeconds 300
```

### Expected Performance

| File Type | Throughput | Notes |
|-----------|------------|-------|
| Small files (<1 MB) | 15 files/sec/thread | Limited by file I/O overhead |
| Medium files (1-100 MB) | 25 MB/sec/thread | Balanced I/O and CPU |
| Large files (>100 MB) | 40 MB/sec/thread | CPU-bound hash computation |
| Network shares | 50% of local performance | Network latency dependent |

## 🔧 Troubleshooting

### Common Issues

#### "Access Denied" Errors
```powershell
# Run as Administrator for system files
# Or exclude protected directories
-ExcludePatterns @("C:\Windows\System32\config\*", "C:\pagefile.sys")
```

#### Network Connectivity Issues
```powershell
# HashSmith automatically tests network paths
# Check the log for network connectivity messages
# Consider using -StrictMode for network resilience
```

#### Memory Issues with Large Directories
```powershell
# Reduce chunk size to lower memory usage
-ChunkSize 500

# Enable file size sorting
-SortFilesBySize
```

#### Locked Files During Business Hours
```powershell
# Use Resume functionality for incremental processing
.\Scripts\Start-HashSmith.ps1 -SourceDir "C:\Data" -Resume

# Schedule during maintenance windows
# Or use -FixErrors to retry specific files
```

### Log Analysis

#### Text Log Format
```
C:\Data\file.txt = a1b2c3d4e5f6..., size: 1024
C:\Data\error.txt = ERROR(IO): The process cannot access the file, size: 2048
TotalMD5 = final_directory_hash
```

#### JSON Log Structure
```json
{
  "Version": "4.1.0",
  "Configuration": { ... },
  "Statistics": {
    "FilesProcessed": 1000,
    "FilesError": 2,
    "BytesProcessed": 1073741824
  },
  "DirectoryHash": {
    "Hash": "a1b2c3d4...",
    "FileCount": 1000,
    "TotalSize": 1073741824
  }
}
```

### Getting Help

1. **Check the JSON log** for detailed error information
2. **Enable -StrictMode** for maximum validation
3. **Use -TestMode** to verify file discovery completeness
4. **Review network connectivity** for UNC paths
5. **Verify permissions** for protected directories

## 🏢 Enterprise Features

### Audit Trail Compliance
- **Immutable logs** with atomic write operations
- **Structured JSON output** for SIEM integration
- **Comprehensive error tracking** with categorization
- **Race condition detection** for forensic integrity

### Integration Ready
- **PowerShell remoting** support for centralized execution
- **Exit codes** for automation and monitoring
- **JSON output** for database import and reporting
- **Resume capability** for scheduled maintenance windows

### Security Features
- **File integrity verification** before and after processing
- **Symbolic link detection** and configurable handling
- **Circuit breaker pattern** for resilient operations
- **Network path validation** with automatic retry

## 🧪 Testing Framework

### Unit Testing with Pester
```powershell
# Install Pester testing framework
Install-Module -Name Pester -Force -SkipPublisherCheck

# Run HashSmith tests
Invoke-Pester -Path .\Tests\ -OutputFormat NUnitXml -OutputFile TestResults.xml
```

### Example Test Cases
```powershell
Describe "HashSmith Core Functionality" {
    It "Should compute correct MD5 for known file" {
        $result = Get-HashSmithFileHashSafe -Path "test.txt" -Algorithm "MD5"
        $result.Hash | Should -Be "5d41402abc4b2a76b9719d911017c592"
    }
    
    It "Should handle locked files gracefully" {
        $result = Get-HashSmithFileHashSafe -Path "locked.txt" -Algorithm "MD5"
        $result.Success | Should -Be $false
        $result.ErrorCategory | Should -Be "IO"
    }
}
```

## 🚀 Business Context & Enterprise Enhancements

### Current Business Value
HashSmith addresses critical enterprise needs:
- **Compliance reporting** for SOX, GDPR, HIPAA
- **Data migration verification** with zero tolerance for errors
- **Forensic evidence integrity** for legal proceedings
- **Change detection** for security monitoring

### Recommended Enterprise Enhancements

#### 1. Reporting Dashboard & Analytics
```powershell
# Azure Function integration for real-time reporting
# PowerBI dashboards for trend analysis
# Automated compliance reports
```

#### 2. SIEM Integration
```powershell
# Splunk/ElasticSearch connectors
# Real-time alerting for integrity violations
# Automated incident response workflows
```

#### 3. CI/CD Pipeline Integration
```powershell
# Azure DevOps task for build verification
# GitHub Actions for repository integrity
# Automated regression testing
```

### Extension Ideas

#### Extension 1: Azure Function Wrapper
Transform HashSmith into a serverless solution:

```typescript
// Azure Function wrapper for HashSmith
export async function hashSmithTrigger(context: Context, req: HttpRequest) {
    const { sourcePath, algorithm } = req.body;
    
    // Execute HashSmith via PowerShell Core
    const result = await execPowerShell(`
        Import-Module ./HashSmith
        Start-HashSmith -SourceDir "${sourcePath}" -Algorithm "${algorithm}" -UseJsonLog
    `);
    
    // Store results in Azure Storage/CosmosDB
    await storeResults(result);
    
    return {
        status: 200,
        body: result
    };
}
```

**Business Benefits:**
- **Serverless scaling** for large enterprises
- **Cost optimization** with pay-per-use model
- **Global deployment** across Azure regions
- **Integration** with Azure Security Center

#### Extension 2: Cross-Platform Container Solution
Create a containerized version supporting Linux/macOS:

```dockerfile
FROM mcr.microsoft.com/powershell:7.4-ubuntu-20.04

# Install HashSmith
COPY . /app/HashSmith
WORKDIR /app/HashSmith

# Create entrypoint
COPY docker-entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
```

```bash
#!/bin/bash
# docker-entrypoint.sh
pwsh -Command "& './Scripts/Start-HashSmith.ps1' $@"
```

**Usage:**
```bash
# Run HashSmith in Docker
docker run -v /data:/data hashsmith -SourceDir "/data" -Algorithm SHA256

# Kubernetes deployment for enterprise scale
kubectl apply -f hashsmith-cronjob.yaml
```

**Business Benefits:**
- **Multi-platform support** (Windows, Linux, macOS)
- **Kubernetes orchestration** for enterprise scale
- **Microservices architecture** integration
- **Cloud-native deployment** patterns

#### Extension 3: Real-Time Monitoring Service
Continuous file system monitoring with HashSmith integration:

```powershell
# File System Watcher integration
class HashSmithMonitor {
    [FileSystemWatcher] $Watcher
    [Queue] $ChangeQueue
    
    HashSmithMonitor([string] $Path) {
        $this.Watcher = New-Object FileSystemWatcher $Path
        $this.Watcher.IncludeSubdirectories = $true
        $this.Watcher.EnableRaisingEvents = $true
        
        # Register event handlers
        Register-ObjectEvent $this.Watcher "Created" -Action { 
            $this.QueueVerification($Event.SourceEventArgs.FullPath)
        }
    }
    
    [void] QueueVerification([string] $FilePath) {
        # Queue file for integrity verification
        $this.ChangeQueue.Enqueue(@{
            Path = $FilePath
            Timestamp = Get-Date
            Action = "Verify"
        })
    }
}
```

**Business Benefits:**
- **Real-time integrity monitoring** for critical systems
- **Automated incident response** for security events
- **Compliance automation** for regulatory requirements
- **Proactive threat detection** capabilities

## 🤝 Contributing

We welcome contributions! HashSmith is built for the enterprise community.

### Development Setup
```powershell
# Clone and setup development environment
git clone https://github.com/jonasyr/hashsmith.git
cd hashsmith

# Install development dependencies
Install-Module -Name Pester, PSScriptAnalyzer, platyPS

# Run linting and tests
Invoke-ScriptAnalyzer -Path .\Scripts\ -Recurse
Invoke-Pester -Path .\Tests\
```

### Contribution Guidelines
1. **Follow PowerShell best practices** and use PSScriptAnalyzer
2. **Add comprehensive tests** for new functionality
3. **Update documentation** for API changes
4. **Test on multiple environments** (PowerShell 5.1 and 7+)
5. **Maintain backward compatibility** for enterprise deployments

### Reporting Issues
- **Security vulnerabilities**: Contact security@yourorg.com
- **Bug reports**: Use GitHub Issues with reproduction steps
- **Feature requests**: Include business justification and use cases

## 📄 License

HashSmith is licensed under the MIT License. See [LICENSE](LICENSE) for details.

**Enterprise License:** For commercial support, training, and enterprise features, contact enterprise@yourorg.com.

---
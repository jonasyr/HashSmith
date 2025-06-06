# HashSmith

HashSmith is an enterprise-grade, thread-safe checksum generator designed to compute file hashes (MD5, SHA1, SHA256, SHA384, SHA512) at scale. It features parallel processing, intelligent retry mechanisms, resume functionality, “fix errors” mode, exclusion patterns, long-path support, and structured JSON logging for auditing and monitoring.

---

## Table of Contents

1. [Features](#features)
2. [Prerequisites](#prerequisites)
3. [Installation](#installation)
4. [Usage](#usage)

   * 4.1 [Basic Invocation](#basic-invocation)
   * 4.2 [Resume Mode](#resume-mode)
   * 4.3 [Fix Errors Mode](#fix-errors-mode)
   * 4.4 [Excluding Files](#excluding-files)
   * 4.5 [Preview Mode (WhatIf)](#preview-mode-whatif)
5. [Parameters](#parameters)
6. [Logging & Output](#logging--output)
7. [Examples](#examples)
8. [Best Practices](#best-practices)
9. [License](#license)

---

## Features

* **Parallel Processing:** Utilizes multiple threads (up to CPU cores × 2 by default) for high throughput.
* **Thread Safety:** Atomic log writes and console progress updates using mutexes.
* **Multiple Hash Algorithms:** Supports MD5, SHA1, SHA256, SHA384, and SHA512.
* **Robust Retry Mechanism:** Automatic exponential backoff for transient I/O or lock-related errors.
* **Resume Functionality:** Skip already processed files by analyzing an existing log.
* **Fix Errors Mode:** Re-compute failed entries without re-hashing successful files.
* **Exclude Patterns:** Filter out files by wildcard patterns (e.g., `*.tmp`, `*.bak`).
* **Long Path Support:** Handles paths longer than 260 characters transparently.
* **Structured JSON Logging:** Each entry is a single-line JSON object for easy ingestion by SIEM or log-analytics.
* **Adaptive Batch Sizing:** Dynamically calculates optimal batch size based on total file count, total size, and thread count.
* **Comprehensive Error Recovery:** Captures and logs any failures, providing context (file size, attempts, method).
* **Preview Mode (`-WhatIf`):** Estimate file counts, batches, and resource usage without hashing.
* **Silent Mode (`-Silent`):** Suppress progress bars and verbose output for automation pipelines.

---

## Prerequisites

* Windows PowerShell 5.1 or higher (PowerShell 7.x+ recommended for true parallelism).
* .NET Framework 4.7.2 (or later) for cryptographic APIs.
* (Optional) An external MD5 tool (e.g., `MD5-x64.exe`) if you wish to offload MD5 computation to a native binary.
* At least **256 MB** of free memory, though **1 GB** (1024 MB) is recommended for large datasets.
* Sufficient file system permissions to read source files and write to the log file.

---

## Installation

1. **Clone the repository:**

   ```powershell
   git clone https://github.com/YourOrg/HashSmith.git
   cd HashSmith
   ```

2. **Unblock the script (if blocked):**

   ```powershell
   Unblock-File .\HashSmith.ps1
   ```

3. **(Optional) Place an external MD5 executable** in a known location or rely on the built-in PowerShell hashing.

---

## Usage

### Basic Invocation

```powershell
.\HashSmith.ps1 -SourceDir "C:\Data"
```

* **Default Behavior:**

  * Uses MD5 algorithm.
  * Creates a log file next to `C:\Data` with a timestamp.
  * Spawns up to `(CPU cores × 2)` parallel threads (if PowerShell 7+).

### Resume Mode

Continue a previously interrupted run without re-hashing successful files:

```powershell
.\HashSmith.ps1 -SourceDir "C:\Data" -Resume
```

* Scans the existing log, skips successfully hashed files, and only processes missing or failed ones.

### Fix Errors Mode

Re-compute only those entries that previously failed:

```powershell
.\HashSmith.ps1 -SourceDir "C:\Data" -LogFile "C:\Logs\data_20250606_MD5.log" -FixErrors
```

* Requires a valid log at `C:\Logs\data_20250606_MD5.log`.
* Any files that no longer exist are skipped with a warning.

### Excluding Files

Exclude certain patterns (e.g., temporary or backup files):

```powershell
.\HashSmith.ps1 -SourceDir "C:\Data" -ExcludePatterns "*.tmp", "*.bak"
```

* All files matching `*.tmp` or `*.bak` under `C:\Data` (recursively) are skipped.

### Preview Mode (WhatIf)

Preview how many files would be processed, estimated batches, total size, and thread configuration:

```powershell
.\HashSmith.ps1 -SourceDir "C:\Data" -WhatIf
```

* No hashing takes place—only displays metrics.

---

## Parameters

| Parameter           | Type       | Required | Default                       | Description                                                                                                                |
| ------------------- | ---------- | -------- | ----------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| **SourceDir**       | `string`   | Yes      | N/A                           | Path to the directory containing files to hash. Must exist and be safe (no path traversal).                                |
| **LogFile**         | `string`   | No       | Auto-generated in parent path | Full path to the JSON log. If omitted, a file named `<folder>_<YYYYMMDD_HHMMSS>_<Algo>.log` will be created automatically. |
| **MD5Tool**         | `string`   | No       | Auto-detected if available    | Path to an external MD5 executable. Used only when `-HashAlgorithm MD5` and file is accessible by the tool.                |
| **HashAlgorithm**   | `string`   | No       | `MD5`                         | Hash algorithm to use. Valid options: `MD5`, `SHA1`, `SHA256`, `SHA384`, `SHA512`.                                         |
| **Resume**          | `switch`   | No       | `$false`                      | Skip files already successfully hashed in an existing log.                                                                 |
| **FixErrors**       | `switch`   | No       | `$false`                      | Only re-hash previously failed entries. Requires an existing log file.                                                     |
| **ExcludePatterns** | `string[]` | No       | `@()`                         | Wildcard patterns to exclude (e.g., `*.tmp`).                                                                              |
| **MaxThreads**      | `int`      | No       | `(CPU cores × 2)`             | Maximum number of parallel threads. Valid range: 1 – 64.                                                                   |
| **BatchSize**       | `int`      | No       | `0`                           | Number of files per batch. `0` means let the script compute an optimal size between 10 and 500.                            |
| **RetryAttempts**   | `int`      | No       | `3`                           | How many times to retry transient hashing errors.                                                                          |
| **LogLevel**        | `string`   | No       | `Info`                        | Verbosity level. Options: `Error`, `Warning`, `Info`, `Debug`.                                                             |
| **WhatIf**          | `switch`   | No       | `$false`                      | Preview mode – calculate stats but do not process hashes.                                                                  |
| **Silent**          | `switch`   | No       | `$false`                      | Suppress console output (logs still write to file).                                                                        |

---

## Logging & Output

* **Log Format:**

  * The first line is a header comment containing metadata in compressed JSON. E.g.:

    ```text
    # MD5 Checksum Log - {"LogVersion":"2.0","CreatedDate":"2025-06-06 12:34:56.789","SourceDirectory":"\\?\C:\Data",…}
    ```
  * Every subsequent line is a compact, single-line JSON object:

    ```jsonc
    {
      "Timestamp": "2025-06-06 12:35:00.123",
      "Level": "Info",
      "ThreadId": 12,
      "ProcessId": 3456,
      "Message": "Hash computed: report.pdf",
      "Data": {
        "FilePath": "\\?\\C:\\Data\\report.pdf",
        "Hash": "5d41402abc4b2a76b9719d911017c592",
        "Algorithm": "MD5",
        "Success": true,
        "Error": null,
        "FileSize": 123456,
        "ProcessingTime": 45,
        "Method": "PowerShell",
        "Attempts": 1
      }
    }
    ```
* **Error Entries:**

  * If hashing fails, Level = `Error`, `Data.Success` is `false`, and `Data.Error` contains the exception message.
* **Resume Logic:**

  * During resume, the script reads all previous successful entries (`Data.Success == true && Data.Hash != null`) and skips those file paths.
* **FixErrors Logic:**

  * The script collects all failed entries (`Data.Success == false`) and re-attempts hashing only those files.

---

## Examples

1. **Generate MD5 for all files under `D:\Archives`:**

   ```powershell
   .\HashSmith.ps1 -SourceDir "D:\Archives" -LogLevel Info
   ```

   * Creates `Archives_<timestamp>_MD5.log` in `D:\`.

2. **Use SHA256 and limit to 8 threads:**

   ```powershell
   .\HashSmith.ps1 -SourceDir "D:\Archives" -HashAlgorithm SHA256 -MaxThreads 8
   ```

3. **Automatically detect an external MD5 tool:**

   ```powershell
   # Place MD5-x64.exe in C:\Tools\
   .\HashSmith.ps1 -SourceDir "C:\BigData" -LogFile "C:\Logs\bigdata.md5"
   ```

4. **Resume an interrupted job:**

   ```powershell
   .\HashSmith.ps1 -SourceDir "C:\BigData" -Resume -LogFile "C:\Logs\bigdata_20250605_MD5.log"
   ```

5. **Fix only failed entries using SHA1:**

   ```powershell
   .\HashSmith.ps1 -SourceDir "C:\Backups" -HashAlgorithm SHA1 -LogFile "C:\Logs\backups_20250604_SHA1.log" -FixErrors
   ```

6. **Exclude temporary files and run silently:**

   ```powershell
   .\HashSmith.ps1 -SourceDir "C:\Projects" -ExcludePatterns "*.tmp","*.log" -Silent
   ```

7. **Preview without executing:**

   ```powershell
   .\HashSmith.ps1 -SourceDir "C:\Media" -WhatIf
   ```

---

## Best Practices

1. **Run on PowerShell 7+ when possible.**

   * True parallelism (`ForEach-Object -Parallel`) only works in PowerShell Core (7.0+).
   * If running on Windows PowerShell 5.1, the script will gracefully fall back to sequential mode.

2. **Choose an appropriate `BatchSize`.**

   * For large numbers of tiny files (< 10 KB each), let the script compute a large batch (up to 200).
   * For very large files (> 100 MB), use smaller batches or explicitly set `-BatchSize <n>` to avoid memory spikes.

3. **Monitor `LogLevel=Debug` for troubleshooting.**

   * In case of unclear failures, set `-LogLevel Debug` to capture internal retry decisions and path-conversion errors.

4. **Leverage `-Resume` after interruptions.**

   * If a run is canceled or the machine restarts, simply re-run with `-Resume` and the same `-LogFile`.
   * Only new or previously failed files will be hashed.

5. **Optimize resource usage.**

   * On servers with heavy I/O, limit `-MaxThreads` to prevent disk thrashing.
   * For SSDs or NVMe, you can safely increase threads to `(CPU cores × 2)` or more, but always monitor CPU and disk metrics.

6. **Archive or rotate logs.**

   * Logs can grow quickly in large repositories. Consider rotating logs daily or after major runs.
   * You can compress old logs (e.g., `.gz` or `.zip`) because HashSmith only needs the current log when resuming or fixing errors.

---

## License

This project is licensed under the [MIT License](./LICENSE). See `LICENSE` for full details.

---

**Q1:** **In what scenarios would you prefer using an external MD5 tool over PowerShell’s built-in `Get-FileHash`?**
**Q2:** **How would you integrate HashSmith into a CI/CD pipeline to verify artifact integrity automatically?**
**Q3:** **If you needed to extend HashSmith to support incremental hashing based on file modification timestamps, what design changes would you propose?**

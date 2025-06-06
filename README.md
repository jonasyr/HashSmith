# HashSmith

HashSmith is an enterprise-grade, thread-safe checksum generator designed to compute file hashes (MD5, SHA256, SHA512) at scale. It features parallel processing, intelligent retry mechanisms, resume functionality, "fix errors" mode, exclusion patterns, long-path support, and structured logging for auditing and monitoring.

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
* **Multiple Hash Algorithms:** Supports MD5, SHA256, and SHA512.
* **Robust Retry Mechanism:** Automatic retry with exponential backoff for transient I/O errors.
* **Resume Functionality:** Skip already processed files by analyzing an existing log.
* **Fix Errors Mode:** Re-compute failed entries without re-hashing successful files.
* **Exclude Patterns:** Filter out files by wildcard patterns (e.g., `*.tmp`, `*.bak`).
* **Long Path Support:** Handles paths longer than 260 characters transparently.
* **Optional JSON Logging:** Generate additional JSON format log alongside plain text.
* **Comprehensive Error Recovery:** Captures and logs any failures with detailed error messages.
* **Preview Mode (`-WhatIf`):** Estimate file counts and resource usage without hashing.

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
   git clone https://github.com/jonasyr/HashSmith.git
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
  * Creates a log file in the source directory with a timestamp.
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
.\HashSmith.ps1 -SourceDir "C:\Data" -LogFile "C:\Logs\data_MD5_20250606.log" -FixErrors
```

* Requires a valid log at the specified path.
* Any files that no longer exist are skipped with a warning.

### Excluding Files

Exclude certain patterns (e.g., temporary or backup files):

```powershell
.\HashSmith.ps1 -SourceDir "C:\Data" -ExcludePatterns "*.tmp", "*.bak"
```

* All files matching `*.tmp` or `*.bak` under `C:\Data` (recursively) are skipped.

### Preview Mode (WhatIf)

Preview how many files would be processed and estimated total size:

```powershell
.\HashSmith.ps1 -SourceDir "C:\Data" -WhatIf
```

* No hashing takes place—only displays metrics.

---

## Parameters

| Parameter           | Type       | Required | Default                       | Description                                                                                                                |
| ------------------- | ---------- | -------- | ----------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| **SourceDir**       | `string`   | Yes      | N/A                           | Path to the directory containing files to hash. Must exist and be accessible.                                |
| **LogFile**         | `string`   | No       | Auto-generated in source dir | Full path to the log file. If omitted, a file named `<folder>_<Algo>_<timestamp>.log` will be created automatically. |
| **MD5Tool**         | `string`   | No       | Auto-detected if available    | Path to an external MD5 executable. Used only when `-HashAlgorithm MD5` and file is accessible.                |
| **HashAlgorithm**   | `string`   | No       | `MD5`                         | Hash algorithm to use. Valid options: `MD5`, `SHA256`, `SHA512`.                                         |
| **Resume**          | `switch`   | No       | `$false`                      | Skip files already successfully hashed in an existing log.                                                                 |
| **FixErrors**       | `switch`   | No       | `$false`                      | Only re-hash previously failed entries. Requires an existing log file.                                                     |
| **ExcludePatterns** | `string[]` | No       | `@()`                         | Wildcard patterns to exclude (e.g., `*.tmp`).                                                                              |
| **UseJsonLog**      | `switch`   | No       | `$false`                      | Generate additional JSON format log alongside plain text.                            |
| **MaxThreads**      | `int`      | No       | `(CPU cores × 2)`             | Maximum number of parallel threads. Valid range: 1 – 128.                                                                   |
| **RetryCount**      | `int`      | No       | `3`                           | How many times to retry transient hashing errors. Valid range: 0 – 10.                                                                          |

---

## Logging & Output

* **Log Format:**

  * The log starts with header comments containing metadata:

    ```text
    # Checksum Log Generated by Production-Ready Script v2.0.0
    # Date: 2025-06-06 12:34:56
    # Algorithm: MD5
    # Source: C:\Data
    ```
  * Every subsequent line follows the format:

    ```text
    C:\Data\report.pdf = 5d41402abc4b2a76b9719d911017c592, size: 123456 bytes
    ```
* **Error Entries:**

  * If hashing fails, the format is:

    ```text
    C:\Data\locked.pdf = ERROR: The process cannot access the file, size: 123456 bytes
    ```
* **Resume Logic:**

  * During resume, the script reads all previous successful entries (those with valid hashes) and skips those file paths.
* **FixErrors Logic:**

  * The script collects all failed entries (those with "ERROR:") and re-attempts hashing only those files.

* **Total Hash:**

  * At the end of a successful run, a total hash is computed from all individual hashes:

    ```text
    TotalMD5 = a1b2c3d4e5f6789012345678901234567890abcd
    ```

---

## Examples

1. **Generate MD5 for all files under `D:\Archives`:**

   ```powershell
   .\HashSmith.ps1 -SourceDir "D:\Archives"
   ```

   * Creates `Archives_MD5_<timestamp>.log` in `D:\Archives`.

2. **Use SHA256 and limit to 8 threads:**

   ```powershell
   .\HashSmith.ps1 -SourceDir "D:\Archives" -HashAlgorithm SHA256 -MaxThreads 8
   ```

3. **Use an external MD5 tool:**

   ```powershell
   # Place MD5-x64.exe in C:\Tools\
   .\HashSmith.ps1 -SourceDir "C:\BigData" -MD5Tool "C:\Tools\MD5-x64.exe"
   ```

4. **Resume an interrupted job:**

   ```powershell
   .\HashSmith.ps1 -SourceDir "C:\BigData" -Resume
   ```

5. **Fix only failed entries using SHA512:**

   ```powershell
   .\HashSmith.ps1 -SourceDir "C:\Backups" -HashAlgorithm SHA512 -LogFile "C:\Logs\backups_SHA512_20250604.log" -FixErrors
   ```

6. **Exclude temporary files and generate JSON log:**

   ```powershell
   .\HashSmith.ps1 -SourceDir "C:\Projects" -ExcludePatterns "*.tmp","*.log" -UseJsonLog
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

2. **Monitor resource usage.**

   * On servers with heavy I/O, limit `-MaxThreads` to prevent disk thrashing.
   * For SSDs or NVMe, you can safely increase threads to `(CPU cores × 2)` or more.

3. **Leverage `-Resume` after interruptions.**

   * If a run is canceled or the machine restarts, simply re-run with `-Resume`.
   * Only new or previously failed files will be hashed.

4. **Use `-FixErrors` for reliability.**

   * After a run with errors, use `-FixErrors` to retry only the failed files.
   * This is more efficient than re-running the entire job.

5. **Archive or rotate logs.**

   * Logs can grow quickly in large repositories. Consider archiving completed logs.
   * You can compress old logs because HashSmith only needs the current log when resuming or fixing errors.

---

## License

This project is licensed under the [MIT License](./LICENSE). See `LICENSE` for full details.

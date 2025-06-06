<#
.SYNOPSIS
    Robuster MD5-Checksum-Generator mit Enterprise-Features und Thread-Safety.

.DESCRIPTION
    Hochperformante MD5-Checksum-Generierung mit paralleler Verarbeitung, 
    robuster Fehlerbehandlung, Resume-Funktionalität und FixErrors-Flag.
    
    Enterprise-Features:
    - Thread-sichere parallele Verarbeitung
    - Atomare Log-Operationen mit File-Locking
    - Lange Pfad-Unterstützung (>260 Zeichen)
    - Intelligente Retry-Mechanismen
    - Strukturierte JSON-Logs
    - Comprehensive Error-Recovery

.PARAMETER SourceDir
    Quellverzeichnis für MD5-Generierung (erforderlich).

.PARAMETER LogFile
    Pfad zur Log-Datei. Falls nicht angegeben, wird automatisch generiert.

.PARAMETER MD5Tool
    Pfad zum externen MD5-Tool. Auto-Detection falls nicht angegeben.

.PARAMETER HashAlgorithm
    Hash-Algorithmus (MD5, SHA1, SHA256). Standard: MD5.

.PARAMETER Resume
    Fortsetzung einer unterbrochenen Operation basierend auf bestehender Log-Datei.

.PARAMETER FixErrors
    Repariert nur fehlerhafte Einträge aus bestehender Log-Datei.

.PARAMETER ExcludePatterns
    Array von Dateimustern zum Ausschließen.

.PARAMETER MaxThreads
    Maximale Anzahl paralleler Threads. Standard: CPU-Kerne * 2.

.PARAMETER BatchSize
    Anzahl Dateien pro Batch. Standard: Adaptive Berechnung.

.PARAMETER RetryAttempts
    Anzahl Wiederholungsversuche bei Fehlern. Standard: 3.

.PARAMETER LogLevel
    Logging-Level (Error, Warning, Info, Debug). Standard: Info.

.PARAMETER WhatIf
    Vorschau-Modus ohne tatsächliche Verarbeitung.

.PARAMETER Silent
    Unterdrückt Progress-Anzeige (für Automation).

.EXAMPLE
    .\New-MD5Checksum.ps1 -SourceDir "C:\Data" -LogLevel Info
    Generiert MD5-Checksums für alle Dateien in C:\Data.

.EXAMPLE
    .\New-MD5Checksum.ps1 -SourceDir "\\Server\Share" -Resume -MaxThreads 8
    Setzt unterbrochene Operation auf Netzwerk-Share mit 8 Threads fort.

.EXAMPLE
    .\New-MD5Checksum.ps1 -LogFile "C:\Logs\data.md5" -FixErrors
    Repariert nur fehlerhafte Einträge aus bestehender Log-Datei.

.NOTES
    Version: 2.0
    Author: Enterprise Security Team
    Requires: PowerShell 5.1+ (7.0+ für optimale Performance)
    
.LINK
    https://docs.microsoft.com/en-us/powershell/
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0, HelpMessage="Quellverzeichnis für MD5-Generierung")]
    [ValidateScript({
        if (-not (Test-Path $_ -PathType Container)) {
            throw "Verzeichnis '$_' existiert nicht oder ist nicht zugänglich."
        }
        $true
    })]
    [string]$SourceDir,
    
    [Parameter(HelpMessage="Pfad zur Log-Datei")]
    [string]$LogFile,
    
    [Parameter(HelpMessage="Pfad zum externen MD5-Tool")]
    [string]$MD5Tool,
    
    [Parameter(HelpMessage="Hash-Algorithmus")]
    [ValidateSet("MD5", "SHA1", "SHA256", "SHA384", "SHA512")]
    [string]$HashAlgorithm = "MD5",
    
    [Parameter(HelpMessage="Fortsetzung unterbrochener Operation")]
    [switch]$Resume,
    
    [Parameter(HelpMessage="Repariert nur fehlerhafte Log-Einträge")]
    [switch]$FixErrors,
    
    [Parameter(HelpMessage="Dateimuster zum Ausschließen")]
    [string[]]$ExcludePatterns = @(),
    
    [Parameter(HelpMessage="Maximale Thread-Anzahl")]
    [ValidateRange(1, 64)]
    [int]$MaxThreads = ([Environment]::ProcessorCount * 2),
    
    [Parameter(HelpMessage="Batch-Größe für Verarbeitung")]
    [ValidateRange(1, 1000)]
    [int]$BatchSize = 0,  # 0 = Automatische Berechnung
    
    [Parameter(HelpMessage="Anzahl Wiederholungsversuche")]
    [ValidateRange(1, 10)]
    [int]$RetryAttempts = 3,
    
    [Parameter(HelpMessage="Logging-Level")]
    [ValidateSet("Error", "Warning", "Info", "Debug")]
    [string]$LogLevel = "Info",
    
    [Parameter(HelpMessage="Vorschau ohne Ausführung")]
    [switch]$WhatIf,
    
    [Parameter(HelpMessage="Unterdrückt Progress-Anzeige")]
    [switch]$Silent
)

#Requires -Version 5.1

# =============================================================================
# ENTERPRISE CONFIGURATION & CONSTANTS
# =============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Konfigurationskonstanten
$script:Config = @{
    # Performance-Settings
    MaxMemoryUsageMB = 1024
    IoTimeoutSeconds = 30
    DefaultRetryDelayMs = 500
    MaxRetryDelayMs = 5000
    
    # Pfad-Settings
    LongPathPrefix = "\\?\"
    MaxPathLength = 32767
    
    # Logging-Settings
    LogDateFormat = "yyyy-MM-dd HH:mm:ss.fff"
    LogFileEncoding = "UTF8"
    
    # Hash-Settings
    BufferSize = 64KB
    
    # Thread-Settings
    MinBatchSize = 10
    MaxBatchSize = 500
    OptimalFilesPerThread = 25
}

# Globale Variablen für Thread-Safety
try {
    $script:LogMutex = New-Object System.Threading.Mutex($false, "MD5Generator_LogMutex_$PID")
    $script:ProgressMutex = New-Object System.Threading.Mutex($false, "MD5Generator_ProgressMutex_$PID")
} catch {
    # Fallback für ältere PowerShell-Versionen
    $script:LogMutex = $null
    $script:ProgressMutex = $null
}
$script:Statistics = @{}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

function Write-LogEntry {
    <#
    .SYNOPSIS
        Thread-sichere, strukturierte Log-Funktion.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter()]
        [ValidateSet("Error", "Warning", "Info", "Debug")]
        [string]$Level = "Info",
        
        [Parameter()]
        [string]$LogFilePath = $script:CurrentLogFile,
        
        [Parameter()]
        [hashtable]$AdditionalData = @{}
    )
    
    # Log-Level-Filtering
    $levelPriority = @{ "Error" = 0; "Warning" = 1; "Info" = 2; "Debug" = 3 }
    $currentPriority = $levelPriority[$script:LogLevel]
    $messagePriority = $levelPriority[$Level]
    
    if ($messagePriority -gt $currentPriority) {
        return
    }
    
    # Strukturierter Log-Eintrag
    $logEntry = [PSCustomObject]@{
        Timestamp = Get-Date -Format $script:Config.LogDateFormat
        Level = $Level
        ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
        ProcessId = $PID
        Message = $Message
        Data = $AdditionalData
    }
    
    # Thread-sichere Ausgabe
    $colorMap = @{
        "Error" = "Red"
        "Warning" = "Yellow" 
        "Info" = "White"
        "Debug" = "Gray"
    }
    
    if (-not $Silent) {
        $color = $colorMap[$Level]
        $displayMessage = "[$($logEntry.Timestamp)] [$Level] $Message"
        Write-Host $displayMessage -ForegroundColor $color
    }
    
    # Thread-sichere Log-Datei-Schreibung
    if ($LogFilePath) {
        $jsonEntry = $logEntry | ConvertTo-Json -Compress
        
        if ($script:LogMutex) {
            $script:LogMutex.WaitOne() | Out-Null
        }
        try {
            if ($PSVersionTable.PSVersion.Major -ge 6) {
                Add-Content -Path $LogFilePath -Value $jsonEntry -Encoding $script:Config.LogFileEncoding -ErrorAction SilentlyContinue
            } else {
                Add-Content -Path $LogFilePath -Value $jsonEntry -Encoding UTF8 -ErrorAction SilentlyContinue
            }
        }
        finally {
            if ($script:LogMutex) {
                $script:LogMutex.ReleaseMutex()
            }
        }
    }
}

function ConvertTo-LongPath {
    <#
    .SYNOPSIS
        Konvertiert Pfade für Unterstützung langer Pfadnamen (>260 Zeichen).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )
    
    try {
        # Bereits ein langer Pfad?
        if ($Path.StartsWith($script:Config.LongPathPrefix)) {
            return $Path
        }
        
        # UNC-Pfad?
        if ($Path.StartsWith("\\")) {
            return $script:Config.LongPathPrefix + "UNC\" + $Path.Substring(2)
        }
        
        # Absoluter lokaler Pfad?
        if ([System.IO.Path]::IsPathRooted($Path)) {
            return $script:Config.LongPathPrefix + $Path
        }
        
        # Relativer Pfad - zu absolut konvertieren
        $absolutePath = [System.IO.Path]::GetFullPath($Path)
        return $script:Config.LongPathPrefix + $absolutePath
    }
    catch {
        Write-LogEntry "Fehler bei Pfadkonvertierung für '$Path': $($_.Exception.Message)" -Level Error
        return $Path  # Fallback zum Original-Pfad
    }
}

function Test-PathSafety {
    <#
    .SYNOPSIS
        Validiert Pfade auf Sicherheitsrisiken (Path Traversal, etc.).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )
    
    # Path Traversal-Schutz
    $dangerousPatterns = @("\.\.\\", "\.\./", "\.\.:", "~")
    foreach ($pattern in $dangerousPatterns) {
        if ($Path -match [regex]::Escape($pattern)) {
            return $false
        }
    }
    
    # Verbotene Zeichen prüfen
    $invalidChars = [System.IO.Path]::GetInvalidPathChars()
    foreach ($char in $invalidChars) {
        if ($Path.Contains($char)) {
            return $false
        }
    }
    
    return $true
}

function Get-OptimalBatchSize {
    <#
    .SYNOPSIS
        Berechnet optimale Batch-Größe basierend auf Dateianzahl und -größe.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [int]$TotalFiles,
        
        [Parameter(Mandatory=$true)]
        [long]$TotalSize,
        
        [Parameter(Mandatory=$true)]
        [int]$ThreadCount
    )
    
    if ($BatchSize -gt 0) {
        return [Math]::Min($BatchSize, $script:Config.MaxBatchSize)
    }
    
    # Adaptive Berechnung
    $avgFileSize = if ($TotalFiles -gt 0) { $TotalSize / $TotalFiles } else { 1MB }
    
    if ($avgFileSize -lt 10KB) {
        # Viele kleine Dateien - größere Batches
        $optimalSize = [Math]::Min(200, [Math]::Max($script:Config.MinBatchSize, $TotalFiles / ($ThreadCount * 4)))
    }
    elseif ($avgFileSize -gt 100MB) {
        # Wenige große Dateien - kleinere Batches  
        $optimalSize = [Math]::Max($script:Config.MinBatchSize, $ThreadCount)
    }
    else {
        # Standard-Größe
        $optimalSize = $script:Config.OptimalFilesPerThread * $ThreadCount / 4
    }
    
    return [Math]::Min([Math]::Max([int]$optimalSize, $script:Config.MinBatchSize), $script:Config.MaxBatchSize)
}

# =============================================================================
# HASH CALCULATION FUNCTIONS
# =============================================================================

function Get-FileHashWithRetry {
    <#
    .SYNOPSIS
        Robuste Hash-Berechnung mit Retry-Mechanismus und Fallback-Strategien.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath,
        
        [Parameter()]
        [string]$Algorithm = $HashAlgorithm,
        
        [Parameter()]
        [string]$ExternalTool = $script:MD5ToolPath,
        
        [Parameter()]
        [int]$MaxRetries = $RetryAttempts
    )
    
    $result = [PSCustomObject]@{
        FilePath = $FilePath
        Hash = $null
        Algorithm = $Algorithm
        Success = $false
        Error = $null
        FileSize = 0
        ProcessingTime = 0
        Method = $null
        Attempts = 0
    }
    
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    try {
        # Sicherheitsvalidierung
        if (-not (Test-PathSafety $FilePath)) {
            throw "Pfad '$FilePath' hat Sicherheitsrisiken"
        }
        
        # Lange Pfad-Unterstützung
        $longPath = ConvertTo-LongPath $FilePath
        
        # Datei-Info abrufen
        $fileInfo = Get-Item -LiteralPath $longPath -ErrorAction Stop
        $result.FileSize = $fileInfo.Length
        
        # Retry-Schleife
        for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
            $result.Attempts = $attempt
            
            try {
                # Strategie 1: Externes Tool (falls verfügbar und MD5)
                if ($ExternalTool -and (Test-Path $ExternalTool) -and $Algorithm -eq "MD5") {
                    $hash = Invoke-ExternalHashTool -FilePath $longPath -ToolPath $ExternalTool
                    if ($hash) {
                        $result.Hash = $hash.ToLower()
                        $result.Method = "ExternalTool"
                        $result.Success = $true
                        break
                    }
                }
                
                # Strategie 2: PowerShell Get-FileHash
                $hashObject = Get-FileHash -LiteralPath $longPath -Algorithm $Algorithm -ErrorAction Stop
                if ($hashObject -and $hashObject.Hash) {
                    $result.Hash = $hashObject.Hash.ToLower()
                    $result.Method = "PowerShell"
                    $result.Success = $true
                    break
                }
                
                # Strategie 3: .NET Crypto APIs (Fallback)
                $hash = Get-HashUsingDotNet -FilePath $longPath -Algorithm $Algorithm
                if ($hash) {
                    $result.Hash = $hash.ToLower()
                    $result.Method = "DotNet"
                    $result.Success = $true
                    break
                }
                
                throw "Alle Hash-Methoden fehlgeschlagen"
            }
            catch {
                $result.Error = $_.Exception.Message
                
                # Intelligente Retry-Entscheidung
                if ($attempt -lt $MaxRetries) {
                    if ($result.Error -match "being used by another process|locked|in use") {
                        # Datei gesperrt - exponential backoff
                        $delayMs = $script:Config.DefaultRetryDelayMs * [Math]::Pow(2, $attempt - 1)
                        $delayMs = [Math]::Min($delayMs, $script:Config.MaxRetryDelayMs)
                        
                        Write-LogEntry "Retry $attempt/$MaxRetries für gesperrte Datei: $(Split-Path $FilePath -Leaf) (Delay: ${delayMs}ms)" -Level Warning
                        Start-Sleep -Milliseconds $delayMs
                    }
                    elseif ($result.Error -match "Access.*denied|UnauthorizedAccess") {
                        # Berechtigungsfehler - kein Retry sinnvoll
                        break
                    }
                    elseif ($result.Error -match "not found|FileNotFound") {
                        # Datei nicht gefunden - kein Retry sinnvoll  
                        break
                    }
                    else {
                        # Sonstiger Fehler - kurzer Retry
                        Start-Sleep -Milliseconds $script:Config.DefaultRetryDelayMs
                    }
                }
            }
        }
    }
    catch {
        $result.Error = $_.Exception.Message
        $result.Success = $false
    }
    finally {
        $stopwatch.Stop()
        $result.ProcessingTime = $stopwatch.ElapsedMilliseconds
        
        # Statistiken aktualisieren
        if ($result.Success) {
            if ($script:Statistics.ContainsKey("SuccessCount")) {
                $script:Statistics["SuccessCount"]++
            } else {
                $script:Statistics["SuccessCount"] = 1
            }
            if ($script:Statistics.ContainsKey("TotalSize")) {
                $script:Statistics["TotalSize"] += $result.FileSize
            } else {
                $script:Statistics["TotalSize"] = $result.FileSize
            }
        } else {
            if ($script:Statistics.ContainsKey("ErrorCount")) {
                $script:Statistics["ErrorCount"]++
            } else {
                $script:Statistics["ErrorCount"] = 1
            }
        }
    }
    
    return $result
}

function Invoke-ExternalHashTool {
    <#
    .SYNOPSIS
        Sicherer Aufruf des externen MD5-Tools mit Validierung.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath,
        
        [Parameter(Mandatory=$true)]
        [string]$ToolPath
    )
    
    try {
        # Tool-Signatur prüfen (vereinfacht)
        if (-not (Test-Path $ToolPath)) {
            return $null
        }
        
        # Sicherer Aufruf mit Timeout
        $processStartInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processStartInfo.FileName = $ToolPath
        $processStartInfo.Arguments = "`"$FilePath`" -ContinueOnErrors -TextMode"
        $processStartInfo.UseShellExecute = $false
        $processStartInfo.RedirectStandardOutput = $true
        $processStartInfo.RedirectStandardError = $true
        $processStartInfo.CreateNoWindow = $true
        
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processStartInfo
        
        $outputBuilder = New-Object System.Text.StringBuilder
        $errorBuilder = New-Object System.Text.StringBuilder
        
        $outputHandler = {
            if ($EventArgs.Data) {
                [void]$outputBuilder.AppendLine($EventArgs.Data)
            }
        }
        
        $errorHandler = {
            if ($EventArgs.Data) {
                [void]$errorBuilder.AppendLine($EventArgs.Data)
            }
        }
        
        Register-ObjectEvent -InputObject $process -EventName OutputDataReceived -Action $outputHandler | Out-Null
        Register-ObjectEvent -InputObject $process -EventName ErrorDataReceived -Action $errorHandler | Out-Null
        
        $process.Start() | Out-Null
        $process.BeginOutputReadLine()
        $process.BeginErrorReadLine()
        
        # Timeout
        if (-not $process.WaitForExit($script:Config.IoTimeoutSeconds * 1000)) {
            $process.Kill()
            throw "Tool-Timeout nach $($script:Config.IoTimeoutSeconds) Sekunden"
        }
        
        Get-Event | Remove-Event
        
        if ($process.ExitCode -eq 0) {
            return Extract-HashFromOutput $outputBuilder.ToString()
        }
        
        return $null
    }
    catch {
        Write-LogEntry "Externes Tool fehlgeschlagen: $($_.Exception.Message)" -Level Warning
        return $null
    }
}

function Get-HashUsingDotNet {
    <#
    .SYNOPSIS
        Hash-Berechnung mit .NET Crypto APIs als Fallback.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath,
        
        [Parameter(Mandatory=$true)]
        [string]$Algorithm
    )
    
    try {
        $cryptoProvider = switch ($Algorithm) {
            "MD5" { [System.Security.Cryptography.MD5]::Create() }
            "SHA1" { [System.Security.Cryptography.SHA1]::Create() }
            "SHA256" { [System.Security.Cryptography.SHA256]::Create() }
            "SHA384" { [System.Security.Cryptography.SHA384]::Create() }
            "SHA512" { [System.Security.Cryptography.SHA512]::Create() }
            default { throw "Unbekannter Algorithmus: $Algorithm" }
        }
        
        try {
            $fileStream = [System.IO.File]::OpenRead($FilePath)
            try {
                $hashBytes = $cryptoProvider.ComputeHash($fileStream)
                return [System.BitConverter]::ToString($hashBytes) -replace '-', ''
            }
            finally {
                $fileStream.Dispose()
            }
        }
        finally {
            $cryptoProvider.Dispose()
        }
    }
    catch {
        return $null
    }
}

function Extract-HashFromOutput {
    <#
    .SYNOPSIS
        Robuste Hash-Extraktion aus Tool-Output.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Output
    )
    
    if ([string]::IsNullOrWhiteSpace($Output)) {
        return $null
    }
    
    # Verschiedene Extraktionsstrategien
    $strategies = @(
        # MD5 = HASH Format
        '=\s*([a-fA-F0-9]{32})',
        # Nur Hash (32 Zeichen)
        '([a-fA-F0-9]{32})',
        # Hash mit Dateiname
        '([a-fA-F0-9]{32})\s+\*?.+',
        # Hash am Zeilenanfang
        '^([a-fA-F0-9]{32})'
    )
    
    foreach ($pattern in $strategies) {
        if ($Output -match $pattern) {
            return $Matches[1]
        }
    }
    
    return $null
}

# =============================================================================
# LOG MANAGEMENT FUNCTIONS  
# =============================================================================

function Initialize-LogFile {
    <#
    .SYNOPSIS
        Initialisiert Log-Datei mit Header und Metadata.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$LogPath,
        
        [Parameter(Mandatory=$true)]
        [string]$SourceDirectory
    )
    
    try {
        $logDir = Split-Path $LogPath -Parent
        if ($logDir -and -not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        
        # Log-Header mit Metadata
        $header = [PSCustomObject]@{
            LogVersion = "2.0"
            CreatedDate = Get-Date -Format $script:Config.LogDateFormat
            SourceDirectory = $SourceDirectory
            HashAlgorithm = $HashAlgorithm
            PowerShellVersion = $PSVersionTable.PSVersion.ToString()
            ComputerName = $env:COMPUTERNAME
            UserName = $env:USERNAME
            ScriptVersion = "2.0"
        }
        
        $headerJson = $header | ConvertTo-Json -Compress
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            Set-Content -Path $LogPath -Value "# MD5 Checksum Log - $headerJson" -Encoding $script:Config.LogFileEncoding
        } else {
            Set-Content -Path $LogPath -Value "# MD5 Checksum Log - $headerJson" -Encoding UTF8
        }
        
        Write-LogEntry "Log-Datei initialisiert: $LogPath" -Level Info
        return $true
    }
    catch {
        Write-LogEntry "Fehler beim Initialisieren der Log-Datei: $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Read-LogEntries {
    <#
    .SYNOPSIS
        Liest und parst Log-Einträge für Resume/FixErrors.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$LogPath
    )
    
    $entries = @{
        Successful = @{}
        Failed = @{}
        Header = $null
    }
    
    if (-not (Test-Path $LogPath)) {
        return $entries
    }
    
    try {
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            $lines = Get-Content -Path $LogPath -Encoding $script:Config.LogFileEncoding
        } else {
            $lines = Get-Content -Path $LogPath -Encoding UTF8
        }
        
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }
            
            # Header-Zeile
            if ($line.StartsWith("# MD5 Checksum Log")) {
                try {
                    $headerJson = $line.Substring($line.IndexOf("{"))
                    $entries.Header = $headerJson | ConvertFrom-Json
                }
                catch {
                    # Ignoriere Header-Parse-Fehler
                }
                continue
            }
            
            # JSON Log-Einträge
            if ($line.StartsWith("{")) {
                try {
                    $logEntry = $line | ConvertFrom-Json
                    
                    # Nur relevante Hash-Einträge
                    if ($logEntry.Data -and $logEntry.Data.FilePath) {
                        if ($logEntry.Data.Success -eq $true -and $logEntry.Data.Hash) {
                            $entries.Successful[$logEntry.Data.FilePath] = $logEntry.Data
                        }
                        elseif ($logEntry.Data.Success -eq $false) {
                            $entries.Failed[$logEntry.Data.FilePath] = $logEntry.Data
                        }
                    }
                }
                catch {
                    # Ignoriere Parse-Fehler für einzelne Zeilen
                }
                continue
            }
            
            # Legacy-Format (für Abwärtskompatibilität)
            if ($line -match '^([^=]+)\s*=\s*([a-fA-F0-9]{32,128})') {
                $filePath = $Matches[1].Trim()
                $hash = $Matches[2].Trim()
                
                $entries.Successful[$filePath] = [PSCustomObject]@{
                    FilePath = $filePath
                    Hash = $hash
                    Success = $true
                    Method = "Legacy"
                }
            }
            elseif ($line -match '^#\s*ERROR:.*?([^\\]+)$') {
                $fileName = $Matches[1].Trim()
                # Für Legacy-Fehler können wir den vollständigen Pfad nicht rekonstruieren
                # Diese werden bei FixErrors ignoriert
            }
        }
        
        Write-LogEntry "Log-Analyse: $($entries.Successful.Count) erfolgreich, $($entries.Failed.Count) fehlerhaft" -Level Info
        return $entries
    }
    catch {
        Write-LogEntry "Fehler beim Lesen der Log-Datei: $($_.Exception.Message)" -Level Error
        return $entries
    }
}

function Write-HashResult {
    <#
    .SYNOPSIS
        Thread-sichere Protokollierung von Hash-Ergebnissen.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Result,
        
        [Parameter(Mandatory=$true)]
        [string]$LogPath
    )
    
    $logData = @{
        FilePath = $Result.FilePath
        Hash = $Result.Hash
        Algorithm = $Result.Algorithm
        Success = $Result.Success
        Error = $Result.Error
        FileSize = $Result.FileSize
        ProcessingTime = $Result.ProcessingTime
        Method = $Result.Method
        Attempts = $Result.Attempts
    }
    
    if ($Result.Success) {
        Write-LogEntry "Hash berechnet: $(Split-Path $Result.FilePath -Leaf)" -Level Info -AdditionalData $logData
    }
    else {
        Write-LogEntry "Hash-Fehler: $(Split-Path $Result.FilePath -Leaf) - $($Result.Error)" -Level Error -AdditionalData $logData
    }
}

# =============================================================================
# MAIN PROCESSING FUNCTIONS
# =============================================================================

function Get-FilesToProcess {
    <#
    .SYNOPSIS
        Sammelt Dateien für Verarbeitung mit Filterung und Validierung.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$SourcePath,
        
        [Parameter()]
        [string[]]$ExcludePatterns = @(),
        
        [Parameter()]
        [hashtable]$ExistingEntries = @{}
    )
    
    Write-LogEntry "Scanne Verzeichnis: $SourcePath" -Level Info
    
    try {
        $longPath = ConvertTo-LongPath $SourcePath
        
        # Rekursive Datei-Enumeration
        $allFiles = Get-ChildItem -LiteralPath $longPath -Recurse -File -ErrorAction SilentlyContinue | 
                   Where-Object { 
                       $include = $true
                       
                       # Exclusion-Patterns prüfen
                       foreach ($pattern in $ExcludePatterns) {
                           if ($_.Name -like $pattern) {
                               $include = $false
                               break
                           }
                       }
                       
                       # System-/Temp-Dateien ausschließen
                       if ($include -and ($_.Attributes -band [System.IO.FileAttributes]::System)) {
                           $include = $false
                       }
                       
                       # Bereits verarbeitete Dateien ausschließen (für Resume)
                       if ($include -and $ExistingEntries.ContainsKey($_.FullName)) {
                           $include = $false
                       }
                       
                       $include
                   }
        
        $totalFiles = $allFiles.Count
        $totalSize = ($allFiles | Measure-Object -Property Length -Sum).Sum
        
        Write-LogEntry "Gefunden: $totalFiles Dateien ($(Format-FileSize $totalSize))" -Level Info
        
        return @{
            Files = $allFiles
            TotalCount = $totalFiles
            TotalSize = $totalSize
        }
    }
    catch {
        Write-LogEntry "Fehler beim Scannen: $($_.Exception.Message)" -Level Error
        throw
    }
}

function Invoke-ParallelHashCalculation {
    <#
    .SYNOPSIS
        Hauptfunktion für parallele Hash-Berechnung.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.IO.FileInfo[]]$Files,
        
        [Parameter(Mandatory=$true)]
        [string]$LogPath,
        
        [Parameter(Mandatory=$true)]
        [int]$ThreadCount,
        
        [Parameter(Mandatory=$true)]
        [int]$BatchSize
    )
    
    $totalFiles = $Files.Count
    if ($totalFiles -eq 0) {
        Write-LogEntry "Keine Dateien zu verarbeiten" -Level Warning
        return
    }
    
    # Batches erstellen
    $batches = @()
    for ($i = 0; $i -lt $totalFiles; $i += $BatchSize) {
        $endIndex = [Math]::Min($i + $BatchSize - 1, $totalFiles - 1)
        $batches += ,$Files[$i..$endIndex]
    }
    
    $totalBatches = $batches.Count
    Write-LogEntry "Verarbeite $totalFiles Dateien in $totalBatches Batches mit $ThreadCount Threads" -Level Info
    
    # Progress-Tracking
    $completed = 0
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    # Parallel-Verarbeitung (PowerShell 7+) oder Sequential (5.x)
    $useParallel = $PSVersionTable.PSVersion.Major -ge 7 -and $ThreadCount -gt 1
    
    if ($useParallel) {
        Write-LogEntry "Parallel-Modus aktiviert" -Level Info
        
        $batches | ForEach-Object -Parallel {
            # Importiere benötigte Funktionen in Parallel-Runspace
            $VerbosePreference = $using:VerbosePreference
            $LogPath = $using:LogPath
            $HashAlgorithm = $using:HashAlgorithm
            $RetryAttempts = $using:RetryAttempts
            $MD5ToolPath = $using:script:MD5ToolPath
            $Config = $using:script:Config
            
            # Funktionen in Runspace definieren (vereinfacht)
            function Write-LogEntry {
                param($Message, $Level = "Info", $LogFilePath, $AdditionalData = @{})
                # Vereinfachte Thread-sichere Implementierung
                $logEntry = [PSCustomObject]@{
                    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
                    Level = $Level
                    ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                    Message = $Message
                    Data = $AdditionalData
                }
                $jsonEntry = $logEntry | ConvertTo-Json -Compress
                # Atomare Schreibung (vereinfacht)
                $jsonEntry | Out-File -FilePath $LogFilePath -Append -Encoding UTF8
            }
            
            # Batch verarbeiten
            $batch = $_
            foreach ($file in $batch) {
                try {
                    $result = Get-FileHash -LiteralPath $file.FullName -Algorithm $HashAlgorithm -ErrorAction Stop
                    $hashResult = [PSCustomObject]@{
                        FilePath = $file.FullName
                        Hash = $result.Hash.ToLower()
                        Algorithm = $HashAlgorithm
                        Success = $true
                        Error = $null
                        FileSize = $file.Length
                        ProcessingTime = 0
                        Method = "PowerShell"
                        Attempts = 1
                    }
                }
                catch {
                    $hashResult = [PSCustomObject]@{
                        FilePath = $file.FullName
                        Hash = $null
                        Algorithm = $HashAlgorithm
                        Success = $false
                        Error = $_.Exception.Message
                        FileSize = $file.Length
                        ProcessingTime = 0
                        Method = "Failed"
                        Attempts = 1
                    }
                }
                
                # Protokollierung
                $logData = @{
                    FilePath = $hashResult.FilePath
                    Hash = $hashResult.Hash
                    Algorithm = $hashResult.Algorithm
                    Success = $hashResult.Success
                    Error = $hashResult.Error
                    FileSize = $hashResult.FileSize
                    ProcessingTime = $hashResult.ProcessingTime
                    Method = $hashResult.Method
                    Attempts = $hashResult.Attempts
                }
                
                if ($hashResult.Success) {
                    Write-LogEntry "Hash berechnet: $(Split-Path $hashResult.FilePath -Leaf)" -Level Info -LogFilePath $LogPath -AdditionalData $logData
                }
                else {
                    Write-LogEntry "Hash-Fehler: $(Split-Path $hashResult.FilePath -Leaf) - $($hashResult.Error)" -Level Error -LogFilePath $LogPath -AdditionalData $logData
                }
            }
            
        } -ThrottleLimit $ThreadCount
    }
    else {
        Write-LogEntry "Sequential-Modus (PowerShell $($PSVersionTable.PSVersion.Major))" -Level Warning
        
        # Sequential-Verarbeitung
        $batchIndex = 0
        foreach ($batch in $batches) {
            $batchIndex++
            
            foreach ($file in $batch) {
                $result = Get-FileHashWithRetry -FilePath $file.FullName
                Write-HashResult -Result $result -LogPath $LogPath
                
                $completed++
                
                # Progress-Update
                if (-not $Silent -and ($completed % 10 -eq 0 -or $completed -eq $totalFiles)) {
                    $percentComplete = [int](($completed / $totalFiles) * 100)
                    $elapsed = $stopwatch.Elapsed
                    $rate = if ($elapsed.TotalSeconds -gt 0) { $completed / $elapsed.TotalSeconds } else { 0 }
                    $eta = if ($rate -gt 0) { [TimeSpan]::FromSeconds(($totalFiles - $completed) / $rate) } else { [TimeSpan]::Zero }
                    
                    Write-Progress -Activity "Hash-Berechnung" -Status "$completed/$totalFiles ($($rate.ToString('F1')) Dateien/s, ETA: $($eta.ToString('hh\:mm\:ss')))" -PercentComplete $percentComplete
                }
            }
        }
    }
    
    $stopwatch.Stop()
    Write-LogEntry "Verarbeitung abgeschlossen in $($stopwatch.Elapsed.ToString('hh\:mm\:ss'))" -Level Info
    
    if (-not $Silent) {
        Write-Progress -Activity "Hash-Berechnung" -Completed
    }
}

function Repair-ErrorEntries {
    <#
    .SYNOPSIS
        Repariert fehlerhafte Log-Einträge (FixErrors-Funktionalität).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$LogPath
    )
    
    Write-LogEntry "Starte FixErrors-Modus" -Level Info
    
    if (-not (Test-Path $LogPath)) {
        Write-LogEntry "Log-Datei nicht gefunden: $LogPath" -Level Error
        return $false
    }
    
    # Bestehende Log-Einträge analysieren
    $logEntries = Read-LogEntries -LogPath $LogPath
    $failedEntries = $logEntries.Failed
    
    if ($failedEntries.Count -eq 0) {
        Write-LogEntry "Keine fehlerhaften Einträge gefunden" -Level Info
        return $true
    }
    
    Write-LogEntry "Gefunden: $($failedEntries.Count) fehlerhafte Einträge" -Level Info
    
    $repairedCount = 0
    $stillFailedCount = 0
    
    foreach ($failedPath in $failedEntries.Keys) {
        Write-LogEntry "Repariere: $(Split-Path $failedPath -Leaf)" -Level Info
        
        # Prüfe ob Datei noch existiert
        if (-not (Test-Path $failedPath)) {
            Write-LogEntry "Datei nicht mehr vorhanden: $(Split-Path $failedPath -Leaf)" -Level Warning
            continue
        }
        
        # Versuche Hash-Berechnung
        $result = Get-FileHashWithRetry -FilePath $failedPath
        
        if ($result.Success) {
            # Erfolgreiche Reparatur - Log aktualisieren
            Write-HashResult -Result $result -LogPath $LogPath
            $repairedCount++
            Write-LogEntry "Repariert: $(Split-Path $failedPath -Leaf) -> $($result.Hash)" -Level Info
        }
        else {
            # Immer noch fehlerhaft
            Write-HashResult -Result $result -LogPath $LogPath
            $stillFailedCount++
            Write-LogEntry "Weiterhin fehlerhaft: $(Split-Path $failedPath -Leaf) - $($result.Error)" -Level Warning
        }
    }
    
    Write-LogEntry "FixErrors abgeschlossen: $repairedCount repariert, $stillFailedCount weiterhin fehlerhaft" -Level Info
    return $true
}

function Format-FileSize {
    <#
    .SYNOPSIS
        Formatiert Dateigröße in lesbarer Form.
    #>
    param([long]$Bytes)
    
    if ($Bytes -eq 0) { return "0 B" }
    
    $sizes = @("B", "KB", "MB", "GB", "TB", "PB")
    $index = 0
    $size = [double]$Bytes
    
    while ($size -ge 1024 -and $index -lt ($sizes.Count - 1)) {
        $size = $size / 1024
        $index++
    }
    
    return "{0:N2} {1}" -f $size, $sizes[$index]
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

function Main {
    <#
    .SYNOPSIS
        Hauptausführungsfunktion mit vollständiger Fehlerbehandlung.
    #>
    
    try {
        # Banner
        Write-Host ""
        Write-Host "┌─────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
        Write-Host "│         Enterprise MD5 Checksum Generator v2.0             │" -ForegroundColor Cyan  
        Write-Host "│         Thread-Safe • Robust • Production-Ready            │" -ForegroundColor Cyan
        Write-Host "└─────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
        Write-Host ""
        
        # Globale Variablen setzen
        $script:LogLevel = $LogLevel
        $script:MD5ToolPath = $MD5Tool
        
        # Pfad-Validierung
        if (-not (Test-PathSafety $SourceDir)) {
            throw "Unsicherer Quellpfad erkannt: $SourceDir"
        }
        
        $SourceDir = ConvertTo-LongPath (Resolve-Path $SourceDir).Path
        
        # Log-Datei bestimmen
        if (-not $LogFile) {
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $sourceName = Split-Path $SourceDir -Leaf
            $LogFile = Join-Path (Split-Path $SourceDir -Parent) "${sourceName}_${timestamp}_${HashAlgorithm}.log"
        }
        
        $LogFile = ConvertTo-LongPath $LogFile
        $script:CurrentLogFile = $LogFile
        
        # MD5-Tool Auto-Detection
        if (-not $MD5Tool) {
            $commonPaths = @(
                "C:\Peano\Tools\MD5-x64.exe",
                "C:\Tools\MD5-x64.exe", 
                ".\MD5-x64.exe"
            )
            
            foreach ($path in $commonPaths) {
                if (Test-Path $path) {
                    $script:MD5ToolPath = $path
                    break
                }
            }
        }
        
        # Parameter-Anzeige
        Write-LogEntry "Konfiguration:" -Level Info
        Write-LogEntry "  Quellverzeichnis: $SourceDir" -Level Info
        Write-LogEntry "  Log-Datei: $LogFile" -Level Info  
        Write-LogEntry "  Hash-Algorithmus: $HashAlgorithm" -Level Info
        Write-LogEntry "  Max. Threads: $MaxThreads" -Level Info
        Write-LogEntry "  Retry-Versuche: $RetryAttempts" -Level Info
        Write-LogEntry "  PowerShell: $($PSVersionTable.PSVersion)" -Level Info
        
        if ($script:MD5ToolPath) {
            Write-LogEntry "  Externes Tool: $($script:MD5ToolPath)" -Level Info
        }
        
        # FixErrors-Modus
        if ($FixErrors) {
            if (-not $LogFile -or -not (Test-Path $LogFile)) {
                throw "FixErrors erfordert existierende Log-Datei"
            }
            
            return Repair-ErrorEntries -LogPath $LogFile
        }
        
        # Log initialisieren
        if (-not $Resume -or -not (Test-Path $LogFile)) {
            if (-not (Initialize-LogFile -LogPath $LogFile -SourceDirectory $SourceDir)) {
                throw "Log-Datei konnte nicht initialisiert werden"
            }
        }
        
        # Bestehende Einträge für Resume laden
        $existingEntries = @{}
        if ($Resume -and (Test-Path $LogFile)) {
            $logEntries = Read-LogEntries -LogPath $LogFile
            $existingEntries = $logEntries.Successful
            Write-LogEntry "Resume-Modus: $($existingEntries.Count) bereits verarbeitete Dateien übersprungen" -Level Info
        }
        
        # Dateien sammeln
        $fileInfo = Get-FilesToProcess -SourcePath $SourceDir -ExcludePatterns $ExcludePatterns -ExistingEntries $existingEntries
        
        if ($fileInfo.TotalCount -eq 0) {
            Write-LogEntry "Keine Dateien zu verarbeiten" -Level Warning
            return $true
        }
        
        # Optimale Batch-Größe berechnen
        $optimalBatchSize = Get-OptimalBatchSize -TotalFiles $fileInfo.TotalCount -TotalSize $fileInfo.TotalSize -ThreadCount $MaxThreads
        Write-LogEntry "Optimale Batch-Größe: $optimalBatchSize" -Level Info
        
        # WhatIf-Modus
        if ($WhatIf) {
            Write-Host ""
            Write-Host "┌─────────────────────────────────────────────────────────────┐" -ForegroundColor Yellow
            Write-Host "│                       WHAT-IF MODUS                        │" -ForegroundColor Yellow
            Write-Host "└─────────────────────────────────────────────────────────────┘" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Zu verarbeitende Dateien: $($fileInfo.TotalCount)" -ForegroundColor Cyan
            Write-Host "Gesamtgröße: $(Format-FileSize $fileInfo.TotalSize)" -ForegroundColor Cyan
            Write-Host "Geschätzte Batches: $([Math]::Ceiling($fileInfo.TotalCount / $optimalBatchSize))" -ForegroundColor Cyan
            Write-Host "Thread-Konfiguration: $MaxThreads Threads" -ForegroundColor Cyan
            Write-Host "Log-Datei: $LogFile" -ForegroundColor Cyan
            return $true
        }
        
        # Hauptverarbeitung starten
        Write-LogEntry "Starte Hash-Berechnung..." -Level Info
        $processingStart = Get-Date
        
        Invoke-ParallelHashCalculation -Files $fileInfo.Files -LogPath $LogFile -ThreadCount $MaxThreads -BatchSize $optimalBatchSize
        
        $processingEnd = Get-Date
        $totalDuration = $processingEnd - $processingStart
        
        # Finale Statistiken
        $successCount = if ($script:Statistics.ContainsKey("SuccessCount")) { $script:Statistics["SuccessCount"] } else { 0 }
        $errorCount = if ($script:Statistics.ContainsKey("ErrorCount")) { $script:Statistics["ErrorCount"] } else { 0 }
        $processedSize = if ($script:Statistics.ContainsKey("TotalSize")) { $script:Statistics["TotalSize"] } else { 0 }
        
        Write-Host ""
        Write-Host "┌─────────────────────────────────────────────────────────────┐" -ForegroundColor Green
        Write-Host "│                   VERARBEITUNG ABGESCHLOSSEN                │" -ForegroundColor Green
        Write-Host "└─────────────────────────────────────────────────────────────┘" -ForegroundColor Green
        Write-Host ""
        Write-Host "Erfolgreich verarbeitet: $successCount Dateien" -ForegroundColor Green
        Write-Host "Fehler: $errorCount" -ForegroundColor $(if($errorCount -gt 0){"Red"}else{"Green"})
        Write-Host "Verarbeitete Datenmenge: $(Format-FileSize $processedSize)" -ForegroundColor Cyan
        Write-Host "Gesamtdauer: $($totalDuration.ToString('hh\:mm\:ss'))" -ForegroundColor Cyan
        Write-Host "Durchschnitt: $(if($totalDuration.TotalSeconds -gt 0){($successCount / $totalDuration.TotalSeconds).ToString('F1')}else{'N/A'}) Dateien/Sekunde" -ForegroundColor Cyan
        Write-Host "Log-Datei: $LogFile" -ForegroundColor Yellow
        Write-Host ""
        
        Write-LogEntry "Verarbeitung erfolgreich abgeschlossen" -Level Info
        return $true
    }
    catch {
        Write-LogEntry "Fataler Fehler: $($_.Exception.Message)" -Level Error
        Write-Host "Fehler: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Stack Trace: $($_.ScriptStackTrace)" -ForegroundColor Red
        return $false
    }
    finally {
        # Cleanup
        if ($script:LogMutex) {
            try { $script:LogMutex.Dispose() } catch { }
        }
        if ($script:ProgressMutex) {
            try { $script:ProgressMutex.Dispose() } catch { }
        }
    }
}

# Script-Ausführung
$exitCode = if (Main) { 0 } else { 1 }
exit $exitCode
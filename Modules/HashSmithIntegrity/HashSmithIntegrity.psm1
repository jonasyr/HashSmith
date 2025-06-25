<#
.SYNOPSIS
    Directory integrity hash computation for HashSmith

.DESCRIPTION
    This module provides deterministic directory integrity hash computation
    that creates consistent hashes regardless of file processing order.
#>

# Import required modules
# Note: Dependencies are handled by the main script import order

#region Public Functions

<#
.SYNOPSIS
    Computes a deterministic directory integrity hash

.DESCRIPTION
    Creates a deterministic hash of all files in a directory by sorting files
    in a consistent manner and including metadata for integrity verification.

.PARAMETER FileHashes
    Hashtable of file paths and their hash information

.PARAMETER Algorithm
    Hash algorithm to use for directory hash computation

.PARAMETER BasePath
    Base path for creating relative paths

.PARAMETER StrictMode
    Enable strict mode with additional validation

.EXAMPLE
    $dirHash = Get-HashSmithDirectoryIntegrityHash -FileHashes $hashes -Algorithm "SHA256" -BasePath $basePath
#>
function Get-HashSmithDirectoryIntegrityHash {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$FileHashes,
        
        [ValidateSet('MD5', 'SHA1', 'SHA256', 'SHA512')]
        [string]$Algorithm = 'MD5',
        
        [string]$BasePath,
        
        [switch]$StrictMode
    )
    
    Write-HashSmithLog -Message "Computing directory integrity hash with enhanced determinism" -Level INFO -Component 'INTEGRITY'
    
    if ($FileHashes.Count -eq 0) {
        Write-HashSmithLog -Message "No files to include in directory hash" -Level WARN -Component 'INTEGRITY'
        return $null
    }
    
    try {
        # Create deterministic input by sorting files with enhanced criteria
        $sortedEntries = @()
        $fileCount = 0
        $totalSize = 0
        
        # Sort by normalized relative path and then by file size for determinism
        $sortedPaths = $FileHashes.Keys | Sort-Object { 
            $relativePath = $_
            if ($BasePath -and $_.StartsWith($BasePath)) {
                $relativePath = $_.Substring($BasePath.Length).TrimStart('\', '/')
            }
            $relativePath.ToLowerInvariant().Replace('\', '/')
        } | Sort-Object { $FileHashes[$_].Size }
        
        foreach ($filePath in $sortedPaths) {
            $relativePath = $filePath
            if ($BasePath -and $filePath.StartsWith($BasePath)) {
                $relativePath = $filePath.Substring($BasePath.Length).TrimStart('\', '/')
            }
            
            # Normalize path separators for cross-platform determinism
            $normalizedRelativePath = $relativePath.Replace('\', '/')
            
            # Format: normalizedpath|hash|size|flags
            $flags = @()
            if ($FileHashes[$filePath].IsSymlink) { $flags += 'S' }
            if ($FileHashes[$filePath].RaceConditionDetected) { $flags += 'R' }
            if ($FileHashes[$filePath].IntegrityVerified) { $flags += 'I' }
            $flagString = $flags -join ','
            
            $entry = "$normalizedRelativePath|$($FileHashes[$filePath].Hash)|$($FileHashes[$filePath].Size)|$flagString"
            $sortedEntries += $entry
            $fileCount++
            $totalSize += $FileHashes[$filePath].Size
        }
        
        $config = Get-HashSmithConfig
        
        # Add metadata for additional integrity verification
        $metadata = @(
            "METADATA|FileCount:$fileCount",
            "METADATA|TotalSize:$totalSize",
            "METADATA|Algorithm:$Algorithm",
            "METADATA|Version:$($config.Version)",
            "METADATA|Timestamp:$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffZ')"
        )
        
        # Combine all entries
        $allEntries = $sortedEntries + $metadata
        $combinedInput = $allEntries -join "`n"
        
        if ($StrictMode) {
            Write-HashSmithLog -Message "Directory hash input preview (first 500 chars): $($combinedInput.Substring(0, [Math]::Min(500, $combinedInput.Length)))" -Level DEBUG -Component 'INTEGRITY'
        }
        
        # Create combined input bytes with explicit encoding
        $inputBytes = [System.Text.Encoding]::UTF8.GetBytes($combinedInput)
        
        # Compute final hash
        $hashAlgorithm = [System.Security.Cryptography.HashAlgorithm]::Create($Algorithm)
        $hashBytes = $hashAlgorithm.ComputeHash($inputBytes)
        $directoryHash = [System.BitConverter]::ToString($hashBytes) -replace '-', ''
        $hashAlgorithm.Dispose()
        
        Write-HashSmithLog -Message "Directory integrity hash computed: $($directoryHash.ToLower())" -Level SUCCESS -Component 'INTEGRITY'
        Write-HashSmithLog -Message "Hash includes $fileCount files, $($totalSize) bytes total" -Level INFO -Component 'INTEGRITY'
        
        return @{
            Hash = $directoryHash.ToLower()
            FileCount = $fileCount
            TotalSize = $totalSize
            Algorithm = $Algorithm
            Metadata = @{
                SortedEntries = $sortedEntries.Count
                MetadataEntries = $metadata.Count
                InputSize = $inputBytes.Length
                Timestamp = Get-Date
            }
        }
        
    }
    catch {
        Write-HashSmithLog -Message "Error computing directory integrity hash: $($_.Exception.Message)" -Level ERROR -Component 'INTEGRITY'
        throw
    }
}

#endregion

# Export public functions
Export-ModuleMember -Function @(
    'Get-HashSmithDirectoryIntegrityHash'
)

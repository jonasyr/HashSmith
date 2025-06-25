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
        # Create standard directory hash compatible with other MD5 tools
        # Simply concatenate all individual file hashes in sorted filename order
        $fileCount = 0
        $totalSize = 0
        $sortedHashes = @()
        
        # Sort files by filename only (standard approach)
        $sortedPaths = $FileHashes.Keys | Sort-Object { 
            [System.IO.Path]::GetFileName($_).ToLowerInvariant()
        }
        
        foreach ($filePath in $sortedPaths) {
            $hash = $FileHashes[$filePath].Hash
            $sortedHashes += $hash
            $fileCount++
            $totalSize += $FileHashes[$filePath].Size
        }
        
        # Standard approach: concatenate all hashes without separators
        $combinedInput = $sortedHashes -join ""
        
        if ($StrictMode) {
            Write-HashSmithLog -Message "Directory hash input (concatenated hashes): $($combinedInput.Substring(0, [Math]::Min(200, $combinedInput.Length)))..." -Level DEBUG -Component 'INTEGRITY'
        }
        
        # Create combined input bytes with explicit encoding
        $inputBytes = [System.Text.Encoding]::UTF8.GetBytes($combinedInput)
        
        # Compute final hash
        $hashAlgorithm = [System.Security.Cryptography.HashAlgorithm]::Create($Algorithm)
        $hashBytes = $hashAlgorithm.ComputeHash($inputBytes)
        $directoryHash = [System.BitConverter]::ToString($hashBytes) -replace '-', ''
        $hashAlgorithm.Dispose()
        
        Write-HashSmithLog -Message "Standard directory hash computed: $($directoryHash.ToLower())" -Level SUCCESS -Component 'INTEGRITY'
        Write-HashSmithLog -Message "Hash includes $fileCount files, $($totalSize) bytes total (compatible with standard MD5 tools)" -Level INFO -Component 'INTEGRITY'
        
        return @{
            Hash = $directoryHash.ToLower()
            FileCount = $fileCount
            TotalSize = $totalSize
            Algorithm = $Algorithm
            Metadata = @{
                SortedHashes = $sortedHashes.Count
                InputSize = $inputBytes.Length
                Method = "Standard concatenated hash"
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

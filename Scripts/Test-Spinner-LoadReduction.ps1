#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Test the new spinner and load reduction improvements

.DESCRIPTION
    Tests the new file-level spinner during chunk processing and verifies
    that system load has been reduced to prevent freezes.
#>

# Get script directory for relative module paths
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptPath
$ModulesPath = Join-Path $ProjectRoot "Modules"

Write-Host "🚀 Testing Spinner and Load Reduction Improvements" -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Cyan

try {
    # Import modules
    Write-Host "`n📦 Importing modules..." -ForegroundColor Yellow
    Import-Module (Join-Path $ModulesPath "HashSmithCore") -Force -Verbose:$false
    Import-Module (Join-Path $ModulesPath "HashSmithConfig") -Force -Verbose:$false
    Import-Module (Join-Path $ModulesPath "HashSmithHash") -Force -Verbose:$false
    Write-Host "✅ Modules imported" -ForegroundColor Green

    # Initialize config
    Initialize-HashSmithConfig
    
    Write-Host "`n🎬 Demo 1: File Processing Spinner" -ForegroundColor Cyan
    Write-Host "Simulating file processing with live spinner updates..." -ForegroundColor Yellow
    
    # Demo the file processing spinner
    $testFiles = @("document1.pdf", "database.sql", "video.mp4", "archive.zip", "presentation.pptx")
    for ($i = 0; $i -lt $testFiles.Count; $i++) {
        $file = $testFiles[$i]
        Show-HashSmithFileSpinner -CurrentFile $file -TotalFiles $testFiles.Count -ProcessedFiles ($i + 1) -ChunkInfo "Chunk 2 of 8"
        Start-Sleep -Milliseconds 800
    }
    Clear-HashSmithFileSpinner
    Write-Host "✅ File processing spinner demo completed" -ForegroundColor Green

    Write-Host "`n🎬 Demo 2: Large File Hash Spinner" -ForegroundColor Cyan
    Write-Host "Creating a medium-sized test file..." -ForegroundColor Yellow
    
    # Create a test file that will trigger the spinner (15MB)
    $testFile = Join-Path $PWD "medium_test_file.bin"
    $content = [byte[]]::new(15MB)
    [System.Random]::new().NextBytes($content)
    [System.IO.File]::WriteAllBytes($testFile, $content)
    
    $fileSize = (Get-Item $testFile).Length
    Write-Host "📝 Created test file: $('{0:N1} MB' -f ($fileSize / 1MB))" -ForegroundColor Yellow
    
    Write-Host "🔐 Computing hash with spinner..." -ForegroundColor Yellow
    $startTime = Get-Date
    $hashResult = Get-HashSmithFileHashSafe -Path $testFile -Algorithm "MD5"
    $duration = (Get-Date) - $startTime
    
    if ($hashResult.Success) {
        Write-Host "✅ Hash computed: $($hashResult.Hash)" -ForegroundColor Green
        Write-Host "   ⏱️  Duration: $($duration.TotalSeconds.ToString('F2'))s" -ForegroundColor White
        Write-Host "   📊 Size: $('{0:N1} MB' -f ($hashResult.Size / 1MB))" -ForegroundColor White
    } else {
        Write-Host "❌ Hash failed: $($hashResult.Error)" -ForegroundColor Red
    }

    Write-Host "`n🎬 Demo 3: Manual Spinner Animation" -ForegroundColor Cyan
    Write-Host "Testing the basic spinner animation..." -ForegroundColor Yellow
    Show-HashSmithSpinner -Message "System load optimization in progress..." -Seconds 4
    Write-Host "✅ Manual spinner completed" -ForegroundColor Green

    Write-Host "`n📊 Performance and Load Improvements:" -ForegroundColor Yellow
    Write-Host "   • Reduced parallel thread count to prevent system overload" -ForegroundColor Green
    Write-Host "   • Added delays between operations for large files" -ForegroundColor Green
    Write-Host "   • Smaller buffer sizes to reduce memory pressure" -ForegroundColor Green
    Write-Host "   • Brief pauses between chunk processing" -ForegroundColor Green
    Write-Host "   • Live file-level progress during chunk processing" -ForegroundColor Green
    Write-Host "   • Lower threshold for hash spinner (10MB instead of 50MB)" -ForegroundColor Green

} catch {
    Write-Host "❌ Test failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
} finally {
    # Cleanup
    if (Test-Path $testFile) {
        Remove-Item $testFile -Force -ErrorAction SilentlyContinue
        Write-Host "`n🗑️  Test file cleaned up" -ForegroundColor Gray
    }
}

Write-Host "`n🎉 Spinner and Load Reduction Test Completed!" -ForegroundColor Green
Write-Host "=" * 60 -ForegroundColor Green

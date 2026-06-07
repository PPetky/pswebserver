#Requires -Version 5.1
<#
.SYNOPSIS
    Test script for attachment handling feature
.DESCRIPTION
    This script demonstrates how to:
    - Create sample attachment files
    - View attachments in browser
    - Download attachments
.EXAMPLE
    .\Test-Attachments.ps1
#>

param(
    [string]$ServerUrl = "http://localhost:8080"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "╔═══════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║    Attachment Handling Feature Test           ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

$attachmentsDir = Join-Path $PSScriptRoot "attachments"

# Function to test attachment retrieval
function Test-Attachment {
    param(
        [int]$Id,
        [string]$Description
    )
    
    Write-Host "[TEST] Testing attachment #$Id - $Description" -ForegroundColor Yellow
    
    try {
        $url = "$ServerUrl/attachments/$Id"
        Write-Host "  → URL: $url" -ForegroundColor Gray
        
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing
        Write-Host "  ✓ Status: $($response.StatusCode)" -ForegroundColor Green
        Write-Host "  ✓ Content-Type: $($response.Headers['Content-Type'])" -ForegroundColor Green
        Write-Host "  ✓ Size: $($response.Content.Length) bytes" -ForegroundColor Green
        
        if ($response.Headers['Content-Disposition']) {
            Write-Host "  ✓ Disposition: $($response.Headers['Content-Disposition'])" -ForegroundColor Green
        }
        
        Write-Host ""
        return $true
    } catch {
        Write-Host "  ✗ Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
        return $false
    }
}

# Test existing attachments from attachments.json
Write-Host "═══ Testing Existing Attachments ═══" -ForegroundColor Cyan
Write-Host ""

# Read attachments.json to see what IDs exist
$attachmentsJson = Join-Path $PSScriptRoot "data\attachments.json"
if (Test-Path $attachmentsJson) {
    $attachments = Get-Content $attachmentsJson -Raw | ConvertFrom-Json
    Write-Host "Found $(@($attachments).Count) attachments in database" -ForegroundColor Cyan
    Write-Host ""
    
    foreach ($att in $attachments) {
        $table = if ($att.content) { " - table: $($att.content)" } else { "" }
        $desc = "$($att.content_type) - parent: $($att.parent)$table"
        Test-Attachment -Id $att.id -Description $desc
    }
} else {
    Write-Host "No attachments.json found" -ForegroundColor Yellow
    Write-Host ""
}

# Create a sample attachment for testing
Write-Host "═══ Creating Sample Test Attachment ═══" -ForegroundColor Cyan
Write-Host ""

$testFile = Join-Path $attachmentsDir "sample_test.txt"
$testContent = @"
Sample Attachment File
======================

This is a test attachment created by Test-Attachments.ps1
Timestamp: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

You can view this file at: $ServerUrl/attachments/{id}
Add ?download=1 to force download: $ServerUrl/attachments/{id}?download=1
"@

try {
    $testContent | Set-Content -Path $testFile -Encoding UTF8
    Write-Host "✓ Created sample file: $testFile" -ForegroundColor Green
    Write-Host ""
} catch {
    Write-Host "✗ Failed to create sample file: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
}

# Display usage instructions
Write-Host "═══ Usage Instructions ═══" -ForegroundColor Cyan
Write-Host ""
Write-Host "View Attachment (inline):" -ForegroundColor White
Write-Host "  $ServerUrl/attachments/{id}" -ForegroundColor Gray
Write-Host ""
Write-Host "Download Attachment (force download):" -ForegroundColor White
Write-Host "  $ServerUrl/attachments/{id}?download=1" -ForegroundColor Gray
Write-Host ""
Write-Host "API Endpoints:" -ForegroundColor White
Write-Host "  GET    $ServerUrl/api/attachments        - List all attachments" -ForegroundColor Gray
Write-Host "  GET    $ServerUrl/api/attachments/{id}   - Get attachment metadata" -ForegroundColor Gray
Write-Host "  POST   $ServerUrl/api/attachments        - Create attachment record" -ForegroundColor Gray
Write-Host "  PUT    $ServerUrl/api/attachments/{id}   - Update attachment metadata" -ForegroundColor Gray
Write-Host "  DELETE $ServerUrl/api/attachments/{id}   - Delete attachment record" -ForegroundColor Gray
Write-Host ""
Write-Host "Examples using PowerShell:" -ForegroundColor White
Write-Host ""
Write-Host "  # List all attachments" -ForegroundColor DarkGray
Write-Host "  Invoke-RestMethod -Uri '$ServerUrl/api/attachments'" -ForegroundColor Gray
Write-Host ""
Write-Host "  # View attachment #1 in browser" -ForegroundColor DarkGray
Write-Host "  Start-Process '$ServerUrl/attachments/1'" -ForegroundColor Gray
Write-Host ""
Write-Host "  # Download attachment #1" -ForegroundColor DarkGray
Write-Host "  Invoke-WebRequest -Uri '$ServerUrl/attachments/1?download=1' -OutFile 'downloaded_file.txt'" -ForegroundColor Gray
Write-Host ""
Write-Host "═══ Test Complete ═══" -ForegroundColor Green
Write-Host ""

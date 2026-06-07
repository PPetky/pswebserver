#Requires -Version 5.1
<#
.SYNOPSIS
    Helper script to add new attachments to the PowerShell Web Server
.DESCRIPTION
    This script helps you create attachment records in attachments.json
    and copy files to the attachments folder with proper metadata.
.PARAMETER FilePath
    Path to the file you want to attach
.PARAMETER Parent
    Parent record ID (optional)
.PARAMETER Creator
    Creator identifier (optional)
.PARAMETER Table
    Table name to store in content field (optional, e.g., "carthoteca")
.PARAMETER ServerUrl
    Base URL of the web server (default: http://localhost:8080)
.EXAMPLE
    .\Add-Attachment.ps1 -FilePath "C:\Documents\report.pdf" -Parent 22 -Table "carthoteca"
.EXAMPLE
    .\Add-Attachment.ps1 -FilePath ".\image.jpg" -Creator "user1" -Table "products"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$FilePath,
    
    [string]$Parent = "",
    [string]$Creator = "",
    [string]$Table = "",
    [string]$ServerUrl = "http://localhost:8080"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Check if file exists
if (-not (Test-Path $FilePath)) {
    Write-Host "✗ Error: File not found: $FilePath" -ForegroundColor Red
    exit 1
}

$file = Get-Item $FilePath
$fileName = $file.Name
$attachmentsDir = Join-Path $PSScriptRoot "attachments"

# Ensure attachments directory exists
if (-not (Test-Path $attachmentsDir)) {
    New-Item -ItemType Directory -Path $attachmentsDir | Out-Null
}

# Determine content type from extension
$contentTypes = @{
    ".txt"  = "text/plain"
    ".pdf"  = "application/pdf"
    ".doc"  = "application/msword"
    ".docx" = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    ".xls"  = "application/vnd.ms-excel"
    ".xlsx" = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    ".png"  = "image/png"
    ".jpg"  = "image/jpeg"
    ".jpeg" = "image/jpeg"
    ".gif"  = "image/gif"
    ".bmp"  = "image/bmp"
    ".webp" = "image/webp"
    ".mp3"  = "audio/mpeg"
    ".mp4"  = "video/mp4"
    ".zip"  = "application/zip"
    ".rar"  = "application/x-rar-compressed"
    ".7z"   = "application/x-7z-compressed"
}

$ext = $file.Extension.ToLower()
$contentType = if ($contentTypes.ContainsKey($ext)) { 
    $contentTypes[$ext] 
} else { 
    "application/octet-stream" 
}

Write-Host "╔═══════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║         Add Attachment to Web Server          ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

Write-Host "File Information:" -ForegroundColor Yellow
Write-Host "  Name         : $fileName" -ForegroundColor Gray
Write-Host "  Size         : $($file.Length) bytes" -ForegroundColor Gray
Write-Host "  Content Type : $contentType" -ForegroundColor Gray
Write-Host "  Parent       : $(if ($Parent) { $Parent } else { '(none)' })" -ForegroundColor Gray
Write-Host "  Creator      : $(if ($Creator) { $Creator } else { '(none)' })" -ForegroundColor Gray
Write-Host "  Table        : $(if ($Table) { $Table } else { '(none)' })" -ForegroundColor Gray
Write-Host ""

# Copy file to attachments directory
$destPath = Join-Path $attachmentsDir $fileName
if (Test-Path $destPath) {
    # Generate unique name if file already exists
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
    $extension = $file.Extension
    $counter = 1
    do {
        $fileName = "${baseName}_${counter}${extension}"
        $destPath = Join-Path $attachmentsDir $fileName
        $counter++
    } while (Test-Path $destPath)
    Write-Host "⚠ File exists, using unique name: $fileName" -ForegroundColor Yellow
}

try {
    Copy-Item -Path $FilePath -Destination $destPath -Force
    Write-Host "✓ Copied file to: $destPath" -ForegroundColor Green
} catch {
    Write-Host "✗ Failed to copy file: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Create attachment record via API
Write-Host ""
Write-Host "Creating attachment record..." -ForegroundColor Yellow

$body = @{
    file_name    = $fileName
    content_type = $contentType
    parent       = $Parent
    creator      = $Creator
    content      = $Table
} | ConvertTo-Json

try {
    $response = Invoke-RestMethod -Uri "$ServerUrl/api/attachments" `
        -Method POST `
        -ContentType "application/json" `
        -Body $body
    
    Write-Host "✓ Attachment record created successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Attachment Details:" -ForegroundColor Cyan
    Write-Host "  ID           : $($response.id)" -ForegroundColor White
    Write-Host "  File Name    : $($response.file_name)" -ForegroundColor White
    Write-Host "  Content Type : $($response.content_type)" -ForegroundColor White
    Write-Host "  Created At   : $($response.createdAt)" -ForegroundColor White
    Write-Host ""
    Write-Host "Access URLs:" -ForegroundColor Cyan
    Write-Host "  View         : $ServerUrl/attachments/$($response.id)" -ForegroundColor Gray
    Write-Host "  Download     : $ServerUrl/attachments/$($response.id)?download=1" -ForegroundColor Gray
    Write-Host "  List Page    : $ServerUrl/attachments" -ForegroundColor Gray
    Write-Host ""
    
    # Ask if user wants to open in browser
    Write-Host "Open in browser? (Y/N): " -NoNewline -ForegroundColor Yellow
    $answer = Read-Host
    if ($answer -match '^[Yy]') {
        Start-Process "$ServerUrl/attachments/$($response.id)"
    }
    
} catch {
    Write-Host "✗ Failed to create attachment record: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "The file was copied to the attachments folder, but the API request failed." -ForegroundColor Yellow
    Write-Host "Make sure the web server is running at: $ServerUrl" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "═══ Done ═══" -ForegroundColor Green
Write-Host ""

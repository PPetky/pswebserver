#Requires -Version 5.1
<#
.SYNOPSIS
    Test script to verify attachments are properly filtered by table and parent
.DESCRIPTION
    This script tests that the attachments feature correctly filters by:
    - Table name (content field)
    - Parent record ID (parent field)
    - Both combined
#>

param(
    [string]$ServerUrl = "http://localhost:8080"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "╔═══════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║    Test Attachments Filtering by Table       ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Read current attachments
$attachmentsPath = Join-Path $PSScriptRoot "data\attachments.json"
if (-not (Test-Path $attachmentsPath)) {
    Write-Host "✗ No attachments.json found" -ForegroundColor Red
    exit 1
}

$attachments = Get-Content $attachmentsPath -Raw | ConvertFrom-Json
Write-Host "Current Attachments in Database:" -ForegroundColor Yellow
Write-Host "================================" -ForegroundColor Yellow

$groupedByTable = $attachments | Group-Object -Property content

foreach ($group in $groupedByTable) {
    $tableName = if ($group.Name) { $group.Name } else { "(no table)" }
    Write-Host "`n📊 Table: $tableName" -ForegroundColor Cyan
    foreach ($att in $group.Group) {
        Write-Host "   ID: $($att.id) | Parent: $($att.parent) | Type: $($att.content_type)" -ForegroundColor Gray
    }
}

Write-Host "`n" 
Write-Host "Test Scenarios:" -ForegroundColor Yellow
Write-Host "==============" -ForegroundColor Yellow

# Test 1: Filter by table only
Write-Host "`n1️⃣  Testing filter by table='carthoteca'" -ForegroundColor Cyan
try {
    $response = Invoke-WebRequest -Uri "$ServerUrl/attachments?table=carthoteca" -UseBasicParsing
    if ($response.StatusCode -eq 200) {
        $count = ([regex]::Matches($response.Content, 'attachment-card')).Count
        Write-Host "   ✓ Success! Found $count attachments for table 'carthoteca'" -ForegroundColor Green
        Write-Host "   URL: $ServerUrl/attachments?table=carthoteca" -ForegroundColor Gray
    }
} catch {
    Write-Host "   ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 2: Filter by parent only
Write-Host "`n2️⃣  Testing filter by parent='1'" -ForegroundColor Cyan
try {
    $response = Invoke-WebRequest -Uri "$ServerUrl/attachments?parent=1" -UseBasicParsing
    if ($response.StatusCode -eq 200) {
        $count = ([regex]::Matches($response.Content, 'attachment-card')).Count
        Write-Host "   ✓ Success! Found $count attachments for parent '1'" -ForegroundColor Green
        Write-Host "   URL: $ServerUrl/attachments?parent=1" -ForegroundColor Gray
    }
} catch {
    Write-Host "   ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 3: Filter by both table and parent
Write-Host "`n3️⃣  Testing filter by table='carthoteca' AND parent='2'" -ForegroundColor Cyan
try {
    $response = Invoke-WebRequest -Uri "$ServerUrl/attachments?table=carthoteca&parent=2" -UseBasicParsing
    if ($response.StatusCode -eq 200) {
        $count = ([regex]::Matches($response.Content, 'attachment-card')).Count
        Write-Host "   ✓ Success! Found $count attachments for carthoteca #2" -ForegroundColor Green
        Write-Host "   URL: $ServerUrl/attachments?table=carthoteca&parent=2" -ForegroundColor Gray
    }
} catch {
    Write-Host "   ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 4: No filters (show all)
Write-Host "`n4️⃣  Testing without filters (show all)" -ForegroundColor Cyan
try {
    $response = Invoke-WebRequest -Uri "$ServerUrl/attachments" -UseBasicParsing
    if ($response.StatusCode -eq 200) {
        $count = ([regex]::Matches($response.Content, 'attachment-card')).Count
        Write-Host "   ✓ Success! Found $count total attachments" -ForegroundColor Green
        Write-Host "   URL: $ServerUrl/attachments" -ForegroundColor Gray
    }
} catch {
    Write-Host "   ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n" 
Write-Host "Expected Behavior:" -ForegroundColor Yellow
Write-Host "==================" -ForegroundColor Yellow
Write-Host "• Test 1 should only show attachments where content='carthoteca'" -ForegroundColor Gray
Write-Host "• Test 2 should only show attachments where parent='1' (any table)" -ForegroundColor Gray
Write-Host "• Test 3 should only show attachments where BOTH conditions match" -ForegroundColor Gray
Write-Host "• Test 4 should show ALL attachments regardless of table/parent" -ForegroundColor Gray

Write-Host "`n" 
Write-Host "═══ Test Complete ═══" -ForegroundColor Green
Write-Host ""
Write-Host "To test manually, visit:" -ForegroundColor Cyan
Write-Host "  • $ServerUrl/tables/carthoteca" -ForegroundColor Gray
Write-Host "  • Click on an attachment badge (📎) to see filtered results" -ForegroundColor Gray
Write-Host ""

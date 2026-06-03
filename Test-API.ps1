#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Quick REST API tester for the PS WebServer.
    Run this in a second terminal while the server is running.
#>
param([int]$Port = 8080)

$base = "http://localhost:$Port"

function Show-Result {
    param([string]$Label, $Result)
    Write-Host "`n--- $Label ---" -ForegroundColor Cyan
    $Result | ConvertTo-Json -Depth 5 | Write-Host -ForegroundColor White
}

Write-Host "`nPS WebServer API Tester - port $Port`n" -ForegroundColor Yellow

# List tables
$tables = Invoke-RestMethod "$base/api"
Show-Result "Tables" $tables

# CRUD on 'users'
Write-Host "`n[1] List users" -ForegroundColor Green
$list = Invoke-RestMethod "$base/api/users"
Show-Result "Users" $list

Write-Host "`n[2] Create a new user" -ForegroundColor Green
$created = Invoke-RestMethod "$base/api/users" -Method POST `
    -ContentType "application/json" `
    -Body '{"name":"Test User","email":"test@example.com","role":"Tester"}'
Show-Result "Created" $created
$newId = $created.id

Write-Host "`n[3] Get user by ID $newId" -ForegroundColor Green
$got = Invoke-RestMethod "$base/api/users/$newId"
Show-Result "Got" $got

Write-Host "`n[4] Update user $newId" -ForegroundColor Green
$updated = Invoke-RestMethod "$base/api/users/$newId" -Method PATCH `
    -ContentType "application/json" `
    -Body '{"role":"Updated"}'
Show-Result "Updated" $updated

Write-Host "`n[5] Filter by role" -ForegroundColor Green
$filtered = Invoke-RestMethod "$base/api/users?role=Admin"
Show-Result "Filtered (Admin)" $filtered

Write-Host "`n[6] Delete user $newId" -ForegroundColor Green
$deleted = Invoke-RestMethod "$base/api/users/$newId" -Method DELETE
Show-Result "Deleted" $deleted

Write-Host "`n[7] Verify deletion" -ForegroundColor Green
$final = Invoke-RestMethod "$base/api/users"
Show-Result "Final list" $final

Write-Host "`n✅ All tests complete" -ForegroundColor Green

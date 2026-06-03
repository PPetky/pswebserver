#Requires -Version 5.1
<#
.SYNOPSIS
    Pure PowerShell Web Server - No external dependencies required.
.DESCRIPTION
    A self-contained HTTP web server with HTML template rendering,
    JSON-based data storage, and a full CRUD REST API.
    Runs entirely offline - no internet connection needed.
.PARAMETER Port
    TCP port to listen on. Default: 8080
.PARAMETER Host
    Hostname/IP to bind to. Default: localhost
.EXAMPLE
    .\Start-WebServer.ps1
    .\Start-WebServer.ps1 -Port 9000
    .\Start-WebServer.ps1 -Port 8080 -BindHost "0.0.0.0"
#>
param(
    [int]$Port = 8080,
    [string]$BindHost = "localhost"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Load required .NET assembly for encryption
Add-Type -AssemblyName System.Security

# ─── Paths ────────────────────────────────────────────────────────────────────
$ScriptRoot   = $PSScriptRoot
$DataDir      = Join-Path $ScriptRoot "data"
$TemplatesDir = Join-Path $ScriptRoot "templates"
$StaticDir    = Join-Path $ScriptRoot "static"

foreach ($dir in @($DataDir, $TemplatesDir, $StaticDir)) {
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
}

# ─── Logging ──────────────────────────────────────────────────────────────────
function Write-Log {
    param([string]$Level, [string]$Message)
    $colors = @{ INFO="Cyan"; WARN="Yellow"; ERROR="Red"; OK="Green"; REQ="Magenta" }
    $ts = Get-Date -Format "HH:mm:ss"
    $color = if ($colors.ContainsKey($Level)) { $colors[$Level] } else { "White" }
    Write-Host "[$ts] " -NoNewline -ForegroundColor DarkGray
    Write-Host "[$Level] " -NoNewline -ForegroundColor $color
    Write-Host $Message
}

# ─── MIME Types ───────────────────────────────────────────────────────────────
$MimeTypes = @{
    ".html" = "text/html; charset=utf-8"
    ".css"  = "text/css; charset=utf-8"
    ".js"   = "application/javascript; charset=utf-8"
    ".json" = "application/json; charset=utf-8"
    ".png"  = "image/png"
    ".jpg"  = "image/jpeg"
    ".jpeg" = "image/jpeg"
    ".gif"  = "image/gif"
    ".svg"  = "image/svg+xml"
    ".ico"  = "image/x-icon"
    ".txt"  = "text/plain; charset=utf-8"
    ".woff" = "font/woff"
    ".woff2"= "font/woff2"
}

function Get-MimeType([string]$ext) {
    if ($MimeTypes.ContainsKey($ext)) { return $MimeTypes[$ext] }
    return "application/octet-stream"
}

# ─── JSON Storage ─────────────────────────────────────────────────────────────

# Configuration: Protected fields per table (will be encrypted/decrypted automatically)
$ProtectedFields = @{
    "users"      = @("passport_data", "real_name", "residence_address", "registration_place", "birth_place")
    "carthoteca" = @("passport_data", "real_name", "residence_address", "registration_place", "birth_place")
    # Add more tables and fields as needed
}

# Encrypt a field value using Windows Data Protection API (DPAPI)
function Protect-Field([string]$value) {
    if ([string]::IsNullOrEmpty($value)) { return $value }
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($value)
        $encrypted = [Security.Cryptography.ProtectedData]::Protect(
            $bytes, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        return [Convert]::ToBase64String($encrypted)
    } catch {
        Write-Log "WARN" "Failed to encrypt field: $_"
        return $value
    }
}

# Decrypt a field value using Windows Data Protection API (DPAPI)
function Unprotect-Field([string]$value) {
    if ([string]::IsNullOrEmpty($value)) { return $value }
    try {
        $encrypted = [Convert]::FromBase64String($value)
        $decrypted = [Security.Cryptography.ProtectedData]::Unprotect(
            $encrypted, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        return [Text.Encoding]::UTF8.GetString($decrypted)
    } catch {
        # If decryption fails, assume it's plaintext (backward compatibility)
        return $value
    }
}

function Get-TablePath([string]$table) {
    # Sanitise: only alphanumeric + underscores allowed
    if ($table -notmatch '^[a-zA-Z0-9_]+$') { throw "Invalid table name: $table" }
    return Join-Path $DataDir "$table.json"
}

function Read-Table([string]$table) {
    $path = Get-TablePath $table
    if (-not (Test-Path $path)) { return @() }
    $raw = Get-Content -Path $path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
    $parsed = $raw | ConvertFrom-Json
    # Always return an array
    if ($parsed -is [System.Array]) { $result = [object[]]$parsed }
    else { $result = @($parsed) }
    
    # Decrypt protected fields if configured for this table
    if ($ProtectedFields.ContainsKey($table)) {
        $fieldsToDecrypt = $ProtectedFields[$table]
        foreach ($row in $result) {
            foreach ($fieldName in $fieldsToDecrypt) {
                if ($row.PSObject.Properties[$fieldName] -and $row.$fieldName) {
                    $row.$fieldName = Unprotect-Field $row.$fieldName
                }
            }
        }
    }
    
    return $result
}

function Write-Table([string]$table, [object[]]$rows) {
    $path = Get-TablePath $table
    
    # Encrypt protected fields if configured for this table
    if ($ProtectedFields.ContainsKey($table)) {
        $fieldsToEncrypt = $ProtectedFields[$table]
        # Create a deep copy to avoid modifying the original objects
        $rowsToSave = @()
        foreach ($row in $rows) {
            $rowCopy = $row | ConvertTo-Json -Depth 10 | ConvertFrom-Json
            foreach ($fieldName in $fieldsToEncrypt) {
                if ($rowCopy.PSObject.Properties[$fieldName] -and $rowCopy.$fieldName) {
                    $rowCopy.$fieldName = Protect-Field $rowCopy.$fieldName
                }
            }
            $rowsToSave += $rowCopy
        }
        $rowsToSave | ConvertTo-Json -Depth 10 | Set-Content -Path $path -Encoding UTF8
    } else {
        $rows | ConvertTo-Json -Depth 10 | Set-Content -Path $path -Encoding UTF8
    }
}

function New-Row([string]$table, [hashtable]$fields) {
    $rows = @(Read-Table $table)
    # Generate next ID - find the maximum ID in all rows
    $maxId = 0
    foreach ($r in $rows) {
        $id = 0
        if ($r.PSObject.Properties["id"]) {
            $idStr = $r.id.ToString().Trim()
            # Skip empty IDs (likely from template records)
            if ($idStr -ne "" -and [int]::TryParse($idStr, [ref]$id)) {
                if ($id -gt $maxId) { $maxId = $id }
            }
        }
    }
    $fields["id"]        = $maxId + 1
    $fields["createdAt"] = (Get-Date -Format "o")
    $fields["updatedAt"] = (Get-Date -Format "o")
    $rows += [PSCustomObject]$fields
    Write-Table $table ([object[]]$rows)
    return $fields
}

function Update-Row([string]$table, [int]$id, [hashtable]$fields) {
    $rows = @(Read-Table $table)
    $found = $false
    $updated = $null
    $newRows = @()
    foreach ($r in $rows) {
        $rid = 0
        if ($r.PSObject.Properties["id"] -and [int]::TryParse($r.id.ToString(), [ref]$rid) -and $rid -eq $id) {
            foreach ($k in $fields.Keys) {
                if ($k -ne "id" -and $k -ne "createdAt") {
                    $r | Add-Member -MemberType NoteProperty -Name $k -Value $fields[$k] -Force
                }
            }
            $r | Add-Member -MemberType NoteProperty -Name "updatedAt" -Value (Get-Date -Format "o") -Force
            $found = $true
            $updated = $r
        }
        $newRows += $r
    }
    if (-not $found) { return $null }
    Write-Table $table ([object[]]$newRows)
    return $updated
}

function Remove-Row([string]$table, [int]$id) {
    $rows = @(Read-Table $table)
    $found = $false
    $newRows = @()
    foreach ($r in $rows) {
        $rid = 0
        if ($r.PSObject.Properties["id"] -and [int]::TryParse($r.id.ToString(), [ref]$rid) -and $rid -eq $id) {
            $found = $true
            continue
        }
        $newRows += $r
    }
    if (-not $found) { return $false }
    Write-Table $table ([object[]]$newRows)
    return $true
}

# ─── Template Engine ──────────────────────────────────────────────────────────
# Supports: {{variable}}, {{#each items}}...{{/each}}, {{#if cond}}...{{/if}},
#           {{> partial}}, {{{raw_html}}}
function Invoke-Template {
    param(
        [string]$TemplateName,
        [hashtable]$Data = @{}
    )

    $path = Join-Path $TemplatesDir $TemplateName
    if (-not (Test-Path $path)) {
        throw "Template not found: $TemplateName"
    }
    $content = Get-Content -Path $path -Raw -Encoding UTF8
    return Render-Template $content $Data
}

function Render-Template {
    param([string]$Template, [hashtable]$Data)

    # 1. Partials: {{> partial_name}}
    $Template = [regex]::Replace($Template, '\{\{>\s*(\w[\w/.-]*)\s*\}\}', {
        param($m)
        $pname = $m.Groups[1].Value
        $ppath = Join-Path $TemplatesDir "partials/$pname.html"
        if (Test-Path $ppath) {
            $pc = Get-Content -Path $ppath -Raw -Encoding UTF8
            return Render-Template $pc $Data
        }
        return ""
    })

    # 2. Each blocks: {{#each items}} ... {{/each}}
    # Process loops recursively, expanding from the outside in
    function Process-Each([string]$tmpl, [hashtable]$ctx) {
        $startMatch = [regex]::Match($tmpl, '\{\{#each\s+(\w+)\}\}')
        if (-not $startMatch.Success) { return $tmpl }
        
        $key = $startMatch.Groups[1].Value
        $startPos = $startMatch.Index + $startMatch.Length
        
        # Find matching {{/each}} using character-by-character scanning
        $nesting = 0
        $pos = $startPos
        $endPos = -1
        while ($pos -lt $tmpl.Length) {
            if ($tmpl.Substring($pos).StartsWith('{{#each')) {
                $nesting++
                $pos += 7
            } elseif ($tmpl.Substring($pos).StartsWith('{{/each}}')) {
                if ($nesting -eq 0) {
                    $endPos = $pos
                    break
                }
                $nesting--
                $pos += 9
            } else {
                $pos++
            }
        }
        
        if ($endPos -eq -1) { return $tmpl }
        
        $inner = $tmpl.Substring($startPos, $endPos - $startPos)
        
        $items = $null
        if ($ctx.ContainsKey($key)) { $items = $ctx[$key] }
        
        $result = ""
        if ($null -ne $items) {
            $arr = @($items)
            for ($i = 0; $i -lt $arr.Count; $i++) {
                $item = $arr[$i]
                $newCtx = @{}
                foreach ($k in $ctx.Keys) { $newCtx[$k] = $ctx[$k] }
                if ($item -is [hashtable]) {
                    foreach ($k in $item.Keys) { $newCtx[$k] = $item[$k] }
                } elseif ($null -ne $item -and $item -isnot [string] -and $item -isnot [int]) {
                    foreach ($p in $item.PSObject.Properties) { $newCtx[$p.Name] = $p.Value }
                } else {
                    $newCtx["this"] = $item
                }
                $newCtx["@index"] = $i
                $newCtx["@first"] = ($i -eq 0).ToString().ToLower()
                $newCtx["@last"] = ($i -eq $arr.Count - 1).ToString().ToLower()
                # Recursively expand inner content with row context (nested loops will be processed here)
                $result += Render-Template $inner $newCtx
            }
        }
        
        $newTmpl = $tmpl.Substring(0, $startMatch.Index) + $result + $tmpl.Substring($endPos + 9)
        return Process-Each $newTmpl $ctx
    }
    
    $Template = Process-Each $Template $Data

    # 3. If/else blocks: {{#if key}} ... {{else}} ... {{/if}}
    # Process if blocks recursively to handle nesting
    function Process-If([string]$tmpl, [hashtable]$ctx) {
        $startMatch = [regex]::Match($tmpl, '\{\{#if\s+(\w+)\}\}')
        if (-not $startMatch.Success) { return $tmpl }
        
        $key = $startMatch.Groups[1].Value
        $startPos = $startMatch.Index + $startMatch.Length
        
        # Find matching {{/if}} using character-by-character scanning
        $nesting = 0
        $pos = $startPos
        $endPos = -1
        $elsePos = -1
        while ($pos -lt $tmpl.Length) {
            if ($tmpl.Substring($pos).StartsWith('{{#if')) {
                $nesting++
                $pos += 5
            } elseif ($tmpl.Substring($pos).StartsWith('{{/if}}')) {
                if ($nesting -eq 0) {
                    $endPos = $pos
                    break
                }
                $nesting--
                $pos += 7
            } elseif ($tmpl.Substring($pos).StartsWith('{{else}}') -and $nesting -eq 0 -and $elsePos -eq -1) {
                $elsePos = $pos
                $pos += 7
            } else {
                $pos++
            }
        }
        
        if ($endPos -eq -1) { return $tmpl }
        
        # Extract parts
        if ($elsePos -eq -1) {
            $truePart = $tmpl.Substring($startPos, $endPos - $startPos)
            $falsePart = ""
        } else {
            $truePart = $tmpl.Substring($startPos, $elsePos - $startPos)
            $falsePart = $tmpl.Substring($elsePos + 7, $endPos - ($elsePos + 7))
        }
        
        # Evaluate condition
        $val = $null
        if ($ctx.ContainsKey($key)) { $val = $ctx[$key] }
        $truthy = $false
        if ($null -ne $val) {
            if ($val -is [bool])   { $truthy = $val }
            elseif ($val -is [int]) { $truthy = ($val -ne 0) }
            elseif ($val -is [string]) { $truthy = ($val -ne "" -and $val -ne "false" -and $val -ne "0") }
            elseif ($val -is [System.Array] -or $val -is [System.Collections.IList]) { $truthy = ($val.Count -gt 0) }
            else { $truthy = $true }
        }
        
        $part = if ($truthy) { $truePart } else { $falsePart }
        $result = Render-Template $part $ctx
        
        # Build result and recurse
        $newTmpl = $tmpl.Substring(0, $startMatch.Index) + $result + $tmpl.Substring($endPos + 7)
        return Process-If $newTmpl $ctx
    }
    
    $Template = Process-If $Template $Data

    # 4. Raw HTML (no escaping): {{{variable}}}
    $Template = [regex]::Replace($Template, '\{\{\{(\w+)\}\}\}', {
        param($m)
        $key = $m.Groups[1].Value
        if ($Data.ContainsKey($key)) { return [string]$Data[$key] }
        return ""
    })

    # 5. Escaped variables: {{variable}}
    $Template = [regex]::Replace($Template, '\{\{(\w+)\}\}', {
        param($m)
        $key = $m.Groups[1].Value
        if ($Data.ContainsKey($key)) {
            return [System.Web.HttpUtility]::HtmlEncode([string]$Data[$key])
        }
        return ""
    })

    return $Template
}

# ─── Response Helpers ─────────────────────────────────────────────────────────
function Send-Response {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [int]$StatusCode = 200,
        [string]$ContentType = "text/html; charset=utf-8",
        [string]$Body = "",
        [byte[]]$BodyBytes = $null
    )
    $Response.StatusCode = $StatusCode
    $Response.ContentType = $ContentType
    $Response.Headers.Add("X-Powered-By", "PowerShell-WebServer")
    $Response.Headers.Add("Cache-Control", "no-cache")

    if ($null -eq $BodyBytes) {
        $BodyBytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
    }
    $Response.ContentLength64 = $BodyBytes.Length
    $Response.OutputStream.Write($BodyBytes, 0, $BodyBytes.Length)
    $Response.OutputStream.Close()
}

function Send-Json {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [int]$StatusCode = 200,
        [object]$Data
    )
    $json = $Data | ConvertTo-Json -Depth 10 -Compress
    Send-Response -Response $Response -StatusCode $StatusCode `
        -ContentType "application/json; charset=utf-8" -Body $json
}

function Send-Html {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [int]$StatusCode = 200,
        [string]$Html
    )
    Send-Response -Response $Response -StatusCode $StatusCode `
        -ContentType "text/html; charset=utf-8" -Body $Html
}

function Send-Error {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [int]$StatusCode,
        [string]$Message
    )
    try {
        $html = Invoke-Template "error.html" @{ 
            title   = "Error $StatusCode"
            code    = $StatusCode
            message = $Message
        }
        Send-Html -Response $Response -StatusCode $StatusCode -Html $html
    } catch {
        Send-Response -Response $Response -StatusCode $StatusCode `
            -ContentType "text/plain; charset=utf-8" -Body "Error $StatusCode : $Message"
    }
}

# ─── Body Reader ──────────────────────────────────────────────────────────────
function Read-RequestBody([System.Net.HttpListenerRequest]$Request) {
    if (-not $Request.HasEntityBody) { return "" }
    $reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
    $body = $reader.ReadToEnd()
    $reader.Close()
    return $body
}

function Parse-JsonBody([string]$Body) {
    if ([string]::IsNullOrWhiteSpace($Body)) { return @{} }
    try {
        $obj = $Body | ConvertFrom-Json
        $ht = @{}
        foreach ($p in $obj.PSObject.Properties) { $ht[$p.Name] = $p.Value }
        return $ht
    } catch {
        throw "Invalid JSON body"
    }
}

function Parse-FormBody([string]$Body) {
    $ht = @{}
    foreach ($pair in $Body -split "&") {
        $kv = $pair -split "=", 2
        if ($kv.Count -eq 2) {
            $k = [System.Web.HttpUtility]::UrlDecode($kv[0].Trim())
            $v = [System.Web.HttpUtility]::UrlDecode($kv[1].Trim())
            $ht[$k] = $v
        }
    }
    return $ht
}

# ─── Router ───────────────────────────────────────────────────────────────────
function Invoke-Router {
    param(
        [System.Net.HttpListenerRequest]$Request,
        [System.Net.HttpListenerResponse]$Response
    )

    $method = $Request.HttpMethod.ToUpper()
    $rawUrl = $Request.Url.AbsolutePath.TrimEnd("/")
    if ($rawUrl -eq "") { $rawUrl = "/" }

    Write-Log "REQ" "$method $rawUrl"

    try {
        # ── Static files ──────────────────────────────────────────────────────
        if ($rawUrl -match '^/static/') {
            $relPath  = $rawUrl -replace '^/static', ''
            $filePath = Join-Path $StaticDir ($relPath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
            if (Test-Path $filePath -PathType Leaf) {
                $bytes = [System.IO.File]::ReadAllBytes($filePath)
                $ext   = [System.IO.Path]::GetExtension($filePath).ToLower()
                Send-Response -Response $Response -ContentType (Get-MimeType $ext) -BodyBytes $bytes
            } else {
                Send-Error $Response 404 "Static file not found: $rawUrl"
            }
            return
        }

        # ── REST API: /api/{table}[/{id}] ─────────────────────────────────────
        if ($rawUrl -match '^/api/([a-zA-Z0-9_]+)(?:/(\d+))?$') {
            $table = $Matches[1]
            $idStr = if ($Matches.Count -gt 2) { $Matches[2] } else { "" }
            $id    = 0
            [int]::TryParse($idStr, [ref]$id) | Out-Null

            switch ($method) {
                "GET" {
                    $rows = Read-Table $table
                    # Filter support: ?field=value
                    $query = $Request.QueryString
                    if ($query.Count -gt 0) {
                        $filtered = @()
                        foreach ($r in $rows) {
                            $match = $true
                            foreach ($qk in $query.AllKeys) {
                                $qv = $query[$qk]
                                $rv = $null
                                if ($r.PSObject.Properties[$qk]) { $rv = [string]$r.$qk }
                                if ($rv -ne $qv) { $match = $false; break }
                            }
                            if ($match) { $filtered += $r }
                        }
                        $rows = $filtered
                    }
                    if ($id -gt 0) {
                        $row = $rows | Where-Object { $_.id -eq $id } | Select-Object -First 1
                        if ($null -eq $row) { Send-Json $Response 404 @{ error = "Not found" }; return }
                        Send-Json $Response 200 $row
                    } else {
                        Send-Json $Response 200 @{ data = $rows; count = @($rows).Count }
                    }
                }
                "POST" {
                    $body   = Read-RequestBody $Request
                    $fields = Parse-JsonBody $body
                    $row    = New-Row $table $fields
                    Send-Json $Response 201 $row
                }
                "PUT" {
                    if ($id -eq 0) { Send-Json $Response 400 @{ error = "ID required for PUT" }; return }
                    $body   = Read-RequestBody $Request
                    $fields = Parse-JsonBody $body
                    $row    = Update-Row $table $id $fields
                    if ($null -eq $row) { Send-Json $Response 404 @{ error = "Not found" }; return }
                    Send-Json $Response 200 $row
                }
                "PATCH" {
                    if ($id -eq 0) { Send-Json $Response 400 @{ error = "ID required for PATCH" }; return }
                    $body   = Read-RequestBody $Request
                    $fields = Parse-JsonBody $body
                    $row    = Update-Row $table $id $fields
                    if ($null -eq $row) { Send-Json $Response 404 @{ error = "Not found" }; return }
                    Send-Json $Response 200 $row
                }
                "DELETE" {
                    if ($id -eq 0) { Send-Json $Response 400 @{ error = "ID required for DELETE" }; return }
                    $ok = Remove-Row $table $id
                    if (-not $ok) { Send-Json $Response 404 @{ error = "Not found" }; return }
                    Send-Json $Response 200 @{ deleted = $true; id = $id }
                }
                default { Send-Json $Response 405 @{ error = "Method not allowed" } }
            }
            return
        }

        # ── API: list tables ──────────────────────────────────────────────────
        if ($rawUrl -eq "/api" -and $method -eq "GET") {
            $tables = Get-ChildItem -Path $DataDir -Filter "*.json" |
                      Select-Object -ExpandProperty BaseName
            Send-Json $Response 200 @{ tables = @($tables) }
            return
        }

        # ── Page Routes ───────────────────────────────────────────────────────
        Handle-PageRoute -Request $Request -Response $Response -Url $rawUrl -Method $method

    } catch {
        Write-Log "ERROR" $_.Exception.Message
        try { Send-Error $Response 500 $_.Exception.Message } catch {}
    }
}

function Handle-PageRoute {
    param(
        [System.Net.HttpListenerRequest]$Request,
        [System.Net.HttpListenerResponse]$Response,
        [string]$Url,
        [string]$Method
    )

    switch -Regex ($Url) {
        "^/$" {
            # Home / Dashboard
            $tables = @(Get-ChildItem -Path $DataDir -Filter "*.json" | Select-Object -ExpandProperty BaseName)
            $tableInfos = @()
            foreach ($t in $tables) {
                $rows = @(Read-Table $t)
                $tableInfos += @{ name = $t; count = $rows.Count }
            }
            $html = Invoke-Template "index.html" @{
                title      = "Dashboard"
                tableCount = $tables.Count
                rowTotal   = ($tableInfos | Measure-Object -Property count -Sum).Sum
                tables     = $tableInfos
                hasTables  = ($tables.Count -gt 0)
            }
            Send-Html $Response 200 $html
            return
        }

        "^/tables$" {
            # Table list
            $tables = @(Get-ChildItem -Path $DataDir -Filter "*.json" | Select-Object -ExpandProperty BaseName)
            $html = Invoke-Template "tables.html" @{
                title  = "All Tables"
                tables = $tables
            }
            Send-Html $Response 200 $html
            return
        }

        "^/tables/([a-zA-Z0-9_]+)$" {
            $table = $Matches[1]
            if ($Method -eq "POST") {
                # Handle delete action from form
                $body   = Read-RequestBody $Request
                $fields = Parse-FormBody $body
                if ($fields["_action"] -eq "delete" -and $fields["id"]) {
                    $delId = [int]$fields["id"]
                    Remove-Row $table $delId | Out-Null
                }
                $Response.Redirect("/tables/$table")
                $Response.Close()
                return
            }
            $rows   = @(Read-Table $table)
            $cols   = @()
            if ($rows.Count -gt 0) {
                $cols = $rows[0].PSObject.Properties.Name
            }
            $rowMaps = @()
            foreach ($r in $rows) {
                $cells = @()
                foreach ($c in $cols) { $cells += [string]$r.$c }
                $rowMaps += @{ id = [string]$r.id; cells = $cells }
            }
            $html = Invoke-Template "table_view.html" @{
                title   = "Table: $table"
                table   = $table
                columns = $cols
                rows    = $rowMaps
                hasRows = ($rows.Count -gt 0)
                rowCount= $rows.Count
            }
            Send-Html $Response 200 $html
            return
        }

        "^/tables/([a-zA-Z0-9_]+)/new$" {
            $table = $Matches[1]
            if ($Method -eq "POST") {
                $body   = Read-RequestBody $Request
                $fields = Parse-FormBody $body
                $fields.Remove("_action") | Out-Null
                New-Row $table $fields | Out-Null
                $Response.Redirect("/tables/$table")
                $Response.Close()
                return
            }
            # GET: show form - derive columns from existing rows (skip empty template record)
            $rows = @(Read-Table $table)
            $cols = @()
            if ($rows.Count -gt 0) {
                # Use the first record that has actual data (not just the template)
                $dataRow = $null
                foreach ($r in $rows) {
                    $hasData = $false
                    $props = $r.PSObject.Properties.Name | Where-Object { $_ -notin @("id","createdAt","updatedAt") }
                    foreach ($p in $props) {
                        if (-not [string]::IsNullOrWhiteSpace($r.$p)) {
                            $hasData = $true
                            break
                        }
                    }
                    if ($hasData -or $dataRow -eq $null) {
                        $dataRow = $r
                        if ($hasData) { break }
                    }
                }
                if ($dataRow) {
                    # Use hashtable to ensure uniqueness (case-sensitive)
                    $colHash = @{}
                    foreach ($prop in $dataRow.PSObject.Properties.Name) {
                        if ($prop -notin @("id","createdAt","updatedAt")) {
                            $colHash[$prop] = $true
                        }
                    }
                    $cols = @($colHash.Keys)
                }
            }
            # Build fieldRows: array of @{name=...; value=...}
            $fieldRows = @()
            foreach ($c in $cols) { $fieldRows += @{ name = $c; value = "" } }
            $html = Invoke-Template "record_form.html" @{
                title      = "New Record in $table"
                table      = $table
                action     = "Create"
                fieldRows  = $fieldRows
                hasColumns = ($cols.Count -gt 0)
                isNew      = "true"
                id         = ""
            }
            Send-Html $Response 200 $html
            return
        }

        "^/tables/([a-zA-Z0-9_]+)/([0-9]+)/edit$" {
            $table = $Matches[1]
            $id    = [int]$Matches[2]
            if ($Method -eq "POST") {
                $body   = Read-RequestBody $Request
                $fields = Parse-FormBody $body
                $fields.Remove("_action") | Out-Null
                Update-Row $table $id $fields | Out-Null
                $Response.Redirect("/tables/$table")
                $Response.Close()
                return
            }
            $rows = @(Read-Table $table)
            $row  = $rows | Where-Object { $_.id -eq $id } | Select-Object -First 1
            if ($null -eq $row) { Send-Error $Response 404 "Record $id not found in $table"; return }
            # Use hashtable to ensure uniqueness
            $colHash = @{}
            foreach ($prop in $row.PSObject.Properties.Name) {
                if ($prop -notin @("id","createdAt","updatedAt")) {
                    $colHash[$prop] = $true
                }
            }
            $editCols = @($colHash.Keys)
            # Build fieldRows: array of @{name=...; value=...}
            $fieldRows = @()
            foreach ($c in $editCols) { $fieldRows += @{ name = $c; value = [string]$row.$c } }
            $html = Invoke-Template "record_form.html" @{
                title      = "Edit Record #$id in $table"
                table      = $table
                action     = "Update"
                fieldRows  = $fieldRows
                hasColumns = ($editCols.Count -gt 0)
                id         = $id
                isNew      = ""
            }
            Send-Html $Response 200 $html
            return
        }

        "^/create-table$" {
            if ($Method -eq "POST") {
                $body   = Read-RequestBody $Request
                $fields = Parse-FormBody $body
                $tname  = $fields["tableName"] -replace '[^a-zA-Z0-9_]', ''
                if ($tname) {
                    $path = Get-TablePath $tname
                    if (-not (Test-Path $path)) {
                        # Extract field names from form (field_name_1, field_name_2, etc.)
                        $fieldNames = @()
                        foreach ($k in $fields.Keys) {
                            if ($k -match '^field_name_\d+$' -and -not [string]::IsNullOrWhiteSpace($fields[$k])) {
                                $fieldNames += $fields[$k]
                            }
                        }
                        
                        # If fields were defined, create a template record with those fields
                        if ($fieldNames.Count -gt 0) {
                            $templateRow = [PSCustomObject]@{
                                id        = 1
                                createdAt = (Get-Date -Format "o")
                                updatedAt = (Get-Date -Format "o")
                            }
                            # Add user-defined fields to the object
                            foreach ($fname in $fieldNames) {
                                $sanitized = $fname -replace '[^a-zA-Z0-9_]', '_'
                                if ($sanitized) {
                                    $templateRow | Add-Member -MemberType NoteProperty -Name $sanitized -Value "" -Force
                                }
                            }
                            @($templateRow) | ConvertTo-Json -Depth 10 | Set-Content -Path $path -Encoding UTF8
                        } else {
                            "[]" | Set-Content -Path $path -Encoding UTF8
                        }
                    }
                }
                $Response.Redirect("/tables/$tname")
                $Response.Close()
                return
            }
            $html = Invoke-Template "create_table.html" @{ title = "Create Table" }
            Send-Html $Response 200 $html
            return
        }

        default {
            Send-Error $Response 404 "Page not found: $Url"
        }
    }
}

# ─── Bootstrap sample data ────────────────────────────────────────────────────
function Initialize-SampleData {
    $usersPath = Join-Path $DataDir "users.json"
    if (-not (Test-Path $usersPath)) {
        Write-Log "INFO" "Creating sample data..."
        $users = @(
            [PSCustomObject]@{ id=1; name="Alice Smith";  email="alice@example.com"; role="Admin";  createdAt=(Get-Date -Format "o"); updatedAt=(Get-Date -Format "o") },
            [PSCustomObject]@{ id=2; name="Bob Jones";   email="bob@example.com";   role="User";   createdAt=(Get-Date -Format "o"); updatedAt=(Get-Date -Format "o") },
            [PSCustomObject]@{ id=3; name="Carol White"; email="carol@example.com"; role="Editor"; createdAt=(Get-Date -Format "o"); updatedAt=(Get-Date -Format "o") }
        )
        $users | ConvertTo-Json -Depth 5 | Set-Content -Path $usersPath -Encoding UTF8

        $prodPath = Join-Path $DataDir "products.json"
        $products = @(
            [PSCustomObject]@{ id=1; name="Widget A"; price="9.99";  stock="100"; category="Widgets"; createdAt=(Get-Date -Format "o"); updatedAt=(Get-Date -Format "o") },
            [PSCustomObject]@{ id=2; name="Gadget B"; price="24.99"; stock="45";  category="Gadgets"; createdAt=(Get-Date -Format "o"); updatedAt=(Get-Date -Format "o") },
            [PSCustomObject]@{ id=3; name="Doohickey"; price="4.50"; stock="200"; category="Other";   createdAt=(Get-Date -Format "o"); updatedAt=(Get-Date -Format "o") }
        )
        $products | ConvertTo-Json -Depth 5 | Set-Content -Path $prodPath -Encoding UTF8
    }
}

# ─── Main Server Loop ─────────────────────────────────────────────────────────
# Load HttpUtility
Add-Type -AssemblyName System.Web

Initialize-SampleData

$prefix = "http://${BindHost}:${Port}/"
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($prefix)

try {
    $listener.Start()
} catch {
    Write-Log "ERROR" "Cannot start listener on $prefix"
    Write-Log "ERROR" "If on Windows, try running as Administrator, or change the port."
    Write-Log "ERROR" $_.Exception.Message
    exit 1
}

Write-Host ""
Write-Host "  ╔══════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║      PowerShell Web Server  v1.0         ║" -ForegroundColor Cyan
Write-Host "  ╠══════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "  ║  Listening on: $($prefix.PadRight(27))║" -ForegroundColor Green
Write-Host "  ║  Data dir    : ./data/                   ║" -ForegroundColor DarkCyan
Write-Host "  ║  Templates   : ./templates/              ║" -ForegroundColor DarkCyan
Write-Host "  ║  Press Ctrl+C to stop                    ║" -ForegroundColor DarkGray
Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Graceful shutdown on Ctrl+C
$null = [Console]::TreatControlCAsInput = $false
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    $listener.Stop()
} | Out-Null

try {
    while ($listener.IsListening) {
        try {
            $ctx = $listener.GetContext()
        } catch [System.Net.HttpListenerException] {
            if (-not $listener.IsListening) { break }
            continue
        }
        try {
            Invoke-Router -Request $ctx.Request -Response $ctx.Response
        } catch {
            Write-Log "ERROR" "Unhandled: $($_.Exception.Message)"
        }
    }
} finally {
    $listener.Stop()
    Write-Log "INFO" "Server stopped."
}

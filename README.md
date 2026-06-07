# PowerShell Web Server

A **zero-dependency**, fully offline web server written in pure PowerShell 5.1.

No NuGet packages. No npm. No external binaries. Just PowerShell and .NET built-ins.

---

## Quick Start

```powershell
# Default: http://localhost:8080
.\Start-WebServer.ps1

# Custom port
.\Start-WebServer.ps1 -Port 9000

# Listen on all interfaces (requires admin on Windows)
.\Start-WebServer.ps1 -Port 8080 -BindHost "+"
```

Then open your browser: **http://localhost:8080**

---

## Project Structure

```
pswebserver/
├── Start-WebServer.ps1      ← Main server script
├── data/                    ← JSON table files (auto-created)
│   ├── users.json
│   ├── products.json
│   └── attachments.json     ← Attachment metadata
├── attachments/             ← Uploaded attachment files
├── templates/               ← HTML templates
│   ├── partials/
│   │   ├── header.html      ← Shared nav/head
│   │   └── footer.html      ← Shared footer
│   ├── index.html           ← Dashboard
│   ├── tables.html          ← Table list
│   ├── table_view.html      ← View rows
│   ├── record_form.html     ← Create / Edit form
│   ├── create_table.html    ← New table form
│   └── error.html           ← Error page
└── static/                  ← Static assets (css, js, images)
```

---

## Template Engine

Templates use a Handlebars-inspired syntax:

| Syntax | Description |
|---|---|
| `{{variable}}` | Escaped variable output |
| `{{{variable}}}` | Raw (unescaped) HTML output |
| `{{#each items}}...{{/each}}` | Loop over array |
| `{{#if key}}...{{else}}...{{/if}}` | Conditional block |
| `{{> partial_name}}` | Include a partial from `templates/partials/` |
| `{{@index}}` | Current loop index (inside `each`) |
| `{{@first}}` / `{{@last}}` | First/last item flags (inside `each`) |

---

## REST API

The server exposes a full CRUD JSON API at `/api/{table}`:

```
GET    /api                      → List all tables
GET    /api/{table}              → List all rows
GET    /api/{table}?field=value  → Filter rows
GET    /api/{table}/{id}         → Get one row
POST   /api/{table}              → Create row  (JSON body)
PUT    /api/{table}/{id}         → Replace row (JSON body)
PATCH  /api/{table}/{id}         → Update fields (JSON body)
DELETE /api/{table}/{id}         → Delete row
```

### Examples (PowerShell)

```powershell
$base = "http://localhost:8080"

# List all
Invoke-RestMethod "$base/api/users"

# Create
Invoke-RestMethod "$base/api/users" -Method POST `
  -ContentType "application/json" `
  -Body '{"name":"Dave","email":"dave@example.com","role":"User"}'

# Update
Invoke-RestMethod "$base/api/users/1" -Method PATCH `
  -ContentType "application/json" `
  -Body '{"role":"Admin"}'

# Delete
Invoke-RestMethod "$base/api/users/3" -Method DELETE
```

### Examples (curl)

```bash
# List
curl http://localhost:8080/api/users

# Create
curl -X POST http://localhost:8080/api/users \
  -H "Content-Type: application/json" \
  -d '{"name":"Eve","email":"eve@example.com"}'

# Filter
curl "http://localhost:8080/api/users?role=Admin"
```

---

## Data Storage

Each table is a plain JSON file in the `data/` folder:

```json
[
  {
    "id": 1,
    "name": "Alice Smith",
    "email": "alice@example.com",
    "role": "Admin",
    "createdAt": "2024-01-15T10:30:00",
    "updatedAt": "2024-01-15T10:30:00"
  }
]
```

- `id`, `createdAt`, `updatedAt` are managed automatically.
- You can edit JSON files directly while the server is running.
- No schema — add any fields you like.

---

## Static Files

Place any files in the `static/` folder and access them at `/static/filename`.

```
static/logo.png  →  http://localhost:8080/static/logo.png
static/app.css   →  http://localhost:8080/static/app.css
```

---

## Attachment Handling

The server includes a secure attachment system with file encryption and download capabilities.

### Web UI File Upload

**Upload files directly from any table view:**

1. Navigate to a table (e.g., `/tables/carthoteca`)
2. Click the **📎 Attach** button next to any record
3. Select a file and click **⬆️ Upload**
4. File is automatically linked to the record via the `parent` field

**Features:**
- ✅ Inline upload forms for each row
- ✅ Attachment count badges (📎 2)
- ✅ Automatic filename deduplication
- ✅ Content-type detection
- ✅ Links files to parent records automatically

### File Structure

- **Metadata**: Stored in `data/attachments.json` with encrypted file names
- **Files**: Stored in `attachments/` folder
- **Encryption**: File names are encrypted using Windows DPAPI (Data Protection API)

### Attachment Routes

```
GET /attachments/{id}            → View/download attachment by ID
GET /attachments/{id}?download=1 → Force download (vs. inline display)
```

### API Endpoints

```
GET    /api/attachments          → List all attachments
GET    /api/attachments/{id}     → Get attachment metadata
POST   /api/attachments          → Create attachment record
PUT    /api/attachments/{id}     → Update attachment metadata
DELETE /api/attachments/{id}     → Delete attachment record (file remains)
```

### Usage Examples

**View in Browser** (inline for images, PDFs, text):
```powershell
Start-Process "http://localhost:8080/attachments/1"
```

**Force Download**:
```powershell
Invoke-WebRequest -Uri "http://localhost:8080/attachments/1?download=1" `
  -OutFile "myfile.pdf"
```

**List Attachments**:
```powershell
Invoke-RestMethod "http://localhost:8080/api/attachments"
```

**Get Attachment Metadata**:
```powershell
Invoke-RestMethod "http://localhost:8080/api/attachments/1"
```

### Attachment JSON Structure

```json
{
  "id": 1,
  "parent": 22,
  "file_name": "document.pdf",
  "content_type": "application/pdf",
  "content": "",
  "creator": "1",
  "createdAt": "2026-06-07T21:10:23Z",
  "updatedAt": "2026-06-07T21:10:23Z"
}
```

### Supported Content Types

The server automatically detects content types from file extensions:

- **Images**: `.png`, `.jpg`, `.jpeg`, `.gif`, `.svg`, `.webp`, `.bmp`
- **Documents**: `.pdf`, `.doc`, `.docx`, `.xls`, `.xlsx`, `.ppt`, `.pptx`
- **Archives**: `.zip`, `.rar`, `.7z`
- **Media**: `.mp3`, `.mp4`, `.avi`
- **Text**: `.txt`, `.html`, `.css`, `.js`, `.json`

### Testing

Use the included test script:

```powershell
.\Test-Attachments.ps1
```

This will:
- Test existing attachments from `attachments.json`
- Create a sample test file
- Display usage examples

---

## Requirements

- **PowerShell 5.1+** (built into Windows 10/11)
- **Windows**: May need to run as Administrator for non-localhost binding
- **No internet connection required** — fully self-contained

---

## Data Security & Encryption

### Protected Fields

The server uses **Windows Data Protection API (DPAPI)** to encrypt sensitive fields at rest.

Protected fields are configured per table in `$ProtectedFields`:

```powershell
$ProtectedFields = @{
    "users"       = @("name", "email", "role", "key")
    "carthoteca"  = @("passport_data", "real_name", "residence_address")
    "attachments" = @("file_name")
}
```

- **Automatic Encryption**: When writing to JSON files, protected fields are encrypted
- **Automatic Decryption**: When reading from JSON files, protected fields are decrypted
- **User-Scoped**: Encrypted data can only be decrypted by the same Windows user account
- **Transparent**: API consumers always see decrypted values

### How It Works

1. **On Write**: `Write-Table` encrypts protected fields before saving to JSON
2. **On Read**: `Read-Table` decrypts protected fields after loading from JSON
3. **API Access**: All API endpoints work with decrypted values transparently

### Security Considerations

- DPAPI encryption is **user-scoped** — data can only be decrypted by the same Windows user
- If you move JSON files to another user/computer, protected fields cannot be decrypted
- For production use, consider additional authentication/authorization layers

---

## Windows Firewall Note

To allow LAN access (binding to `0.0.0.0` or `+`):

```powershell
# Run as Administrator
New-NetFirewallRule -DisplayName "PS WebServer" -Direction Inbound `
  -Protocol TCP -LocalPort 8080 -Action Allow
```

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
│   └── products.json
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

## Requirements

- **PowerShell 5.1+** (built into Windows 10/11)
- **Windows**: May need to run as Administrator for non-localhost binding
- **No internet connection required** — fully self-contained

---

## Windows Firewall Note

To allow LAN access (binding to `0.0.0.0` or `+`):

```powershell
# Run as Administrator
New-NetFirewallRule -DisplayName "PS WebServer" -Direction Inbound `
  -Protocol TCP -LocalPort 8080 -Action Allow
```

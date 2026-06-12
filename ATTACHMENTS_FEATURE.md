# Attachment Handling Feature - Implementation Summary

## Overview

A complete attachment management system has been implemented for the PowerShell Web Server with the following capabilities:

✅ **View attachments** - Click to view files inline (images, PDFs, text)  
✅ **Download attachments** - Force download with query parameter  
✅ **Encrypted file names** - Uses Windows DPAPI for secure storage  
✅ **Content-type detection** - Automatic MIME type handling  
✅ **REST API integration** - Full CRUD operations via `/api/attachments`  
✅ **Web UI** - Browse and manage attachments at `/attachments`  
✅ **Table-aware filtering** - Properly filters attachments by table name (content field)

---

## Recent Bug Fix (2026-06-12)

### Issue: Attachments Not Filtered by Table Name
**Problem**: The `content` field (which stores the table name) was not being used for filtering. This meant:
- Attachments were only filtered by record ID (`parent` field)
- Records with the same ID in different tables would show each other's attachments
- Example: Record #1 in "carthoteca" and record #1 in "users" would show all attachments where parent=1

**Solution**: 
1. Updated `/attachments` route to filter by both `table` and `parent` query parameters
2. Modified attachment count logic in table views to check both `content` (table) and `parent` fields
3. Updated all attachment links to include `?table={tableName}&parent={recordId}`

**Testing**: Run `.\Test-AttachmentsFilter.ps1` to verify proper filtering

---

## Files Modified

### 1. **Start-WebServer.ps1** - Main server script
   - ✅ Added `$AttachmentsDir` path variable
   - ✅ Expanded MIME types for documents, archives, and media
   - ✅ Added `/attachments/{id}` route for serving files
   - ✅ Added `/attachments` page route for web UI
   - ✅ Supports inline viewing and forced downloads

### 2. **templates/partials/header.html** - Navigation
   - ✅ Added "Attachments" link to navigation menu

---

## Files Created

### 1. **templates/attachments_view.html**
   - Beautiful card-based UI for browsing attachments
   - Shows file type icons, metadata, and action buttons
   - View, download, and edit links for each attachment

### 2. **Test-Attachments.ps1**
   - Test script to verify attachment functionality
   - Tests existing attachments from the database
   - Creates sample test files
   - Displays usage examples

### 3. **Add-Attachment.ps1**
   - Helper script to add new attachments
   - Copies files to attachments folder
   - Creates database records via API
   - Handles duplicate filenames
   - Auto-detects content types

### 4. **README.md** - Updated documentation
   - Added attachment handling section
   - Documented routes and API endpoints
   - Included usage examples
   - Added security/encryption section

---

## How It Works

### Route: `/attachments/{id}`

1. Reads `data/attachments.json` to get attachment metadata
2. Decrypts the `file_name` field (encrypted with DPAPI)
3. Locates the file in the `attachments/` folder
4. Sets appropriate Content-Type from metadata or file extension
5. Sets Content-Disposition header:
   - `inline` for viewable types (images, PDFs, text)
   - `attachment` for downloadable types or when `?download=1` is present
6. Serves the file

### Data Flow

```
Browser Request
    ↓
/attachments/{id}
    ↓
Read attachments.json → Decrypt file_name
    ↓
Locate file in attachments/ folder
    ↓
Set headers (Content-Type, Content-Disposition)
    ↓
Stream file to browser
```

---

## Usage Examples

### View Attachment in Browser
```powershell
# Open attachment ID 1 inline
Start-Process "http://localhost:8080/attachments/1"
```

### Download Attachment
```powershell
# Force download attachment ID 1
Invoke-WebRequest -Uri "http://localhost:8080/attachments/1?download=1" `
    -OutFile "myfile.pdf"
```

### List All Attachments (API)
```powershell
Invoke-RestMethod "http://localhost:8080/api/attachments"
```

### Add New Attachment
```powershell
# Using helper script
.\Add-Attachment.ps1 -FilePath "C:\Documents\report.pdf" -Parent 22 -Creator "user1"

# Or manually via API
$body = @{
    file_name    = "document.pdf"
    content_type = "application/pdf"
    parent       = "22"
    creator      = "user1"
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost:8080/api/attachments" `
    -Method POST -ContentType "application/json" -Body $body
```

### Browse Attachments (Web UI)
```
http://localhost:8080/attachments
```

---

## Security Features

### Field Encryption
- `file_name` field is encrypted using Windows DPAPI
- Encryption is **user-scoped** - only the same Windows user can decrypt
- Automatic encryption/decryption handled by `Read-Table`/`Write-Table`
- Transparent to API consumers

### Content-Disposition Headers
- Inline display for safe content types (images, PDFs, text)
- Forced download for executable or unknown types
- User can override with `?download=1` parameter

---

## Supported File Types

### Images
`.png`, `.jpg`, `.jpeg`, `.gif`, `.svg`, `.webp`, `.bmp`, `.ico`

### Documents
`.pdf`, `.doc`, `.docx`, `.xls`, `.xlsx`, `.ppt`, `.pptx`, `.txt`

### Archives
`.zip`, `.rar`, `.7z`

### Media
`.mp3`, `.mp4`, `.avi`

### Web
`.html`, `.css`, `.js`, `.json`

---

## Testing

### Run the test script:
```powershell
.\Test-Attachments.ps1
```

This will:
1. Test all existing attachments from `attachments.json`
2. Create a sample test file
3. Display usage examples and API endpoints

### Add a sample attachment:
```powershell
# Create a test file
"Hello, this is a test attachment!" | Out-File "test.txt"

# Add it to the server
.\Add-Attachment.ps1 -FilePath "test.txt" -Parent "22"

# View it in browser
Start-Process "http://localhost:8080/attachments/3"
```

---

## API Reference

### GET /attachments/{id}
**Description**: View or download an attachment  
**Query Parameters**:
  - `download=1` - Force download instead of inline display

**Response**: Binary file content with appropriate headers

### GET /api/attachments
**Description**: List all attachments  
**Response**: JSON array of attachment objects

### GET /api/attachments/{id}
**Description**: Get attachment metadata  
**Response**: JSON object with decrypted fields

### POST /api/attachments
**Description**: Create new attachment record  
**Request Body**: JSON with `file_name`, `content_type`, `parent`, `creator`  
**Response**: Created attachment object with ID

### PUT/PATCH /api/attachments/{id}
**Description**: Update attachment metadata  
**Request Body**: JSON with fields to update  
**Response**: Updated attachment object

### DELETE /api/attachments/{id}
**Description**: Delete attachment record  
**Note**: This only deletes the database record, not the file  
**Response**: `{ "deleted": true, "id": 1 }`

---

## Notes

1. **File Management**: The `/api/attachments` endpoints only manage the JSON records. Physical file management must be done separately.

2. **Encryption**: File names are encrypted in `attachments.json` but the actual files are stored unencrypted in the `attachments/` folder.

3. **URL Structure**: Use `/attachments/{id}` for serving files, not direct paths to the `attachments/` folder.

4. **Existing Attachments**: The two existing attachments in `attachments.json` have encrypted file names. You'll need to view them through the web server to see their actual names, or use the API to read the decrypted metadata.

5. **Navigation**: The "Attachments" link has been added to the main navigation menu for easy access.

---

## Next Steps (Optional Enhancements)

- [ ] File upload form in web UI
- [ ] Thumbnail generation for images
- [ ] Bulk delete functionality
- [ ] Search/filter attachments by type or parent
- [ ] File size limits and validation
- [ ] Attachment preview modal
- [ ] Activity log for downloads

---

**Implementation Complete! 🎉**

The attachment system is fully functional and ready to use.

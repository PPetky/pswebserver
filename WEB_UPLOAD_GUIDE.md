# Web UI File Upload Feature - Quick Start Guide

## 🎯 Feature Overview

Users can now **upload files directly from the web UI** and link them to table records via the `parent` field in the attachments table.

## 📋 How to Use

### 1. Navigate to Any Table
```
http://localhost:8080/tables/carthoteca
http://localhost:8080/tables/users
http://localhost:8080/tables/products
```

### 2. Upload a File to a Record

For each row in the table, you'll see:
- 📎 Badge showing attachment count (if any)
- **📎 Attach** button

**Steps:**
1. Click the **📎 Attach** button next to any row
2. A file upload form will appear below the row
3. Click **Choose File** and select your file
4. Click **⬆️ Upload**
5. The file is automatically:
   - Saved to the `attachments/` folder
   - Linked to the record via `parent` field
   - Added to `attachments.json` with encrypted filename

### 3. View Uploaded Attachments

**Option A: From the Attachments Page**
```
http://localhost:8080/attachments
```
Shows all attachments with view/download links

**Option B: From Table View**
- Badge next to each row shows: 📎 2 (number of attachments)
- Hover to see tooltip: "2 attachment(s)"

### 4. View or Download Files

**View inline (images, PDFs, text):**
```
http://localhost:8080/attachments/{id}
```

**Force download:**
```
http://localhost:8080/attachments/{id}?download=1
```

## 🧪 Test It Now

### Step-by-Step Test:

1. **Start the server** (if not running):
   ```powershell
   .\Start-WebServer.ps1
   ```

2. **Open a table in your browser**:
   ```
   http://localhost:8080/tables/carthoteca
   ```

3. **Upload a test file**:
   - Click **📎 Attach** next to record #1
   - Select any file (image, PDF, document, etc.)
   - Click **⬆️ Upload**

4. **Verify the upload**:
   - You'll be redirected back to the table
   - The record now shows a **📎 1** badge
   - File is in the `attachments/` folder
   - Record created in `data/attachments.json`

5. **View the attachment**:
   - Go to: `http://localhost:8080/attachments`
   - Find your uploaded file
   - Click **👁️ View** to see it
   - Or click **⬇️ Download** to save it

6. **Check the link**:
   - Open `data/attachments.json`
   - Find the newest record
   - The `parent` field should match the record ID from step 3

## 📊 What Gets Created

When you upload `document.pdf` to record #22 in `carthoteca`:

**1. File saved:**
```
attachments/document.pdf
```

**2. Database record created:**
```json
{
  "id": 3,
  "parent": "22",
  "file_name": "document.pdf",  // encrypted in actual JSON
  "content_type": "application/pdf",
  "creator": "",
  "content": "",
  "createdAt": "2026-06-07T...",
  "updatedAt": "2026-06-07T..."
}
```

**3. Attachment count updated:**
- Table view shows **📎 1** badge next to record #22

## 🎨 UI Features

### In Table View (`/tables/carthoteca`):

✅ **Attachment Count Badge**
- Shows number of attachments per record
- Only visible when attachments exist
- Blue badge: **📎 2**

✅ **Inline Upload Form**
- Toggles on/off with button click
- Shows existing attachment count
- Link to view all attachments

✅ **Upload Feedback**
- Upload form appears below the row
- Cancel button to hide form
- Automatic redirect after successful upload

### In Attachments View (`/attachments`):

✅ **File Type Icons**
- 🖼️ Images
- 📄 PDFs
- 📝 Documents
- 🗜️ Archives
- 🎬 Videos
- 🎵 Audio

✅ **Metadata Display**
- Parent record ID
- Creator
- Created date
- Content type

✅ **Action Buttons**
- 👁️ View (inline)
- ⬇️ Download
- ✏️ Edit metadata

## 🔒 Security

- File names are **encrypted** in `attachments.json` using DPAPI
- Files are stored **unencrypted** in `attachments/` folder
- Duplicate filenames are automatically renamed (e.g., `file_1.pdf`)
- Only files uploaded through the UI or API are tracked

## 🛠️ Advanced Usage

### Upload Multiple Files to Same Record
Just click **📎 Attach** multiple times and upload different files

### View Attachments by Parent
Go to the attachments page and look for the **📌 Parent: 22** indicator

### Delete Attachments
- Navigate to `/tables/attachments`
- Click **🗑 Delete** next to the attachment record
- **Note:** This only deletes the database record, not the file

### Manual File Addition
Use the helper script:
```powershell
.\Add-Attachment.ps1 -FilePath "C:\path\to\file.pdf" -Parent 22
```

## 📸 Expected Behavior

### Before Upload:
```
┌────────────────────────────────────────┐
│ ID │ Name     │ Data    │ Actions     │
├────────────────────────────────────────┤
│ 22 │ John Doe │ Sample  │ ✏️ 📎 🗑     │
└────────────────────────────────────────┘
```

### After Upload (1 file):
```
┌────────────────────────────────────────┐
│ ID │ Name     │ Data    │ Actions     │
├────────────────────────────────────────┤
│ 22 │ John Doe │ Sample  │ 📎1 ✏️ 📎 🗑  │
└────────────────────────────────────────┘
```

### After Upload (3 files):
```
┌────────────────────────────────────────┐
│ ID │ Name     │ Data    │ Actions     │
├────────────────────────────────────────┤
│ 22 │ John Doe │ Sample  │ 📎3 ✏️ 📎 🗑  │
└────────────────────────────────────────┘
```

## ✅ Feature Checklist

- [x] Upload files from table view
- [x] Link files to parent records
- [x] Show attachment count badges
- [x] Toggle upload form per row
- [x] Automatic filename deduplication
- [x] Content-type detection
- [x] Encrypted filename storage
- [x] View/download from web UI
- [x] Redirect after upload
- [x] Error handling

## 🚀 Next Steps

Try uploading:
- ✅ Images (PNG, JPG) → Will display inline
- ✅ PDFs → Will open in browser
- ✅ Documents (DOCX, XLSX) → Will download
- ✅ Archives (ZIP, RAR) → Will download
- ✅ Any other file type

**Happy uploading! 📎**

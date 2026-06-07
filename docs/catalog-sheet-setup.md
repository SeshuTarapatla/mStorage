# Catalog Sheet Setup Guide

This guide explains how to create and maintain the Google Sheet that powers the mStorage Catalog tab.

---

## 1. Create the Sheet

1. Go to [sheets.google.com](https://sheets.google.com) and create a new blank spreadsheet.
2. Name it something like **mStorage Catalog**.

---

## 2. Set Up Columns

**Row 1 must be the header row exactly as shown below** (case-sensitive). Data starts from row 2.

| Column | Header | Description |
|--------|--------|-------------|
| A | `title` | Display name of the video shown on the card |
| B | `date` | Date in `YYYY-MM-DD` format (e.g. `2023-08-14`) |
| C | `tags` | Comma-separated tags, no spaces (e.g. `family,vacation,india`) |
| D | `description` | Short description shown in the detail panel |
| E | `thumbnail_url` | Direct image URL for the card thumbnail (see Section 4) |
| F | `photos_url` | Google Photos share link for the video (see Section 5) |
| G | `size_mb` | File size as a plain number, no unit (e.g. `42`) |
| H | `encoded` | `true` if this is a steganography-encoded video, `false` otherwise |

**Example row:**
```
Family Trip Coorg 2023 | 2023-08-14 | family,vacation,india | Hiking day at Abbey Falls | https://drive.google.com/thumbnail?id=1abc...&sz=w400 | https://photos.app.goo.gl/XXXXX | 42 | true
```

---

## 3. Share the Sheet

1. Click **Share** (top right).
2. Under "General access", change from **Restricted** to **Anyone with the link**.
3. Set permission to **Viewer**.
4. Click **Copy link** — this is the URL you paste into the mStorage app.

> The app will show an error if the sheet is set to Restricted.

---

## 4. Getting the Thumbnail URL (Google Drive)

Thumbnails are served from Google Drive — they load as plain images without any login.

1. Upload the video to **Google Drive** (same Google account).
2. Right-click the file → **Share** → set to **Anyone with the link → Viewer**.
3. Copy the share link. It looks like:
   ```
   https://drive.google.com/file/d/1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms/view
   ```
4. Copy the file ID — the long string between `/d/` and `/view`:
   ```
   1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms
   ```
5. Build the thumbnail URL:
   ```
   https://drive.google.com/thumbnail?id=FILE_ID&sz=w400
   ```

---

## 5. Getting the Google Photos URL

1. Open the video in **Google Photos**.
2. Click the share icon → **Create link**.
3. Copy the generated link. It looks like:
   ```
   https://photos.app.goo.gl/XXXXX
   ```
4. Paste this directly into column F.

> This link opens in the app's built-in browser where you can download the video.

---

## 6. Entering the Sheet URL in mStorage

1. Open the **Catalog** tab in mStorage.
2. Paste the Google Sheets share URL from Step 3 into the prompt.
3. The app saves it — you only need to do this once.
4. To change it later, go to **Settings → Catalog Sheet URL**.

---

## Tips

- Keep the header row exactly as specified — the app maps columns by header name.
- Dates must be `YYYY-MM-DD` or sorting won't work correctly.
- Tags must have no spaces around commas: `family,vacation` not `family, vacation`.
- Leave `size_mb` empty if unknown — the app handles blank cells gracefully.
- Add new videos by simply appending rows — the app re-fetches on each refresh.

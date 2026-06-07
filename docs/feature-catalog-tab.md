# Feature: Catalog Tab — Google Sheets-Powered Video Browser

## Vision

Add a **Catalog** tab to mStorage that lets anyone browse, search, and download steganography-encoded videos — all driven by a Google Sheet that only the owner can edit. No backend, no auth setup, no API keys required for viewers.

---

## User Flow

1. User opens the Catalog tab.
2. If no sheet URL is saved, the app shows an input prompt: **"Enter catalog sheet URL"**.
3. The app fetches the sheet (public CSV export endpoint — no API key needed), parses rows, and displays a card grid.
4. Each card shows: thumbnail, title, date, tags, short description.
5. User can search (by title/tags) and filter (by date, tag).
6. Clicking a card opens a detail panel with a **"View & Download"** button.
7. That button opens an in-app WebView overlay pointing to the Google Photos share link.
8. The user clicks download inside the Photos page; the app intercepts the download request, saves the file, and prompts **"Open in Decode?"**.

The entered sheet URL is persisted locally (SharedPreferences / app settings) so the user only types it once. An "Edit Sheet URL" option lives in Settings.

---

## Google Sheet Format

The owner maintains this sheet. Suggested columns:

| Column | Field          | Example                                                      | Notes                                        |
|--------|----------------|--------------------------------------------------------------|----------------------------------------------|
| A      | `title`        | Family Trip 2023                                             | Shown on card                                |
| B      | `date`         | 2023-08-14                                                   | ISO 8601, used for sort/filter               |
| C      | `tags`         | family,vacation,india                                        | Comma-separated                              |
| D      | `description`  | Hiking day at Coorg                                          | Short text shown in detail panel             |
| E      | `thumbnail_url`| `https://drive.google.com/thumbnail?id=FILE_ID&sz=w400`      | Google Drive thumbnail (no auth needed)      |
| F      | `photos_url`   | `https://photos.app.goo.gl/XXXXX`                            | Google Photos share link — opens in WebView  |
| G      | `size_mb`      | 42                                                           | Optional, shown in detail panel              |
| H      | `encoded`      | true                                                         | Flag: is this a steganography video?         |

**Thumbnail vs download split:** Thumbnails come from Google Drive (stable, direct image URL). Downloads happen through Google Photos in-app WebView. Both can point to the same file since the same video lives in both services via Google's ecosystem sync.

---

## Link Strategy

### Thumbnails — Google Drive
Upload the video to Drive (same account), share as "Anyone with link can view", get the file ID:
```
https://drive.google.com/thumbnail?id={FILE_ID}&sz=w400
```
No API key, no auth. Works as a plain `<img>` src or `NetworkImage`.

### Downloads — Google Photos WebView
Google Photos share links (`photos.app.goo.gl/...`) work in unauthenticated browsers — confirmed working in incognito. Instead of direct HTTP download (which doesn't work), the app opens an **in-app WebView** pointing to the Photos link. When the user taps the download button on the Photos page, the WebView fires a download request which the app intercepts.

**Package: `flutter_inappwebview`** — supports Windows via WebView2 (same Chromium engine as Edge). The `onDownloadStartRequest` callback fires when a download is triggered, giving us the URL, filename, and MIME type. The app then downloads the file via the `http` package and saves it to the user's Downloads folder (or a temp path).

---

## In-App Browser Flow (Detail)

```
[Catalog Card] → [Detail Panel]
                      ↓ "View & Download"
               [WebView overlay/dialog]
                  Shows Google Photos page
                      ↓ user clicks download
               [onDownloadStartRequest fires]
                      ↓
               [App downloads via http]
                      ↓
               [Toast: "Saved. Open in Decode?"]
                      ↓ yes
               [Decode tab pre-loaded with file]
```

The WebView overlay should be a modal covering ~90% of the screen with a close button and a URL bar showing the current page — enough to feel like a lightweight browser without full browser chrome.

---

## Fetching the Sheet (No API Key Needed)

```
https://docs.google.com/spreadsheets/d/{SHEET_ID}/export?format=csv&gid=0
```

Works for any sheet set to **"Anyone with the link can view"**. No OAuth, no API key. The app parses the CSV directly.

---

## Implementation Plan

### Phase 1 — Core catalog (MVP)
- [ ] `CatalogEntry` model + CSV parser
- [ ] Parse Google Sheets URL to extract sheet ID
- [ ] Fetch + parse sheet on tab open; cache for session
- [ ] Catalog screen: card grid with thumbnail (cached), title, date, tags
- [ ] Detail panel: description, size, photos link
- [ ] In-app WebView overlay with `onDownloadStartRequest` interception
- [ ] Download file via `http`, save to temp, route to Decode tab
- [ ] Persist sheet URL in app settings

### Phase 2 — Search & Filter
- [ ] Text search across title, description, tags
- [ ] Filter by tag (chip selector)
- [ ] Sort by date (newest/oldest)
- [ ] "Encoded only" toggle filter

### Phase 3 — Polish
- [ ] Pull-to-refresh for catalog
- [ ] Download progress indicator (within the WebView overlay)
- [ ] "Copy Photos link" option per card
- [ ] Empty state, error state, and loading skeleton UIs
- [ ] Large file warning (>200 MB) before opening WebView

---

## Packages Needed

| Package                  | Purpose                                        |
|--------------------------|------------------------------------------------|
| `http`                   | Fetch sheet CSV and download intercepted files |
| `csv`                    | Parse CSV rows                                 |
| `cached_network_image`   | Thumbnail caching                              |
| `path_provider`          | Temp/downloads dir                             |
| `flutter_inappwebview`   | In-app browser + download interception         |

---

## Open Questions

1. **WebView2 availability** — WebView2 runtime ships with Windows 11 and modern Win10, but very old machines may need a one-time install. Worth a runtime check with a helpful error message.
2. **Sheet refresh** — re-fetch on explicit pull-to-refresh. No polling needed.
3. **Auto-route to Decode** — show a toast with an "Open in Decode" action button after download completes rather than auto-switching tabs (less jarring).
4. **Multiple catalogs** — future: support a saved list of sheet URLs. Out of scope for v1.1.

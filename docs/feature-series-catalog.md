# v1.3.0 — Series Catalog Feature Plan

## Overview

Extend the Catalog tab to support TV series alongside movies. Series have a hierarchy
(series → seasons → episodes), which is fundamentally different from movies (1 entry = 1 video).
The approach: keep the existing Movies grid untouched and add a **Series sub-tab** within the
Catalog screen, backed by a second sheet tab named **Series** in the same Google Spreadsheet.

---

## 1. Google Sheet Changes

The user renames their existing Sheet1 to **Movies** and adds a new sheet tab named **Series**.

### Series sheet: one row per episode

Each row represents one episode. Series-level metadata (poster, IMDB ID, genres, tags, plot)
is entered on the first row for each series and may be left blank on subsequent rows — the
parser groups rows by `series_title` and inherits series-level fields from the first
non-empty occurrence per series.

#### Columns

| Column | Required | Description |
|---|---|---|
| `series_title` | yes | Show name — the grouping key |
| `series_imdb_id` | no | IMDB ID of the **series** (e.g. `tt0903747`) |
| `season` | yes | Season number (integer) |
| `episode` | yes | Episode number within the season (integer) |
| `episode_title` | no | Episode title (blank → use "Episode N") |
| `air_date` | no | ISO date or year |
| `video_url` | yes | Google Photos album / direct link for this episode |
| `poster_url` | no | Series poster — only needed on one row per series |
| `size_mb` | no | File size in MB |
| `language` | no | Language label |
| `encoded` | no | `true` if video is encoded/hidden (default `false`) |
| `show` | no | `false` to hide from catalog |
| `tags` | no | Franchise tags, comma-separated |
| `genres` | no | Genre tags, comma-separated |
| `plot` | no | Series synopsis (blank → IMDB) |

Flexible alias-matching applies (same strategy as movies): e.g. `series_title`, `show_title`,
`title` all resolve to the series title column.

### Single URL, two named sheet tabs

No new URL setting. The app derives both CSV endpoints from the **existing** sheet URL:

| Tab | Fetch URL |
|---|---|
| Movies | `…/export?format=csv&gid=0` (unchanged) |
| Series | `…/gviz/tq?tqx=out:csv&sheet=Series` (by name) |

The Google Visualization endpoint (`gviz/tq`) resolves tabs by name, works publicly without
auth, and returns the same CSV format. If the **Series** tab doesn't exist yet, the request
returns an error which the app treats as "no series data" (empty state, not an error banner).

No changes to `sheetUrlProvider` or how the user configures the URL.

---

## 2. Data Model

### New file: `lib/features/catalog/models/series_entry.dart`

```
SeriesEntry
  String title
  String imdbId             // series-level IMDB ID
  String posterUrl
  String plot
  List<String> genres
  List<String> tags
  String? language
  double? imdbRating        // series-level rating from IMDB
  List<SeasonEntry> seasons

SeasonEntry
  int number
  List<EpisodeEntry> episodes

EpisodeEntry
  int episodeNumber
  String title              // from sheet, or "Episode N" fallback
  DateTime? airDate
  String videoUrl
  int? sizeMb
  bool encoded
```

### New file: `lib/features/catalog/models/series_sheet_schema.dart`

Same pattern as `SheetSchema` — column names, indices, `headerTsv`, `parseTsv` / `buildTsv`.
Useful when the Admin tool adds series support in a future release.

### IMDB enrichment

`ImdbService.resolve()` already handles series IMDB IDs (same API fields: title, poster, plot,
genres, rating). No changes to `ImdbService` needed. Episode-level enrichment is deferred.

---

## 3. State Management

### New file: `lib/features/catalog/series_notifier.dart`

```
seriesProvider  — StateNotifierProvider<SeriesNotifier, SeriesCatalogState>
```

No new URL provider — `SeriesNotifier` reads `sheetUrlProvider` directly and constructs the
`gviz/tq` URL from the same sheet ID.

`SeriesCatalogState` sealed class:
- `SeriesCatalogIdle`
- `SeriesCatalogLoading`
- `SeriesCatalogLoaded(List<SeriesEntry> series)`
- `SeriesCatalogError(String message)`

`SeriesNotifier.load(sheetUrl)` pipeline:
1. Extract sheet ID from URL (same `_extractSheetId` regex as movies)
2. Build `gviz/tq` URL: `https://docs.google.com/spreadsheets/d/$id/gviz/tq?tqx=out:csv&sheet=Series`
3. Check disk cache (TTL: 1 hour) → `catalog_csv_series_$id.json`
4. Fetch CSV if stale or missing; treat HTTP error / HTML response as empty (Series tab not yet created)
5. Parse flat rows → group by `series_title` → build `SeriesEntry` tree
6. Enrich via `ImdbService.resolve()` on series-level IMDB IDs
7. Emit `SeriesCatalogLoaded`

Cache key uses `series_` prefix to avoid collision with the movies cache.

---

## 4. UI Architecture

### 4a. Inner tab bar in CatalogScreen

`CatalogScreen` gains a `TabController` with two tabs: **Movies** and **Series**.

The tab switcher is a compact pill toggle placed between the `_TopBar` and the content area
(where the sort/filter bar currently lives). The top bar (URL input / search) is **shared** —
the same URL and search state applies regardless of which sub-tab is active.

When the catalog sub-tab switches:
- The active palette changes (amber for Movies, orange for Series)
- The sort/filter bar only appears under Movies (Series has its own simpler controls)
- The content area swaps between `_MoviesSubtab` and `_SeriesSubtab`

Tab bar visual design:
- Two pill buttons: `Movies` and `Series`
- Active pill uses the sub-tab's accent color with 10% fill and full border
- Inactive pill is muted text, no fill

### 4b. Movies sub-tab (`_MoviesSubtab`)

Zero changes to existing logic. `_Body`, `_Grid`, `_SortFilterBar`, `_CardDetail`,
`_DownloadsListView`, `_DownloadPanel` are wrapped as-is inside the Movies tab view.

### 4c. Series sub-tab (`_SeriesSubtab`)

Mirrors `_Body` structure for its four states (idle / loading / loaded / error).

**Idle state**: same prompt style as movies — "Paste a Google Sheets URL above…" — but noting
that a **Series** tab must exist in the spreadsheet.

**Loaded state** — `_SeriesGrid`:
Masonry grid of `SeriesCard` widgets (one card per show, not per episode).

**`SeriesCard`** (compact):
- Poster thumbnail
- Title
- Sub-line: `3 seasons · 24 episodes`
- Downloaded dot indicator if any episode from this series is in download history
- Orange accent on hover/selected state

**`SeriesCardExpanded`** (full overlay, same mechanism as movies):
- Large poster left, metadata right
- Title, IMDB rating, genres, language
- Plot paragraph
- Season accordion below: each season is a collapsible section header
  - Episode rows inside: `E01 · Episode Title · air_date · [▶ Open] [↓ Download]`
  - "Open" → launches `WebViewOverlay` with the episode's video URL
  - "Download" → `downloadProvider.notifier.enqueue(...)` — same as movies
- Keyboard: Left/Right navigates between series in the grid; Escape closes

### 4d. Series sort + filter bar

Simpler than movies:
- Sort: **A–Z** | **Seasons** | **Episodes**
- Filter: **Language** | **Genre**
- No Rating sort (series-level IMDB rating is available, could add in future)

---

## 5. Theme

New constant in `lib/core/theme/tab_colors.dart` (not a new `AppTab`):

```dart
const kSeriesPalette = TabPalette(
  primary:   Color(0xFFEA580C),  // orange-600
  secondary: Color(0xFFF97316),  // orange-500
  glow:      Color(0x66EA580C),
  surface:   Color(0xFF1A0A02),
);
```

`CatalogScreen` passes either `AppTab.catalog.palette` or `kSeriesPalette` to child widgets
based on the active sub-tab index.

---

## 6. Files to Create / Modify

### New files
| File | Purpose |
|---|---|
| `lib/features/catalog/models/series_entry.dart` | SeriesEntry / SeasonEntry / EpisodeEntry |
| `lib/features/catalog/models/series_sheet_schema.dart` | Series column schema |
| `lib/features/catalog/series_notifier.dart` | SeriesNotifier + SeriesCatalogState |
| `lib/features/catalog/widgets/series_card.dart` | SeriesCard + SeriesCardExpanded |

### Modified files
| File | Change |
|---|---|
| `lib/core/theme/tab_colors.dart` | Add `kSeriesPalette` constant |
| `lib/features/catalog/catalog_screen.dart` | Add TabController, pill tab bar, `_SeriesSubtab` integration, palette switching |

### Untouched
| File | Why |
|---|---|
| `lib/features/catalog/catalog_notifier.dart` | Movies unchanged |
| `lib/features/catalog/models/catalog_entry.dart` | Movies model unchanged |
| `lib/features/catalog/models/sheet_schema.dart` | Movies schema unchanged |
| `lib/features/admin/admin_screen.dart` | Admin movies-only for now |
| `lib/features/shell/app_shell.dart` | No new sidebar tab |
| `lib/core/services/settings_service.dart` | No new settings key |

---

## 7. Deferred / Out of Scope

- Episode-level IMDB enrichment (titles, air dates per episode from IMDB)
- Admin tool for series
- Series in the download history view (download records already work by title; no structural change needed)

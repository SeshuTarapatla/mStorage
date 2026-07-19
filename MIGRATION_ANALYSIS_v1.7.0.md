# v1.7.0 — IMDB API Migration Analysis

**Status: APPROVED — implementation in progress on `feat/v1.7.0`.**

`api.imdbapi.dev` (the current metadata source) appears to be dead. Candidate
replacement: `https://api.balloonerismm.workers.dev` (unofficial Cloudflare
Worker proxy in front of IMDb's internal GraphQL API — same category of
service as the one that just died: **not** an official/licensed API, no
auth, no published SLA or rate limit, could disappear the same way). That
risk doesn't block the migration (we have no better option right now) but
it's worth going in with eyes open, and probably worth designing the
service layer so a *third* swap someday is cheap (see §6).

Everything below is grounded in the actual code (`lib/features/catalog/imdb_service.dart`,
`lib/features/catalog/models/imdb_data.dart`, the three sheet-schema files, and
`admin_screen.dart`) and in live test calls to the new API (`tt1375666` /
Inception, `tt0944947` / Game of Thrones, `tt0944947` S1E1) — not just the
OpenAPI spec.

---

## 1. Where this touches the app

One file makes all HTTP calls: `ImdbService` (`lib/features/catalog/imdb_service.dart`).
Everything else — `catalog_notifier.dart`, `series_notifier.dart`,
`request_notifier.dart`, `admin_screen.dart`, `catalog_card.dart`,
`settings_screen.dart` — goes through it. That's good: the migration is
contained to `imdb_service.dart` + `models/imdb_data.dart`, nothing else
needs to change *structurally*. But the internal shape of `ImdbService`
needs a real rewrite, not a find-and-replace of the base URL — see §3.

## 2. What doesn't change

- **IDs are compatible.** Both APIs use IMDb's native `tt########` scheme
  (and the new API's own validation pattern is literally `^tt\d+$`). Every
  ID already stored in the Sheets (`imdb_id`, `series_imdb_id`,
  `episode_imdb_id`) stays valid. No ID-mapping/backfill needed.
- **No auth.** New API has no security scheme — same as today, no key to
  provision or store.
- **Existing sheet columns don't need to change.** Per your direction we're
  now *adding* columns (append-only, backward-compatible) rather than just
  swapping the data source behind the same ones — see §5.
- **Poster/image URLs are still full HTTPS URLs** (`m.media-amazon.com`),
  not relative paths needing a base-URL prefix — confirmed against a live
  response, not just the schema description.

## 3. What breaks / needs real rework in `ImdbService`

### 3a. No batch endpoint — this is the biggest structural change
Today, `resolve(ids)` fetches up to 5 IDs per request, 4 requests
concurrently (`titles:batchGet?titleIds=...`). The new API has **no
multi-ID endpoint at all** — every title is `GET /movie/{id}` or
`GET /tv/{id}` individually. A catalog load that today issues, say, 8 batch
requests for 40 titles would issue **40 individual requests**. `resolve()`
needs to be rewritten around per-ID fetches with its own concurrency cap
(and probably a smaller one, to be polite to an unauthenticated free
Worker) — this is the part of the migration I'd want to load-test against
the real catalog size before calling it done, since neither API publishes
a rate limit.

### 3b. The API is no longer type-agnostic — movie vs TV must be known up front
The old `:batchGet` endpoint took a flat list of IDs and figured out
movie/series/episode from the response shape (`ImdbData.fromApi` still has
this logic — parentId/seasonNumber/endYear sniffing). The new API requires
you to already know the type:
- Movies-tab IDs → `/movie/{id}`
- Series-tab IDs → `/tv/{id}`
- Episode-tab rows → `/tv/{series_imdb_id}/season/{season}/episode/{episode}`
  (**not** a lookup by the episode's own `tt` id — more below)

The good news: **for every existing bulk-load path this is a non-issue**,
because the sheet tab you're reading from already tells you the type
(Movies sheet = movie, Series sheet = series, Episodes sheet = episode row
with `series_imdb_id`/`season`/`episode` columns already present). No sheet
schema change needed for this.

The one place it *is* a real gap: **`request_notifier.dart`**'s "paste an
IMDb URL to request a title" flow. Today it doesn't know or care what type
the pasted ID is — one `:batchGet` call and `_inferType()` sniffs the
answer from whatever comes back. With the new API we try `/movie/{id}`,
fall back to `/tv/{id}` on 404 (2 requests instead of 1, worst case), and
if a user pastes a link to a **specific episode**
(`imdb.com/title/tt1480055` — an episode's own page), **neither endpoint
will resolve it** — the new API only reaches episode data via
`/tv/{series}/season/{n}/episode/{n}`, which requires already knowing the
parent series + season + episode number, none of which is recoverable from
a bare episode `tt` id.

**Decided:** rather than silently falling back to "raw ID as title, type
guessed as Movie" (today's behavior for *any* unresolvable ID — which
would be actively misleading here, since it'd tag a real episode link as
a Movie submission with no warning), a double-404 gets a specific message:
*"Couldn't find this on IMDb as a movie or TV series — if this links to a
specific episode, please submit the show's main IMDb page instead."* This
also covers genuinely invalid/mistyped links with the same honest framing.
Side benefit: `_inferType()`'s heuristic sniffing (`endYear`/`runtimeSeconds`/
`parentId` guessing) goes away entirely — type is now known for certain
from *which* endpoint returned 200, not inferred from response shape.

### 3c. Admin screen's episode-fetch path actually gets *more correct*
`admin_screen.dart`'s episode mode already collects series ID, season
number, and episode number as separate form fields (`_seriesImdbCtrl`,
`_seasonCtrl`, `_episodeCtrl`) — it just doesn't use season/episode in the
fetch today because the old API didn't need them. Switching
`_fetchEpisode` to call `/tv/{seriesId}/season/{s}/episode/{e}` is a
straightforward swap, and is arguably more correct than today's "guess
from a flat ID lookup" approach. Bonus: the new episode response includes
the episode's own `id` (confirmed live: `tt1480055` for GoT S1E1), so the
`episode_imdb_id` sheet field could be auto-filled from the response
instead of hand-typed — optional, not required.

### 3d. "Stars" (top cast) requires a second call per title — resolved by §5's sheet-first redesign
The old batch response embedded `stars[].displayName` directly. The new
`MovieDetail`/`TVDetail` responses **do not include cast** — it's a
separate `GET /movie/{id}/credits` (confirmed live: 87 cast + 163 crew for
Inception) or `/tv/{id}/credits` call. `stars` is shown on every catalog
card, not just in admin (`catalog_card.dart:399-402`), so if every catalog
load still resolved every title live, this would mean doubling request
volume for that field alone.

**Superseded by §5.** Per your direction, we're persisting `rating`,
`runtime`, `certificate`, and `stars` straight into the Sheet at
admin-entry time instead of re-fetching them on every catalog load. Under
that model, the `/credits` call happens **once**, when the admin adds the
title — not once per catalog load per device. See §5 for the full design;
this subsection is kept for the historical reasoning.

### 3e. Runtime units are inconsistent *within* the new API itself
Confirmed against live data — this is the one silent-corruption risk if
missed:
- `MovieDetail.runtime` is in **minutes** (Inception → `148`, correct as
  minutes; would be nonsense as seconds).
- `TVEpisode.runtime` (from the season/episode endpoint) is in **seconds**
  (GoT S1E1 → `3720` = 62 minutes, correct as seconds; nonsense as
  minutes).
- `TVDetail.episode_run_time` (array, typical episode length) is almost
  certainly minutes like the movie field, not confirmed live.

The app's internal field is named `runtimeSeconds` everywhere
(`ImdbData`, `CatalogEntry`, `EpisodeEntry`) and is currently populated
directly from a seconds value. Migration code must convert movie/series
runtime *×60* but leave episode runtime as-is — easy to get backwards,
worth an explicit unit test per entity type rather than trusting review
alone.

### 3f. Field renames / reshapes (mechanical, but exhaustive — see §4)
`plot`→`overview`, `primaryTitle`→`title` (movies) / `name` (TV),
`primaryImage.url`→`poster_path`, `rating.aggregateRating`→`vote_average`,
`rating.voteCount`→`vote_count`, `genres[]` (strings)→`genres[].name`
(objects, but `id == name` in this API so no lookup table needed),
`releaseDate.{year,month,day}`/`startYear` (two shapes)→`release_date`
(single ISO date string, actually simpler), `certificates[]` (list,
picks `country=='US'`)→`certificate` (single object `{rating, body}`,
already US-equivalent — confirmed live: Inception → `{"rating":"PG-13","body":"MPAA"}`,
so the country-preference loop goes away entirely), `endYear`
(direct field, movies/series)→**not present**; must be derived as
`in_production ? null : year(last_air_date)` for series, N/A for movies.

### 3g. Image fetching loses pagination, gains categorization
Old: `/titles/{id}/images?pageSize=&pageToken=` — flat list, paginated,
used by both the catalog-card carousel (`fetchImages`, 4 images, cached)
and admin's "load more" tool (`fetchImagesUncached`, paginated).
New: `/movie/{id}/images` (or `/tv/{id}/images`) — returns **everything in
one response**, split into `posters[]` / `backdrops[]` / `logos[]` /
`stills[]` (confirmed live: 1 poster + 46 stills for Inception in a single
call; movie images has no backdrops/logos populated per the API's own
description — "IMDb doesn't separate backdrops or logos as distinct
categories — all non-poster art is returned in stills"). This actually
simplifies the cached `fetchImages` path (one call, no pagination to
manage) but the admin "load more" button and `nextPageToken` plumbing in
`fetchImagesUncached` becomes dead code — the equivalent new behavior is
"fetch once, client-side-paginate through the array you already have."

## 4. Field mapping reference

| Current (`ImdbData` / old API) | New API field | Notes |
|---|---|---|
| `id` | `id` | unchanged, same `tt` scheme |
| `title` (`primaryTitle`) | `title` (movie) / `name` (TV) | key rename, differs by type |
| `plot` | `overview` | rename |
| `genres[]` (string) | `genres[].name` | object now, but `id==name`, so `.map((g) => g.name)` is a drop-in |
| `posterUrl` (`primaryImage.url`) | `poster_path` | still a full HTTPS URL |
| `releaseDate` (object or bare year) | `release_date` (movie) / `first_air_date` (TV) | now a single ISO date string — simpler |
| `rating` (`rating.aggregateRating`) | `vote_average` | rename |
| `voteCount` (`rating.voteCount`) | `vote_count` | rename |
| `runtimeSeconds` | `runtime` (movie, **minutes** — ×60) / episode `runtime` (**seconds**, direct) | unit mismatch, see §3e |
| `stars[]` | not in detail response — `GET /{type}/{id}/credits` → `cast[].name` (ordered by `order`) | extra call, see §3d |
| `certificate` (loop over `certificates[]` for `country=='US'`) | `certificate.rating` | now a single object, no loop needed |
| `endYear` | not present — derive from `!in_production ? null : year(last_air_date)` | TV only |
| `seasonNumber` / `episodeNumber` | `season_number` / `episode_number` (from the season/episode endpoint response) | only reachable via the nested episode endpoint |
| `parentId` | not returned — already known from the request path (`series_imdb_id`) | no longer needs sniffing |

## 5. Google Sheets impact — revised: sheet-first, API-once

**Direction from you:** push as much IMDB-derived data as possible into
the Sheet itself at admin-entry time, so the live app calls the API as
close to zero times as possible during normal catalog browsing. This
changes the plan from "same columns, new source" to "new columns +
new merge behavior," so I'm laying it out in full for review.

### 5a. Why this works, and what it doesn't fix

Two things line up in our favor:

1. **The merge pattern already exists — it's just not applied consistently.**
   `CatalogEntry.mergeImdb()` already does "sheet value wins if present,
   API only fills what's blank" for `title`/`date`/`genres`/`plot`/`thumbnailUrl`
   (`catalog_entry.dart:127-145`). It just currently makes an exception for
   `rating`/`voteCount`/`runtimeSeconds`/`stars`/`certificate` — those five
   are unconditionally overwritten by the API every load because there's
   nowhere to read a sheet value from today. Adding sheet columns for them
   and applying the *same* pattern is a small, consistent change, not a new
   pattern.
2. **Two of the three sheets already half-did this and it got lost.**
   `series_sheet_schema.dart` already has a `rating` column (idx 6) —
   but `series_notifier.dart`'s `_buildEntries()` never reads it back
   (no `sc(row, ['rating'])` call anywhere in that method), so it's
   currently a dead column: written by admin, ignored on load, silently
   clobbered by the live API value in `withImdb()`. Same story for
   Episodes' `rating` (idx 8) — it *is* read into `EpisodeEntry.imdbRating`
   at parse time (`series_notifier.dart:240,255`), but then unconditionally
   overwritten a few lines later in the enrichment step (`:331`) regardless
   of whether the sheet already had a value. Both are existing bugs this
   change fixes as a side effect.

What this **doesn't** eliminate: the admin "add new title" flow still
needs to call the API at least once per title (that's the one-time cost
you're asking for), the "request new title" validation flow still needs a
lookup to show a preview, and any row where the admin leaves an optional
column blank still falls back to a live fetch, same safety net as today.
It also doesn't change §3g (images) — `slide_images` already persists a
curated set of poster/still URLs to the sheet and always has; no change
needed there.

### 5b. Proposed new columns

Appended at the **end** of each tab, not inserted in the middle — the TSV
schemas are strictly positional (`parseTsv`/`buildTsv` in each
`*_sheet_schema.dart`), and inserting mid-row would require you to
manually reorder columns in the live Google Sheet to match. Appending is
purely additive: `parseTsv` already pads short rows with `''` up to
`columnCount`, so existing rows read fine with the new columns simply
blank until backfilled, and the read path (`CatalogEntry.fromRow`, and
`series_notifier.dart`'s header-alias lookups) matches by **header name**,
not position, so column order in your actual spreadsheet doesn't need to
match the moment you add the header text.

**⚠️ You'll need to manually add the new header names to row 1 of your
live Sheet(s)** — the app reads a published CSV export, it can't create
columns for you.

**Movies** (`sheet_schema.dart`) — currently 13 columns, would become 17:

| New column | Source (new API) | Format | Example |
|---|---|---|---|
| `rating` | `vote_average` | 1dp decimal | `8.8` |
| `runtime_min` | `runtime` (movie endpoint — already minutes) | integer | `148` |
| `certificate` | `certificate.rating` | string | `PG-13` |
| `stars` | `GET /movie/{id}/credits` → `cast[].name`, top 3 by `order` | comma-space joined | `Leonardo DiCaprio, Joseph Gordon-Levitt, Elliot Page` |

**Series** (`series_sheet_schema.dart`) — `rating` already exists (fix the
dead-read bug, no new column); currently 10 columns, would become 12:

| Column | Status | Source | Format |
|---|---|---|---|
| `rating` | *existing, currently unread* | `vote_average` | 1dp decimal |
| `certificate` | new | `certificate.rating` | string |
| `stars` | new | `GET /tv/{id}/credits` → `cast[].name`, top 3 | comma-space joined |

**Episodes** (`episode_sheet_schema.dart`) — `rating` already exists (fix
the clobber bug, no new column); currently 14 columns, would become 15:

| Column | Status | Source | Format |
|---|---|---|---|
| `rating` | *existing, currently clobbered* | `vote_average` | 1dp decimal |
| `runtime_min` | new | episode `runtime` (**seconds** — ÷60 at write time) | integer |

**Decided:** `vote_count` stays out entirely (unused in UI today, would be
dead weight). Series/Episodes' `certificate`/`stars` will get matching UI
additions — `series_card.dart` and the series/episode detail screens gain
the same certificate/stars display Movies' `catalog_card.dart` already
has, once the columns exist. `stars` still not proposed for Episodes by
default — guest cast varies per-episode and is a weaker signal than
movie/series leads; easy to add later if wanted.

### 5c. Merge-logic change

Extend the existing "sheet wins, API fills blanks" pattern
(`catalog_entry.dart:127-145`) to the five previously-API-only fields, and
fix the two dead/clobbered `rating` reads in `series_notifier.dart`. In
`catalog_notifier.dart`/`series_notifier.dart`, the `resolve()` call
becomes conditional: only IDs whose sheet row is **missing one of the new
columns** get queued for a live fetch; a fully-backfilled row skips the
network entirely. This is incremental, not a one-time migration — old rows
keep working exactly as they do today (live-fetched) until you re-save
them through the admin screen with the new fields populated; there's no
bulk backfill step required to ship this.

Net effect once most rows are backfilled: normal catalog/series browsing
on any device makes **zero** IMDB API calls for existing entries. The API
is only touched when: (a) the admin adds a brand-new title, (b) a sheet
row is missing one of these fields and the fallback kicks in, or (c) a
user pastes an IMDb URL into "Request new title" for validation/preview.

### 5d. Effect on §3a's concurrency/rate-limit concern

Substantially de-risked. §3a's worry was every device issuing N individual
requests on every cold catalog load. Under the sheet-first model, that
only happens for genuinely incomplete rows — a normal load of a fully
backfilled catalog issues **zero** metadata requests, only image URLs
already sitting in `slide_images`/`poster_url`/`thumbnail_url`. The
per-ID concurrency cap from §3a is still needed (for the admin flow, the
fallback path, and the initial backfill period), just no longer sized for
"the whole catalog, every load."

## 6. Error handling / resilience

Today: every failure (timeout, non-200, exception) is silently swallowed
in `ImdbService`, no retries, cache-first with a 30-day TTL, callers
degrade gracefully to sheet-only data. That pattern carries over cleanly,
and §5 makes it matter less in practice — a live-fetch failure now only
affects rows that haven't been backfilled yet, not the whole catalog.
Still worth adding:
- A concurrency cap tuned for "many individual requests" rather than
  reusing the old "batches of 5, 4 at once" constant, which no longer
  means anything.
- Since this is an unofficial proxy with a documented `502` response for
  "Upstream IMDb GraphQL error" (i.e., it has its own upstream fragility
  baked into the spec), the existing swallow-and-degrade behavior is
  probably still the right call rather than adding retry logic — but it
  does mean transient 502s will look identical to "this title doesn't
  exist" from the app's point of view, same as today.

## 7. No tests currently cover this

`test/core_test.dart` only tests CSV row parsing (`CatalogEntry.fromRow`),
never `ImdbService` or `ImdbData.fromApi`. No HTTP mocking exists in the
project. Recommend adding a couple of focused unit tests for
`ImdbData.fromApi` against fixed fixtures (using the live samples pulled
during this analysis) specifically covering §3e's unit conversion, since
that's the one change that fails silently (wrong number, not a crash) if
gotten wrong — everything else in a migration like this tends to fail
loudly (null/type errors) and gets caught in manual testing.

## 8. Suggested scope for this release

1. Rewrite `ImdbService` internals: per-ID fetch with concurrency cap,
   type-aware endpoint selection (movie/tv/tv-episode), drop the
   batch/pageToken plumbing.
2. Rewrite `ImdbData.fromApi` for the new field names + unit conversions
   (§4), keep `fromJson`/`toJson` (disk cache format) unchanged so
   existing caches don't need a version bump — new fetches just repopulate
   the same on-disk shape.
3. Add the `stars` field to `ImdbData` sourced from `/credits`, fetched
   once by the admin screen when building a row (§5b/§5c) — no longer a
   per-catalog-load concern.
4. Add the new columns from §5b to `sheet_schema.dart`,
   `series_sheet_schema.dart`, `episode_sheet_schema.dart` (append-only,
   bump each `columnCount`); update `admin_screen.dart`'s
   `_rowValues`/`_seriesRowValues`/`_episodeRowValues` to populate them;
   add `certificate`/`stars` display to `series_card.dart` and the
   series/episode detail screens, matching `catalog_card.dart`'s existing
   pills.
5. Fix the two dead/clobbered `rating` reads in `series_notifier.dart`
   and extend the "sheet wins, API fills blanks" pattern
   (`catalog_entry.dart:127-145`) to `rating`/`runtime`/`certificate`/`stars`
   everywhere; make `resolve()` calls conditional on missing fields (§5c).
6. Update `admin_screen.dart`'s episode fetch to use
   `series + season + episode` instead of a flat episode-ID lookup (§3c);
   simplify/remove the "load more images" pagination UI (§3g).
7. Update `request_notifier.dart`'s type inference to try
   `/movie/{id}` → `/tv/{id}` and decide how to message unresolvable
   episode-URL submissions (§3b).
8. Add the unit tests from §7, at minimum for runtime conversion and the
   new sheet-wins merge behavior.
9. Manually re-test the full golden path per `CLAUDE.md`'s UI-testing
   requirement: catalog load (movies + series + episodes) with a
   backfilled row (should make no API call) and a non-backfilled row
   (should fall back correctly), admin fetch/paste flow for all three
   modes, "request new title" for a movie, a series, and (to confirm the
   documented gap) an episode URL.

**Sheet schema changes required** (opt-in, backward-compatible, append-only
— see §5b for exact columns).

---

**Resolved:**
- Series/Episodes get matching `certificate`/`stars` UI, not just storage.
- `vote_count` stays out of the schema entirely.
- §3b: double-404 (movie + tv) gets an explicit "couldn't find this as a
  movie or TV series — if it's an episode link, submit the series page
  instead" message rather than a silent guessed-type fallback.
- No fallback data source for now — accepted risk of depending on a
  single unofficial proxy; service layer will still be reasonably
  contained to `imdb_service.dart` if a future swap is ever needed.

**Status: plan approved — starting implementation on `feat/v1.7.0`.**

# mStorage — UI Theme Exploration

> **What this document is.** A catalogue of alternative visual identities for mStorage.
> Each theme is a *complete* aesthetic — colours, typography, layout, navigation, shape
> language and motion — designed so the app can look like an entirely different product
> **without changing a single line of feature logic**.
>
> **How to use it with Claude Code.** Point Claude at this file and say something like:
> *"Apply the **Phosphor** theme from `docs/ui-themes.md` on a new branch. Presentation
> only — do not touch any feature logic, providers, services, or async flows."*
> The [Implementation Playbook](#implementation-playbook) at the bottom is the contract
> Claude should follow every time.
>
> Themes are **mutually exclusive explorations**, not features to ship together. Pick one,
> try it, throw it away or keep it. The baseline ("Spectrum") is what ships today.

---

## 0. The current look, named: **"Spectrum"**

So we have a shared reference point, here is today's design language written in the same
vocabulary as the alternatives below.

| Axis | Spectrum (today) |
|---|---|
| **Concept** | Dark "developer-tool" surface where **each page owns one neon colour**; the entire chrome (title-bar dot, sidebar accent, content tint) morphs to that colour as you navigate. |
| **Base** | Near-black `#0A0A0F`, layered surfaces `#13131A` / `#1C1C26`, hairline border `#2A2A38`. |
| **Accent model** | **Per-page neon.** Encode = blue, Decode = green, Player = rose, Catalog = amber, Settings = violet, Admin = cyan, Series = orange. Each is a `TabPalette {primary, secondary, glow, surface}`. |
| **Typography** | Space Grotesk (geometric, techy). |
| **Shape** | 10–12 px radius, soft. |
| **Elevation** | Translucent **glows** behind icons/dots (`blurRadius` + low-alpha accent). |
| **Navigation** | 72 px vertical **icon rail** on the left; active item has a 3 px left border + tinted fill + glowing icon. |
| **Motion** | Fade + slide-up page transitions (280 ms); whole-chrome colour morph on tab switch; pulsing "running" dots; toast slide-ins. |
| **Vibe** | Linear / cyberpunk-lite / neon dashboard. |

Everything below is a deliberate departure from this.

---

## 1. How the theme system is wired (read before implementing anything)

A re-skin is safe because presentation is concentrated in a few seams. Touch these; leave
everything else alone.

| File | Role | What a theme changes here |
|---|---|---|
| `lib/core/theme/app_theme.dart` | Global `ThemeData`, the `k*` colour constants, the Google Font. | All base colours, font, input/card styling, radius defaults. |
| `lib/core/theme/tab_colors.dart` | `TabPalette` + the per-tab `tabPalettes` map + `kSeriesPalette`. | The accent model. A theme may keep per-page colours, collapse them to one brand accent, or desaturate them — but **keep the `TabPalette` shape and the map keys** so call-sites don't break. |
| `lib/features/shell/app_shell.dart` | Custom title bar, the 72 px icon rail, page-transition animations, content-surface tint, toasts. | Navigation style, window chrome, transition feel, overall layout frame. |
| `lib/features/shell/widgets/shared_widgets.dart` | `SectionHeader`, `SmallButton`, `ErrorBanner`, `PasswordWarningBanner`, `OutDirRow`. | The repeated building blocks every screen uses — restyle these and most screens follow automatically. |

**The token contract.** Every theme is defined by filling in the same set of tokens. If a
theme supplies all of these, the screens inherit it for free:

- **Surfaces:** `bg`, `surface`, `surface2`, `border`
- **Text tiers:** `textPrimary`, `textSecondary`, `textMuted`
- **Accent model:** either one brand accent or a per-page `TabPalette` map
- **Type:** font family (heading + body if split), weights, letter-spacing, case
- **Shape:** corner radius scale, border weight
- **Elevation:** shadow / glow / glass / extrusion model
- **Spacing:** base unit, page padding, control padding
- **Navigation:** rail vs top-tabs vs floating dock vs command-bar
- **Motion:** transition type, duration, easing

**Hard rules for any re-skin (functionality preservation):**
1. Change only widget *appearance* — never provider logic, notifiers, services, async flows, file I/O, or media-kit / webview wiring.
2. Keep the `AppTab` enum and every `tabPalettes` key. Keep `TabPalette`'s four fields (you may repurpose `glow`, e.g. as a gradient stop, but the field must exist).
3. Keep all public widget constructors/params used by screens (`SectionHeader(icon, title, subtitle, color)` etc.). Restyle the body, preserve the signature.
4. Preserve all interaction affordances: drag-and-drop zones, hover states, tooltips, running indicators, update badge, toasts, fullscreen-hides-chrome behaviour.
5. After applying, run `flutter analyze` and `flutter build windows --release` — both must pass.

---

## 2. The themes at a glance

| # | Name | One-liner | Light/Dark | Accent model | Nav | Font feel |
|---|---|---|---|---|---|---|
| 1 | **Monolith** | Swiss-brutalist; structure as decoration | Light | Mono + 1 loud accent | Top text tabs | Grotesk + mono |
| 2 | **Aurora** | Frosted glass over a living gradient | Dark | One gradient | Floating glass dock | Soft sans |
| 3 | **Manuscript** | A printed magazine you can run | Light (paper) | One restrained ink accent | TOC-style list | Serif display + sans |
| 4 | **Phosphor** | A hacker terminal — on-theme for stego | Dark (CRT) | One phosphor hue | Command bar | Monospace |
| 5 | **Clay** | Soft, tactile, extruded toy UI | Light/soft | One candy accent | Soft pill rail | Rounded sans |
| 6 | **Halcyon** | The calm, muted, anti-neon pro tool | Dark | Desaturated per-page | Quiet rail | Neutral sans |

Pick by feeling: want **serious & quiet** → Halcyon. **Premium & literary** → Manuscript.
**Bold & opinionated** → Monolith. **Lush & modern** → Aurora. **Playful** → Clay.
**On-brand for a steganography tool** → Phosphor.

---

## 3. Theme specs

Each spec is written so it can be lifted directly into an implementation prompt.

---

### 1 — Monolith
*Swiss / brutalist. Loud type, hard edges, no glow, one screaming accent. Looks like a
design studio's internal tool.*

**Concept.** Decoration is banned; **structure is the decoration.** Visible grid, hard
black hairlines, oversized typographic hierarchy, and exactly one high-voltage accent used
sparingly. The per-page rainbow is gone — there is one accent for the whole app.

**Colour tokens**

| Token | Hex |
|---|---|
| bg | `#FAFAF7` (paper white) |
| surface | `#FFFFFF` |
| surface2 | `#F0F0EC` |
| border | `#0B0B0B` (hard black, 1.5 px) |
| textPrimary | `#0B0B0B` |
| textSecondary | `#3A3A38` |
| textMuted | `#8A8A86` |
| **accent** | `#1F1FFF` electric blue *(or `#FF3B00` signal orange — pick one)* |

**Typography.** Headings: **Archivo** / **Space Grotesk** in 800 weight, tight tracking,
large. Labels & metadata: **Space Mono** uppercase, `letterSpacing: 1.5`. Body: same
grotesk, regular.

**Shape & elevation.** Radius `0`. Borders `1.5 px` solid black on every panel, input and
button. **No shadows, no glows.** Optional 1 px grid rules between sections.

**Navigation & layout.** Replace the icon rail with a **top horizontal tab bar**: uppercase
text labels (`ENCODE  DECODE  PLAYER  …`), active tab = solid black block with white text
(or a thick 3 px underline). Title bar becomes a stark black band with the wordmark in mono.
Content area is plain `bg` (no per-page tint).

**Components.**
- *Buttons:* sharp filled rectangles — accent fill, white label, OR black outline + black label. Hover = invert.
- *Inputs:* white box, 1.5 px black border, label uppercase mono above the field.
- *Cards:* white, hard black border, no radius; header bar separated by a 1.5 px rule.
- *SectionHeader:* drop the glowing icon chip → big black title + thin mono subtitle, accent only on a small leading square.
- *ErrorBanner:* black border, accent-tinted fill, mono text.

**Motion.** Near-instant. 100 ms hard fades, no slide, no colour morph. Brutalism doesn't
animate much.

**What makes it feel different.** Light, sharp, typographic, monochrome — the literal
opposite of soft glowing neon.

---

### 2 — Aurora
*Glassmorphism / spatial UI. Frosted translucent panels floating over an animated gradient
mesh. visionOS / macOS Big Sur energy.*

**Concept.** Depth through **blur and translucency**, not borders. A slow-moving multi-stop
gradient lives behind everything; UI panels are frosted glass that let it bleed through. One
gradient accent replaces the rainbow.

**Colour tokens**

| Token | Value |
|---|---|
| bg | animated gradient mesh: `#1E1B4B` → `#312E81` → `#0F766E` (indigo→violet→teal), very slow drift |
| surface (glass) | `Colors.white @ 6%` over `BackdropFilter(blur: 24)` |
| surface2 (glass) | `Colors.white @ 10%` |
| border | `Colors.white @ 14%` (1 px hairline) |
| textPrimary | `#F5F5FF` |
| textSecondary | `#C4C2E0` |
| textMuted | `#8E8CB0` |
| **accent gradient** | `#6EE7F9` → `#A78BFA` (cyan→violet) |

**Typography.** **Inter** (or Manrope) — soft, modern, slightly rounded. Medium weights,
generous line height.

**Shape & elevation.** Large radius `20–28 px`. Elevation = blur + a soft coloured ambient
glow under floating panels. Frosted everything.

**Navigation & layout.** Turn the rail into a **floating glass dock** — either a vertical
pill on the left margin or a horizontal pill centered at the bottom — detached from the
edges with margin around it. Title bar becomes a translucent strip. Active nav item = the
accent gradient as a filled rounded chip.

**Components.**
- *Buttons:* pill-shaped, accent-gradient fill with a soft outer glow; secondary = glass with hairline.
- *Inputs:* glass field, inner hairline, gradient focus ring.
- *Cards:* frosted glass with 1 px white-alpha border and a faint inner top highlight.
- *SectionHeader:* icon in a frosted circle, title in white, gradient used only on the icon.

**Motion.** Smooth and springy. Panels scale-fade in (`Curves.easeOutBack`). Background
gradient drifts continuously. Subtle parallax: background shifts slightly opposite to page
transitions.

**Implementation note.** Wrap the content area in a `Stack` → animated gradient
`Container` at the back, then `BackdropFilter` glass panels. `flutter_animate` (already a
dep) covers the drift and entrances.

**What makes it feel different.** Colour comes from *light and gradient*, not solid blocks;
everything floats and blurs instead of sitting on flat dark cards.

---

### 3 — Manuscript
*Editorial light theme. Warm paper, serif display headings, ink text, hairline rules,
generous whitespace. Reads like a premium magazine or a Kindle.*

**Concept.** Content-first and literary. Calm, warm, printed. The app feels less like a
"tool" and more like a **publication**. One restrained ink accent; whitespace does the work
the neon used to do.

**Colour tokens**

| Token | Hex |
|---|---|
| bg | `#F6F2E9` (warm paper) |
| surface | `#FBF9F3` |
| surface2 | `#EFE9DA` |
| border (hairline) | `#E2DBCB` |
| textPrimary (ink) | `#1C1A17` |
| textSecondary | `#6B6357` |
| textMuted | `#A39A88` |
| **accent** | `#2B4C7E` ink-blue *(or `#B4552D` terracotta)* |

**Typography.** Headings: **Fraunces** (or Playfair Display / Libre Caslon) — a real serif
display face, used large. Body: **Source Sans 3** / **Inter** at comfortable reading size,
`height: 1.6`. Labels: small-caps, tracked.

**Shape & elevation.** Radius `4 px`. **Hairline rules** instead of borders+shadows. No
glow. Optional very subtle paper grain. Lots of breathing room (page padding `40 px`+).

**Navigation & layout.** Left side becomes a **table-of-contents menu**: serif/small-caps
text items, active = ink accent with a thin left rule — no icons-as-buttons, more like a
chapter list. Title bar = thin band with a serif wordmark and a hairline underneath.

**Components.**
- *Buttons:* understated — ink-accent text buttons with a hairline box, or a quiet filled accent for the single primary action.
- *Inputs:* underlined fields (bottom hairline only) with small-caps labels.
- *Cards:* paper cards separated by hairlines and whitespace rather than heavy borders.
- *SectionHeader:* large serif title + sans subtitle; accent reserved for a small leading mark.
- *ErrorBanner:* warm, low-key — terracotta hairline + ink text, no alarm-red.

**Motion.** Gentle. Slow cross-fades (page-turn feel), no sliding chrome, no pulsing.

**What makes it feel different.** Light, warm, serif, spacious — a tonal and emotional
inversion of the dark neon dashboard.

---

### 4 — Phosphor
*Retro terminal / CRT. Monospace everything, one phosphor colour, ASCII frames, scanlines.
Thematically perfect for a steganography tool.*

**Concept.** The whole app pretends to be a **CRT terminal**. One phosphor hue (classic
green or amber) at varying brightness is the entire palette. Panels are drawn as boxes with
corner brackets and title-in-the-border. Hidden-data tool → hacker aesthetic is on-brand.

**Colour tokens**

| Token | Hex |
|---|---|
| bg | `#020402` (near-black with green cast) |
| surface | `#050A05` |
| surface2 | `#08120A` |
| border | `#1C3D1C` (dim phosphor) |
| textPrimary | `#33FF66` (bright phosphor) |
| textSecondary | `#1FA847` |
| textMuted | `#0F5C28` |
| **accent** | `#5BFF8F` (hot phosphor) — *amber variant: bg same, hue `#FFB000`* |

**Typography.** **JetBrains Mono** / **IBM Plex Mono** / Space Mono — monospace
*everywhere*, including headings. Slight glow on text (thin shadow in accent).

**Shape & elevation.** Radius `0`. Elevation = a soft phosphor **bloom** (low-alpha accent
blur) instead of drop shadows. Optional full-screen overlays: faint horizontal **scanlines**
+ very subtle flicker/vignette.

**Navigation & layout.** Replace the rail with a **command bar**: a left list rendered like
a menu — `> ENCODE`, `  DECODE`, `  PLAYER` — active row prefixed with a blinking `>` cursor;
or a numbered bar `[1] ENCODE  [2] DECODE …`. Title bar = a status line:
`mstorage v1.5.0 — [ENCODE] ───────── ● READY`.

**Components.**
- *Panels:* drawn as boxes with `┌─ TITLE ─────┐ … └────────────┘` corner brackets; the title sits in the top rule.
- *Buttons:* `[ RUN ]`, `[ BROWSE ]` — bracketed labels; hover = inverted (accent bg, black text).
- *Inputs:* underline or full box with a blinking cursor glyph; mono placeholder.
- *Progress / pipeline:* ASCII bars `[####------] 41%`, spinner from `| / - \`.
- *SectionHeader:* `// SECTION NAME` comment-style, accent on the `//`.

**Motion.** Typewriter text reveals on screen entry; blinking cursor; flicker on the bloom.
Snappy, no smooth slides.

**Implementation note.** A reusable `TerminalBox` wrapper (CustomPaint border + title) and a
`BlinkingCursor` widget will cover most screens. Scanlines = a single `IgnorePointer` overlay
with a repeating gradient; keep it subtle.

**What makes it feel different.** It stops looking like a 2020s app entirely — it looks like
a machine. Maximum distance from Spectrum.

---

### 5 — Clay
*Neumorphism / claymorphism. Soft monochrome surfaces, extruded dual-shadow shapes, candy
accent, big round corners. Tactile and friendly.*

**Concept.** Everything is made of the **same soft material as the background** and pops out
(or presses in) via paired light/dark shadows. Chunky, rounded, squishy, playful — a
complete personality flip from the sharp neon dashboard.

**Colour tokens** (light variant)

| Token | Hex |
|---|---|
| bg | `#E8EAF1` (soft warm grey) |
| surface | `#E8EAF1` (same as bg — pop is from shadow) |
| surface2 | `#EDEFF5` |
| border | none (use shadows) |
| shadow-light | `#FFFFFF @ 80%` (top-left) |
| shadow-dark | `#A6ABBD @ 55%` (bottom-right) |
| textPrimary | `#3A3D4D` |
| textSecondary | `#6E7287` |
| textMuted | `#A0A4B8` |
| **accent** | `#9B8CFF` lavender *(or `#5BD6A8` mint)* |

*Dark variant: bg `#23252E`, light-shadow `#2C2F3A`, dark-shadow `#171922`.*

**Typography.** **Nunito** / **Quicksand** (rounded sans). Friendly, medium-bold.

**Shape & elevation.** Big radius `18–28 px`. **No borders or glow** — elevation is the dual
soft-shadow ("extruded") look. Pressed/active state = **inset** shadows (concave).

**Navigation & layout.** Rail items become soft extruded **pills**; the active item is
*pressed in* (inset) with an accent icon. Title bar is a soft raised bar. Content sits on the
same material, no tint.

**Components.**
- *Buttons:* raised clay pills; on press they depress (inset) with a spring.
- *Inputs:* inset (concave) fields, as if carved into the surface.
- *Cards:* raised clay panels with generous padding and big radius.
- *Toggles:* physical-switch look. *Progress:* an inset track with a raised accent fill.
- *SectionHeader:* icon in a raised clay circle, accent-tinted.

**Motion.** Bouncy springs on press/release; gentle scale on hover. Soft, toy-like.

**Implementation note.** A `ClayContainer` helper taking `depth` and `isPressed` (two
`BoxShadow`s, opposite offsets) is the core primitive — almost every component composes from
it. Keep shadow offsets small (4–6 px) so it reads as "soft," not "embossed."

**What makes it feel different.** No hard edges, no glow, no color blocks — just soft
extruded material. Warm and toy-like vs. cold and techy.

---

### 6 — Halcyon
*The calm, muted, anti-neon pro tool. Stays dark, but trades the neon rainbow for a
low-saturation, restful Nord / Tokyo-Night palette. The "serious mode."*

**Concept.** Keep the dark, professional layout the user already likes — but **turn the
saturation way down.** No glows, no electric colours. This is the smallest leap from
Spectrum while still feeling like a different, more grown-up app: an IDE/Obsidian mood.

**Colour tokens**

| Token | Hex |
|---|---|
| bg | `#1A1B26` |
| surface | `#1F2335` |
| surface2 | `#24283B` |
| border | `#2E3350` |
| textPrimary | `#C0CAF5` |
| textSecondary | `#9AA5CE` |
| textMuted | `#565F89` |

**Accent model — desaturated per-page** (keeps the per-page identity, drops the neon):

| Tab | Hex |
|---|---|
| Encode | `#7AA2F7` steel blue |
| Decode | `#9ECE6A` sage |
| Player | `#F7768E` dusty rose |
| Catalog | `#E0AF68` muted gold |
| Settings | `#BB9AF7` soft lilac |
| Admin | `#7DCFFF` pale sky |
| Series | `#FF9E64` muted orange |

> *Alternative:* collapse to a single accent (`#7AA2F7`) for an even quieter, more unified
> feel — decide at implementation time.

**Typography.** **Inter** or **IBM Plex Sans** — neutral, professional, no personality
quirks. Normal weights.

**Shape & elevation.** Radius `8 px`. Thin 1 px borders. **Remove glows** — replace
`BoxShadow(glow)` with either nothing or a barely-there `Colors.black @ 30%` drop. Active
states use a soft accent fill (`@ 12%`) + a 2 px left border, no bloom.

**Navigation & layout.** Same 72 px rail and top bar (familiar), but quiet: muted icon
colours, no glow, subtle fill on active. The "running" dot pulses gently instead of glowing.

**Components.** Same structures as today, restyled flat: calm focus rings, understated
buttons (`@ 10%` fill), flat cards, soft non-alarming banners.

**Motion.** Keep the existing transitions but shorten/soften (200 ms crossfade, less slide).
Drop the whole-chrome neon morph or make it a subtle tint shift.

**Implementation note.** Lowest-effort theme — mostly a swap of the `k*` constants and the
`tabPalettes` values plus deleting/softening glow `BoxShadow`s. Layout untouched.

**What makes it feel different.** Same bones, completely different temperature — from
"energetic neon dashboard" to "focused, quiet workspace."

---

## Implementation Playbook

Follow this every time a theme from this doc is applied.

**Step 0 — Branch.** `git checkout -b theme/<name>` (e.g. `theme/phosphor`). One theme per
branch.

**Step 1 — Tokens first.** Rewrite `lib/core/theme/app_theme.dart`:
- Swap the `k*` colour constants to the theme's surface/text tokens.
- Swap the Google Font (`GoogleFonts.<family>TextTheme`). Split heading/body fonts if the theme calls for it.
- Update `inputDecorationTheme`, `cardColor`, radius defaults, focus border.

**Step 2 — Accent model.** Edit `lib/core/theme/tab_colors.dart`:
- Keep `TabPalette`'s fields and every `tabPalettes` key + `kSeriesPalette`.
- For per-page themes (Halcyon): replace the colour values.
- For single-accent themes (all others): set every palette's `primary`/`secondary` to the one brand accent (and repurpose `glow` as needed). This makes the whole app drop the rainbow with zero call-site edits.

**Step 3 — Shell / navigation.** Edit `lib/features/shell/app_shell.dart`:
- Reshape `_TitleBar`, `_Sidebar`/`_SidebarItem` (or replace the rail with top-tabs / dock / command-bar per the theme).
- Adjust page-transition animations and the content-surface tint.
- **Preserve behaviour:** dragging, maximize/restore/close, fullscreen-hides-chrome, the update badge, running indicators, and the toast stack.

**Step 4 — Shared widgets.** Restyle `lib/features/shell/widgets/shared_widgets.dart`
(`SectionHeader`, `SmallButton`, `ErrorBanner`, `PasswordWarningBanner`, `OutDirRow`) —
**keep their constructor signatures.** Most screens update for free once these change.

**Step 5 — Per-screen sweep.** Grep for hardcoded styling that bypasses tokens and fix it:
- `withValues(alpha:` glow `BoxShadow`s (kill/soften for flat themes),
- hardcoded hex literals (e.g. `ErrorBanner`'s reds, drop-zone colours),
- `BorderRadius.circular(<n>)` literals → align to the theme's radius,
- any `GoogleFonts.` or `TextStyle(fontFamily:` overrides in screens.
- Screens to check: `encode_screen`, `decode_screen`, `player_screen`, `catalog_screen`,
  `settings_screen`, `admin_screen`, `series_detail_screen`, and the `widgets/` under each
  feature (`drop_zone`, `progress_pipeline`, `catalog_card`, `series_card`,
  `catalog_detail_panel`, `extracted_files_list`, `webview_overlay`).

**Step 6 — Verify.**
- `flutter analyze` → clean.
- `flutter build windows --release` → succeeds.
- Manually click through every tab: navigation, drag-drop, encode/decode runs, player,
  catalog grid, settings, update flow, toasts — all must behave exactly as before.

**Guardrails (do not cross):**
- No edits to providers, notifiers, services, models, or async/file/media/webview logic.
- No renaming of `AppTab` values or `tabPalettes` keys.
- No changes to widget *behaviour* — only paint.

---

## Optional: make themes switchable instead of swap-and-throw

If, after trying a few, the goal becomes "let the user choose," the clean path is:

1. Promote tokens to a `ThemeSpec` object (all the tokens in §1) rather than top-level
   `const`s, and provide them via a Riverpod provider (`activeThemeProvider`).
2. Define one `ThemeSpec` per theme in `lib/core/theme/specs/`.
3. Replace direct `k*` references with `context`/`ref` lookups (a `Theme.of`-style extension).
4. Add a theme picker in Settings persisting to `shared_preferences` (the settings service
   already exists).

This is a larger refactor — only worth it once a shortlist of keepers exists. For pure
exploration, swap-on-a-branch (the Playbook above) is faster.

---

## Adding more themes later

Append a new `### N — Name` section using the same spec shape (Concept → Colour tokens →
Typography → Shape & elevation → Navigation & layout → Components → Motion → What makes it
feel different). Ideas not yet specced: **Sunset** (warm gradient light), **Carbon** (IBM
Carbon enterprise), **Vapor** (80s synthwave), **Mono** (pure greyscale + one accent),
**Kawaii** (pastel maximalist).

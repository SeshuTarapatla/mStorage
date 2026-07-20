# UX Improvements — v1.1 Polish Pass

A screen-by-screen audit of animation gaps, interaction feedback issues, and general
UX rough edges. Nothing here is a bug fix — everything is about making the app feel
alive and deliberate. Items are grouped by area, with a rough effort estimate and a
priority tag.

Priority: **P1** = essential for a polished release · **P2** = noticeable improvement ·
**P3** = nice-to-have / low ROI

---

## 1. Global / Cross-Cutting

### 1.1 Tab switching has no transition  `P1`
`IndexedStack` swaps tabs instantly. Switching from Catalog to Settings is a jarring
jump. A short cross-fade (150–200 ms) or a subtle slide in the direction of the tab
order would make navigation feel intentional.

**Approach:** Replace `IndexedStack` with an `AnimatedSwitcher` using a custom
`FadeTransition`, or keep `IndexedStack` and layer a per-tab fade-in wrapper.

---

### 1.2 No press feedback on most buttons  `P1`
Hover states exist throughout (via `MouseRegion`), but almost no button responds to
the actual press/click with a scale or brightness change. On Windows with a mouse,
this gap is obvious — you click and nothing "gives".

**Approach:** Add a tiny scale-down (`0.96×`, 80 ms ease-in / ease-out) on `onTap`
for all `GestureDetector`-based buttons. A global `InkWell` replacement or a small
`_PressableButton` helper widget would cover the whole app at once.

---

### 1.3 Tooltips missing on icon-only controls  `P2`
The sidebar icons, the title-bar window controls, the admin toolbar buttons, and many
small icon buttons have no tooltip. On a desktop app, discoverable affordances matter.

**Approach:** Wrap every icon-only `GestureDetector` with a `Tooltip`. Use
`preferBelow: false` and a short `waitDuration: 600 ms` so they don't interfere with
fast mousing.

---

### 1.4 Section headers could stagger on first paint  `P2`
Each screen uses `flutter_animate` `.fadeIn()` with a flat delay per group, but the
delays are uniform (40 ms apart). A more natural stagger (20 ms → 40 ms → 70 ms →
100 ms, accelerating) reads as more intentional.

---

### 1.5 Scroll physics on all `SingleChildScrollView` pages  `P3`
Windows Flutter uses `ClampingScrollPhysics` by default. Switching to
`BouncingScrollPhysics` on scrollable settings, catalog detail, and admin form
panels gives a softer, more premium feel.

---

## 2. App Shell (Sidebar + Title Bar)

### 2.1 Active tab indicator animation  `P1`
The left-border accent on the active tab appears and disappears instantly when
switching. Animating the border width or the background fill (e.g. expanding from the
icon center outward, 200 ms) makes it feel like a real selection rather than a state
toggle.

**Approach:** Use `AnimatedContainer` on the left accent bar and the background fill
inside each `_SidebarItem`.

---

### 2.2 Tab label visibility on hover  `P2`
The sidebar is 72 px wide — labels are always visible. Consider whether a
collapsed (icon-only) state with a hover-expand would reclaim screen real estate.
If staying expanded, at least animate the label color change from `kTextMuted` to
`kTextPrimary` on hover (currently instant).

---

### 2.3 Window controls feedback  `P2`
Minimize, maximize, and close buttons change background on hover but have no press
animation. The close button in particular should respond more visibly (red background
intensifies on press, then fades as the action fires).

---

### 2.4 Running-process indicator is hard to spot  `P3`
The pulsing dot on the active tab is small and only visible if you know to look for
it. When an encode or download is running, a subtle linear progress bar at the bottom
of the sidebar (or at the top of the screen) would be a much clearer ambient signal.

---

## 3. Encode Screen

### 3.1 Drop zone feels static during hover  `P1`
The drag-over scale (`1.02×`) exists but is very subtle. The dashed border could
animate its dash pattern (marching ants), the icon could bounce slightly, and the
background gradient could shift toward the accent color during a drag.

**Approach:** Use a `TweenAnimationBuilder` on border opacity and a looping
`flutter_animate` shimmer on the container background during hover.

---

### 3.2 Progress pipeline — step transitions are abrupt  `P1`
When a step moves from `idle` → `active` → `done`:
- The connecting line colour changes instantly.
- The step dot jumps from gray to accent to green.
- There is no transition for the percentage counter (it just appears).

**Approach:**
- Animate the connecting line via a `TweenAnimationBuilder` on width (0 → full) with
  an accent colour fill sweeping left-to-right.
- Add a brief checkmark pop animation on step completion (scale 0 → 1.2 → 1.0, 250 ms).
- Count-up animation for the percentage via `AnimatedCounter` or
  `TweenAnimationBuilder<int>`.

---

### 3.3 No success/done celebration  `P2`
After encoding completes, the screen shows a green banner but there is no sense of
completion. A brief confetti burst or just a slightly more expressive done state
(icon scales in, banner slides down) would feel rewarding.

---

### 3.4 Error banner entrance animation missing  `P2`
The `ErrorBanner` widget has a "fade in + shake" animation defined but the shake
(`shimmer` or `shake` from flutter_animate) is not wired up everywhere it is used.
Confirm that encode, decode, and player error banners actually play the shake on
appearance.

---

## 4. Decode Screen

### 4.1 Extracted files list has no entrance animation  `P2`
When extraction finishes, the list of extracted files appears instantly. Staggering
each row with a `.fadeIn().slideX(begin: -0.05)` (20 ms apart) makes the reveal feel
deliberate.

---

### 4.2 Loading state has no skeleton  `P3`
While extraction runs, only the pipeline and a spinner are visible. A faint skeleton
row placeholder where the file list will appear would give the user a sense of what
is coming.

---

## 5. Player Screen

### 5.1 Placeholder ↔ Video area swap is a hard cut  `P1`
`AnimatedSwitcher` is used, but the default cross-fade transition is very quick
(200 ms). The video thumbnail / drag feedback area appears instantly. A 300 ms fade
with a subtle scale-up from 0.96 would feel much smoother.

---

### 5.2 VLC and Syncplay buttons have no press animation  `P1`
These are the primary CTAs in the Player screen. They respond to hover but not to
press. A scale-down on tap plus the glow shadow fading briefly would give clear
tactile feedback.

---

### 5.3 Syncplay log panel — collapse/expand has no animation  `P2`
The log panel toggle is instant. Wrapping it in `AnimatedSize` (same pattern used
in the admin panel error banner) would make the expand/collapse smooth.

---

### 5.4 "Drop to change video" overlay appears instantly  `P2`
When a file is dragged over the video area, the overlay appears immediately.
A 100 ms fade-in prevents the flicker that happens when the user hovers in from
the side.

---

## 6. Catalog Screen

### 6.1 Catalog grid cards have no staggered entrance  `P1`
All cards fade in simultaneously when the catalog loads. Staggering each card
(e.g. `delay: (index * 30).ms`, capped at ~300 ms total) makes the grid feel like it
is "filling in" naturally rather than blinking into existence.

**Important:** cap the max delay so late cards in a long list don't have a 5-second
delay. Use `min(index, 10) * 30` ms or apply only to the first visible viewport.

---

### 6.2 Search/filter does not animate card changes  `P1`
Typing in the search box causes cards to disappear and reappear with no transition.
Using `AnimatedList` or animating out the removed cards (fade + scale down, 150 ms)
and fading in the new set would make filtering feel responsive rather than jumpy.

---

### 6.3 Card expansion/collapse transition could be more fluid  `P1`
The expansion overlay uses `FadeTransition + ScaleTransition` (scale 0.88 → 1.0,
320 ms). The collapse just reverses the route pop, but the scale origin (always
`Alignment.center`) does not match the card's position in the grid. A
`Hero`-style shared element transition from the tapped card's position would be
significantly more satisfying.

**Approach:** Wrap the card thumbnail and the expanded header in a `Hero` with the
same tag (`imdbId`). Flutter handles the interpolation automatically.

---

### 6.4 Slideshow page transitions are cuts  `P2`
The `PageView` between slide images uses the default swipe gesture but the
auto-advance (every 5 seconds) does not animate — it jumps. Call
`_pageCtrl.animateToPage(...)` with a `Curves.easeInOut` and 400 ms duration
instead of `jumpToPage`.

---

### 6.5 Slideshow indicator dots — active dot growth is good, but  `P2`
The active dot grows from 6 to 16 px width (nice), but the color transition between
dots is instant. Animating the color of the adjacent dot as it becomes active would
make the indicator more fluid.

---

### 6.6 Download panel entrance has no animation  `P2`
The download panel appears when a download starts with no slide-in or fade. Wrapping
it in an `AnimatedSize` or a `SlideTransition` from the bottom would make the
state change feel intentional.

---

### 6.7 Genre/tag chips in expanded card appear all at once  `P3`
Staggering the chip appearance (`.fadeIn().slideX(begin: 0.03)`, 15 ms apart) makes
the detail section feel richer without being distracting.

---

### 6.8 Catalog loading state — single spinner with no context  `P3`
A full-screen spinner with no skeleton gives users nothing to orient to. Replacing
it with 6–8 skeleton card placeholders (rounded rectangles that shimmer) would
communicate structure while loading and match the eventual grid layout.

---

## 7. Admin Screen

### 7.1 Image lightbox has no open/close animation  `P1`
`showDialog` opens the lightbox as a plain route push. A custom `PageRouteBuilder`
with a scale + fade from 0.85 → 1.0 (250 ms, easeOutCubic) would make it feel like
a dedicated overlay rather than a navigation push.

---

### 7.2 Image pool items have no entrance animation  `P2`
When images load from the API, they appear all at once. Staggering with
`.fadeIn(delay: (index * 20).ms)` (capped at ~300 ms) gives the pool a sense of
populating progressively.

---

### 7.3 Selecting/deselecting an image has no animation  `P2`
Clicking an image to add it to the selected strip just re-renders. A brief border
flash (accent → fully opaque → normal, 200 ms) on the clicked image and a
"pop in" on the new item in the selected strip would make selection feel immediate
and satisfying.

---

### 7.4 Drag-and-drop reorder — drop feedback is minimal  `P2`
When dragging an image in the selected strip, the target slot doesn't visually
indicate where the item will land. Highlighting the target slot (background fill,
scale-up by 1.05) while the drag is in progress would make reordering more
predictable.

---

### 7.5 Genre reorder list drag feedback  `P3`
`ReorderableListView` gives a default elevation shadow during drag. Matching the
style (dark background, accent border) to the rest of the admin panel would keep
the drag handle consistent with the app's visual language.

---

## 8. Settings Screen

### 8.1 Group entrance stagger could be more dramatic  `P2`
Currently all groups animate in with `fadeIn` at 40/60/120/180/240/260/300 ms delays.
Adding a gentle `slideY(begin: 0.04)` to each group entry (already done on catalog
cards) would add depth without being distracting.

---

### 8.2 Chip selection has no transition  `P2`
The startup-page and mask-duration chip buttons switch states instantly. Adding a
150 ms `AnimatedContainer` on the selected chip's background + border (already used
for `_ChipButton`, but verify it has a `duration` set) would confirm the selection
visually.

Actually on inspection `_ChipButton` does use `AnimatedContainer(duration:
150.ms)` — this one is already done. ✓

---

### 8.3 Password show/hide toggle  `P3`
The visibility icon switches instantly. A subtle `AnimatedSwitcher` cross-fade
between the open-eye and closed-eye icon (100 ms) would polish this small interaction.

---

## 9. Interactions Worth Adding (New)

### 9.1 Cursor changes  `P1`
Most clickable `GestureDetector` elements don't change the cursor to `SystemMouseCursors.click`.
On a Windows desktop app this omission is highly visible — the cursor stays as an arrow
on elements that clearly behave like buttons.

**Approach:** Wrap all `GestureDetector` tap targets with
`MouseRegion(cursor: SystemMouseCursors.click)`. Already done in some places
(tab items, window controls) — needs to be applied everywhere else.

---

### 9.2 Copy-to-clipboard micro-feedback  `P2`
The admin "Copy row" button copies TSV to clipboard silently. A brief icon swap
(copy → check, 1.5 s) communicates success without a banner or dialog.

---

### 9.3 Empty state illustrations are icon-only  `P3`
Every empty state (catalog, player, downloads) uses a single Material icon with text.
Adding a subtle pulse or gentle float animation to the empty-state icon (looping
`flutter_animate` `.scaleXY(begin: 0.97, end: 1.03, duration: 1800.ms)` + reverse)
adds life to what would otherwise be a completely static dead end.

---

### 9.4 Smooth number transitions for download progress  `P2`
The download speed, received bytes, and percentage counter update every 300 ms and
jump to new values. Wrapping them in `TweenAnimationBuilder<double>` with a 250 ms
ease would make the numbers flow rather than stutter.

---

## Summary Table

| # | Area | Item | Priority | Effort |
|---|------|------|----------|--------|
| 1.1 | Global | Tab switch fade transition | P1 | Medium |
| 1.2 | Global | Press feedback on buttons | P1 | Medium |
| 1.3 | Global | Tooltips on icon controls | P2 | Low |
| 1.4 | Global | Better entrance stagger timing | P2 | Low |
| 1.5 | Global | Bouncing scroll physics | P3 | Low |
| 2.1 | Shell | Active tab indicator animation | P1 | Low |
| 2.2 | Shell | Tab label color transition | P2 | Low |
| 2.3 | Shell | Window controls press feedback | P2 | Low |
| 2.4 | Shell | Ambient progress bar | P3 | Medium |
| 3.1 | Encode | Drop zone drag hover effects | P1 | Low |
| 3.2 | Encode | Pipeline step transitions | P1 | Medium |
| 3.3 | Encode | Done celebration | P2 | Low |
| 3.4 | Encode | Error banner shake | P2 | Low |
| 4.1 | Decode | Extracted files stagger | P2 | Low |
| 4.2 | Decode | File list skeleton | P3 | Medium |
| 5.1 | Player | Placeholder ↔ video fade | P1 | Low |
| 5.2 | Player | VLC/Syncplay press animation | P1 | Low |
| 5.3 | Player | Log panel animate collapse | P2 | Low |
| 5.4 | Player | Drag overlay fade-in | P2 | Low |
| 6.1 | Catalog | Grid card staggered entrance | P1 | Low |
| 6.2 | Catalog | Search filter card animation | P1 | Medium |
| 6.3 | Catalog | Hero shared element expand | P1 | High |
| 6.4 | Catalog | Slideshow auto-advance animate | P2 | Low |
| 6.5 | Catalog | Slide indicator color lerp | P2 | Low |
| 6.6 | Catalog | Download panel slide-in | P2 | Low |
| 6.7 | Catalog | Genre/tag chip stagger | P3 | Low |
| 6.8 | Catalog | Skeleton loading cards | P3 | Medium |
| 7.1 | Admin | Lightbox open/close animation | P1 | Low |
| 7.2 | Admin | Image pool entrance stagger | P2 | Low |
| 7.3 | Admin | Image select flash | P2 | Low |
| 7.4 | Admin | Drag-drop target highlight | P2 | Low |
| 7.5 | Admin | Genre drag handle style | P3 | Low |
| 8.1 | Settings | Group slide-in stagger | P2 | Low |
| 8.3 | Settings | Password icon cross-fade | P3 | Low |
| 9.1 | All | Cursor: click on all tap targets | P1 | Low |
| 9.2 | Admin | Copy button → check feedback | P2 | Low |
| 9.3 | All | Empty state icon pulse | P3 | Low |
| 9.4 | Catalog | Smooth download number lerp | P2 | Low |

---

## Recommended Implementation Order

**Phase A — Quick wins, high visibility (1–2 days)**
- 9.1 Cursor fix (sweeping change, all `GestureDetector` targets)
- 1.2 Press feedback helper widget
- 2.1 Active tab indicator `AnimatedContainer`
- 6.1 Catalog grid stagger
- 6.4 Slideshow `animateToPage`
- 5.2 VLC/Syncplay press animation
- 7.1 Lightbox open/close animation
- 1.3 Tooltips sweep

**Phase B — Notable UX improvements (2–3 days)**
- 1.1 Tab switch cross-fade
- 3.2 Pipeline step transitions (line sweep + checkmark pop)
- 6.2 Search/filter card animation
- 5.1 Placeholder ↔ video cross-fade
- 6.6 Download panel slide-in
- 7.3 Image select flash
- 9.4 Download number lerp
- 5.3 Syncplay log panel `AnimatedSize`

**Phase C — Polish & stretch goals (1 day)**
- 6.3 Hero expansion (highest effort but most impressive)
- 6.8 Skeleton loading cards
- 9.3 Empty state pulse
- 3.1 Drop zone marching-ants border
- 6.5 Slide indicator color lerp

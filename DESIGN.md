# SupaClip — UI & interaction spec

Derived from seven reference recordings (Supaste). This is the target; where it
disagrees with what's built, this file wins.

The governing idea: **the notch is a live surface that reacts to every copy**,
not a menu you open. Everything else follows from that.

---

## 1. Surfaces

Four distinct surfaces, each with its own job.

### 1.1 Menu bar menu (native `NSMenu`)
Not a SwiftUI window. A real menu:

```
Open Library Window        ⌘⇧L
Quick Paste…               ⌘⇧V
History                     ▸     → last 10 clips, each with ⌃⌘0–9
Settings                    ▸
Privacy                     ▸
Pause                       ▸
Clear History               ▸
Help                        ▸
Quit                       ⌘Q
```

The History submenu lists clip previews with their own shortcut badges;
choosing one pastes it.

### 1.2 Notch strip — the primary surface
Hangs from the notch, opens on hover.

- Search field, then collection chips, then a right-aligned toolbar:
  compose/new, expand, **eyedropper (colour picker)**, pop-out to Library.
- Cards grouped by day: `Today`, `Yesterday`, then dates.
- Horizontal scroll.

### 1.3 Quick Paste (⌃⌘V)
Compact popup near the cursor. Three-column card grid, same chips. Meant for
"grab one thing and get out".

### 1.4 Library window (⌘⇧L)
Standard window with traffic lights.

- Left: sidebar — `All`, `Favorites`, COLLECTIONS (Assets, Email templates,
  Colors, `+ New collection`), RECENT, then source apps.
- Centre: masonry grid of cards.
- Right: **inspector** — preview, then `CREATED`, `SOURCE`, `DIMENSIONS`,
  `DETAILS`, and a `Copy to clipboard` button pinned at the bottom.

---

## 2. The live notch tray

This is the part that makes the app feel alive, and the part currently missing.

1. User presses ⌘C anywhere.
2. A large translucent **keystroke HUD** (`⌘ C`) flashes at the bottom centre.
3. The notch morphs into a **pill** showing a running count:
   `1 item` → `2 items` → `5 items · Text, Image`.
4. Hovering the pill expands it to show the stack as thumbnails.
5. The stack can be **dragged out as a unit** — dropping into Finder writes all
   five files; dropping into Mail/Notes pastes all five.

The tray is a staging shelf, not a selection. There is no checkbox mode. Bulk
copy = copy repeatedly, then drag the pill.

Dragging files *toward* the notch shows a large translucent rounded drop zone.

---

## 3. Detail panel

A separate floating card **below** the notch strip — not a sheet, not a modal.
Opened by the eye icon on card hover.

Header row: `[icon] Kind · <metadata> … Copy ⌄ | [export] | [edit] | [✕]`

| Kind | Metadata | Body |
|---|---|---|
| Image | `992 × 1200`, `1.6 MB` | full image |
| Asset (SVG) | `412 bytes` | rendered glyph, then `SVG markup` code block |
| Colour | — | large swatch, then `Saved` / `HEX` / `RGB` / `CMYK` / `HSL` rows |
| Text/OCR | — | text, with `Aa Copy text` in the toolbar and a `Recognized text` block |

---

## 4. Card anatomy

- Preview fills the card: image thumb, colour fill with its hex, text excerpt,
  or SVG glyph.
- Footer: source-app favicon · relative time · **byte size** (`424 bytes`,
  `364 KB`).
- Shortcut badge `⌃⌘0`–`⌃⌘9` on the first ten.
- On hover: **eye** (preview) and **star** (favourite) — top-right.
- Selected: accent border.

## 5. Collections

Chips carry live counts: `History 19` · `Assets 4` · `Colors 6` ·
`Email templates 3` · `+`. These are collections, not tags — `+ New collection`
creates one. "Favorites" is a starred view, separate from collections.

## 6. Visual language

- Flat near-black surfaces (`~#0A0A0A`), not a system material.
- Dark throughout. (Light mode is a known request; not in the reference.)
- Generous corner radii — 18–22 on panels, 10–12 on cards.
- Colour appears only from the content itself (colour clips, thumbnails) plus
  one accent for selection.
- Card sizes are uniform in the strip, masonry in the Library.

---

## 7. Gap against what's built

| Spec | Status |
|---|---|
| Live notch tray + count pill + drag-out stack | **missing** |
| ⌘C keystroke HUD | **missing** |
| Native menu bar menu with History ▸ | missing (SwiftUI window instead) |
| ⌃⌘0–9 actually bound | badges drawn, not registered |
| Library window + sidebar + inspector | **missing** |
| Detail panel (image / SVG / colour / text) | missing (edit sheet instead) |
| Quick Paste popup at cursor | partial — floating panel exists, wrong shape |
| Byte size on cards | missing |
| Eye + star hover actions | wrong icons (pin/trash) |
| Chip counts | missing |
| Colour picker (eyedropper) | **missing** |
| Colour detail (HEX/RGB/CMYK/HSL) | missing |
| `Aa Copy text` for OCR | buried in editor |
| Flat black surfaces | uses system material |
| Notch strip, day grouping, drag/drop | built |
| Capture, OCR, rules, sort, search | built |

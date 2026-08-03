# App icon — design brief

Everything you need to design the icon, and exactly what to hand back.

---

## Pick one of two paths

### Path A — Icon Composer (recommended, macOS 26 native)

`Icon Composer.app` is already installed with your Xcode:

```
/Applications/Xcode.app/Contents/Applications/Icon Composer.app
```

This produces a **`.icon`** file: a layered icon where macOS applies the glass
material, specular highlight, shadow and rounded-rect shape itself. It generates
the Default / Dark / Clear / Tinted appearances from your layers automatically,
so the icon matches the Liquid Glass look the app now uses.

**Rules for this path:**

| | |
|---|---|
| Canvas | 1024 × 1024 |
| Layers | Export each as **SVG** (preferred) or PNG at 1024 |
| Background | Leave it to the system — supply a flat colour or gradient layer, not a rounded rectangle |
| Do **not** draw | The rounded-rect shape, drop shadow, bevel, specular highlight, or glass. macOS adds all of these — drawing your own means they get applied twice |
| Foreground | Keep the mark inside a **~824 × 824 safe area** centred on the canvas |

### Path B — a single flat PNG (simpler, works everywhere)

If you'd rather just design one image, use Apple's classic macOS icon grid.
Here the shape is **not** applied for you, so you draw it:

| | |
|---|---|
| Canvas | 1024 × 1024, transparent |
| Icon body | **824 × 824**, centred — 100px clear on every side |
| Corner radius | **185.4px** on the 824 body, continuous curve (squircle), not a plain circular radius |
| Shadow | Optional, subtle, below the body only — must stay inside the 100px margin |
| Format | PNG with alpha, sRGB, no colour profile weirdness |

Give me the 1024 and I generate all ten sizes from it.

---

## Design constraints that actually matter

**It has to survive 16 × 16.** That's the Finder list and the ⌘-Tab switcher.
Two or three shapes maximum. No thin strokes — anything under ~24px at 1024
scale disappears entirely. No text, ever.

**Check it at 16, 32 and 128** before sending, not just at 1024. Most icons that
look great at full size turn to mush at 16.

**Corners are where cheap icons show.** Use a continuous/squircle curve, not a
circular corner radius — Figma's "Corner smoothing" at 60% is the closest
approximation.

**Where it appears:** Finder, ⌘-Tab, Launchpad, Spotlight, and the Dock if it
were ever a normal app. It is **not** the menu bar icon — that's a separate
monochrome template glyph, currently the SF Symbol `doc.on.clipboard`. If you
want to design that too, it's a different job: single colour, flat, 16 × 16 at
1×, and it gets tinted by the system.

**Current icon, for reference:** dark graphite squircle with a white
clipboard-and-document mark. Nothing about it is precious — it was generated to
have something in the slot.

---

## What to send me

Drop the files anywhere and give me the path. Any of these work:

1. `MyIcon.icon` — from Icon Composer *(best)*
2. `icon-1024.png` — single flat PNG, drawn per Path B
3. An SVG plus a note on the background colour

I'll wire it into the asset catalog, rebuild, install, and confirm it renders at
every size.

---

## Renaming the app — read this before you do it

You mentioned changing the name. Two separate things change, and one of them
can lose your data:

**1. Display name** — what shows in Finder, ⌘-Tab, Spotlight.
Safe. Free. Tell me the name and it's done.

**2. Bundle identifier** — currently `com.sagarmohansingh.supaclip`.
**This one is destructive if handled carelessly.** The database and all saved
screenshots live at:

```
~/Library/Application Support/com.sagarmohansingh.supaclip/
```

Change the bundle ID and the app looks in a *new, empty* folder — your 81 clips
and every saved screenshot appear to vanish. They aren't deleted, but the app
can't see them.

So when you rename, tell me:

- The new **display name**
- Whether to change the **bundle ID** as well
- If yes, whether to **migrate the existing history** across (I'd say yes — it's
  a folder move plus a one-time check, and I'd back it up first)

Renaming is otherwise cheap: the project is generated from `project.yml`, so the
target, scheme, product name and Info.plist all follow from one edit.

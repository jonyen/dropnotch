# DropNotch

> **Archived.** macOS 27 made this app unnecessary. It adds a built-in overflow button that shows menu bar items hidden behind the notch. It also draws the whole menu bar as one window, so the per-item windows DropNotch captured are gone. DropNotch was built for macOS 14 through 26 and is no longer maintained.

Hover over your MacBook's notch to see the menu bar icons hiding behind it — and click them.

## Why

macOS quietly parks overflow menu bar items under and to the left of the notch, where they're invisible and unclickable. There's no built-in way to reach them short of quitting other menu bar apps or buying an external display. DropNotch drops down a translucent panel with live images of those hidden icons; clicking one activates the real status item, and its menu opens exactly as if you'd clicked it in the menu bar.

## Features

- **Instant hover trigger** — move the pointer onto the notch and the panel slides down, styled to match the menu bar (tinted with a sampled menu bar color)
- **Live icon images** — real pixel captures of the hidden items, so battery percentages and dynamic icons stay current; falls back to the owning app's icon when capture isn't possible
- **Click forwarding** — clicks land on the real status item via Accessibility (`AXPress`), with `AXShowMenu` and a synthetic click as fallbacks
- **Tooltips** — hover a panel icon to see the real item's help text
- **Cmd+drag reordering** — reorder icons inside the panel with live reflow; the order persists across launches. Releasing a cmd+drag up in the real menu bar replays a genuine cmd+drag on the underlying item (see [Limitations](#limitations))
- **Stays out of the way** — the panel never steals focus, and when nothing is hidden, no panel appears
- **Its own status item** — Pause, Launch at Login (on by default; toggling it off sticks), and Quit

## Requirements

- macOS 14 (Sonoma) or later
- A notched MacBook for the main event — on other Macs the app idles politely and its status menu says so
- Two permissions, requested on first launch with a guided walkthrough:
  - **Screen Recording** — to capture live images of the hidden icons
  - **Accessibility** — to enumerate status items and forward clicks

## Build & install

```sh
./scripts/make-app.sh
open build/DropNotch.app
```

The build script signs with your Apple Development certificate when one is available — a real identity has a stable designated requirement, so the TCC permission grants survive rebuilds. Without one it falls back to ad-hoc signing, which resets Screen Recording/Accessibility grants on every build.

DropNotch is a background app (`LSUIElement`): no Dock icon, just the status item.

## Usage

1. Launch the app and grant both permissions when prompted.
2. Hover the notch. The panel drops down showing every hidden item.
3. Click an icon to activate it — menus open in the menu bar as usual.
4. Cmd+drag icons within the panel to reorder them.
5. Use DropNotch's own status item to pause it or toggle Launch at Login.

Move the pointer away and the panel slides back up after a short grace period.

### Appearance tweaks

Two environment variables adjust the panel's look, useful when experimenting:

```sh
DROPNOTCH_MATERIAL=hud DROPNOTCH_ALPHA=0.9 ./build/DropNotch.app/Contents/MacOS/DropNotch
```

- `DROPNOTCH_MATERIAL` — `menu` | `popover` | `hud` | `sidebar` | `tooltip` | `selection`
- `DROPNOTCH_ALPHA` — `0.0`–`1.0`

## How it works

- **Detection** — the Accessibility API enumerates each app's status items (authoritative: one entry per real item). Items positioned under or left of the notch, or off-screen, are considered hidden. A `CGWindowList` fallback covers the case where Accessibility isn't granted.
- **Capture** — ScreenCaptureKit single-frame window captures, matched to items by owning app and menu-bar geometry.
- **Click** — `AXPress` on the item's AX element, with a wake-up retry for stale app connections, then `AXShowMenu`, then a synthetic click as last resort.
- **Hover** — a global mouse-move monitor feeds a small state machine (show on notch entry, grace timer on exit) so the panel doesn't flicker.

## Limitations

- **Dragging items out to the menu bar mostly can't work.** macOS destroys the windows of fully hidden status items, so there is nothing on screen to drag. Releasing a cmd+drag in the menu bar replays a real cmd+drag only for items that still have a window. See `docs/superpowers/specs/` for the investigation, including a rejected spacer-based workaround.
- Icon images refresh about once a second while the panel is open; sub-second animations won't be smooth.

## Development

```sh
swift test        # unit tests (hover state machine, geometry, ordering, scanning)
./scripts/make-app.sh
```

- `Sources/DropNotchCore/` — all logic, built as a library so it's testable
- `Sources/DropNotch/` — thin executable entry point
- `docs/smoke-checklist.md` — manual verification checklist
- `docs/superpowers/` — design notes, plans, and rejected-approach write-ups

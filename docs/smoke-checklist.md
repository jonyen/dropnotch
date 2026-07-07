# DropNotch Manual Smoke Checklist

Build & launch: `./scripts/make-app.sh && open build/DropNotch.app`

Note: ad-hoc re-signing on each build can reset TCC grants — if hover or
capture stops working after a rebuild, re-grant both permissions in
System Settings (remove + re-add the app in each pane).

- [ ] First launch shows permissions window; both buttons open the right System Settings pane.
- [ ] After granting both + relaunch: status item (notch symbol) appears with Pause / Launch at Login / Quit.
- [ ] With enough menu bar icons that some are hidden: hovering the notch drops the panel.
- [ ] Panel icons visually match the real menu bar items (live pixels, correct scale).
- [ ] Battery/Wi-Fi-style dynamic icons refresh while the panel stays open (~1s).
- [ ] Moving cursor from notch into panel keeps it open; moving away hides it after ~0.3s; no flicker sweeping across the menu bar.
- [ ] Clicking a panel icon opens that item's real menu; panel hides first; menu keeps focus.
- [ ] With nothing hidden: panel shows "Nothing hidden".
- [ ] Pause in status menu stops hover triggering; unpause restores it.
- [ ] In a fullscreen app (menu bar hidden): hovering top-center does NOT show the panel.
- [ ] Quit works.

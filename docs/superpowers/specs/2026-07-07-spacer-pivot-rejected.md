# Spacer-Based Hiding Pivot — Rejected

**Date:** 2026-07-07
**Status:** Rejected after feasibility spike

## Proposal

Pivot DropNotch to the Ice/Bartender architecture: insert a spacer status
item and own the hiding, so hidden items keep windows — enabling real
capture, clicks, and cmd+drag moves.

## Why rejected

Direct experiment on macOS 26.5 (scratchpad spike, two own status items):

1. **Spacer expansion no longer repositions neighbors.** Expanding a spacer
   item 30→900pt moved the adjacent item zero points. The flow layout the
   spacer trick exploits is gone; overflow items are parked at fixed slots
   left of the notch.
2. **Third-party status item windows are not exposed to CGWindowList** at
   the status layer — even our own item's window (alive in-process) is
   invisible to the window server listing, so ScreenCaptureKit capture and
   synthetic drags on "kept-alive" windows cannot work either.

Ecosystem corroboration: Apple changed the menu bar architecture (items no
longer separate windows); Ice/Bartender/BTT all broke and now rely on
private-API workarounds that are explicitly fragile:

- https://github.com/jordanbaird/Ice/issues/711
- https://community.folivora.ai/t/macos-27-golden-gate-menu-bar-management-broken-solutions-ice-thaw-bartender-barbee-etc/47232

## Decision

Keep the current AX-based architecture (reveal, template glyphs, click
forwarding — all supported APIs). Icon-moving stays out of scope until
Apple ships a public menu bar layout API or a stable community technique
emerges.

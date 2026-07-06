# DropNotch — Design Spec

**Date:** 2026-07-06
**Status:** Approved

## Purpose

macOS menu bar utility. Hovering the cursor over the notch drops down a panel showing live images of menu bar icons that macOS has hidden (occluded by the notch or pushed off-screen by overflow). Clicking an icon in the panel activates the real status item as if clicked in the menu bar.

## Decisions Made

- **Dropdown UI:** live pixel-accurate icon images captured via ScreenCaptureKit (not bundle-icon list, not item repositioning).
- **Trigger:** instant on hover-enter of notch rect; auto-hide when cursor leaves notch+panel union, with ~0.3s grace delay to prevent flicker.
- **Scope:** all overflow items — anything macOS can't fit in the menu bar, whether behind the notch or pushed off-screen.
- **Mechanism (Approach A):** CGWindowList detection + ScreenCaptureKit capture + Accessibility (AXPress) click forwarding.

## App Shape

- Swift, SwiftUI/AppKit hybrid. Xcode project, macOS 14+ target (dev machine: macOS 26).
- `LSUIElement = true` background agent, no Dock icon.
- Own status item with menu: Pause, Launch at Login, Quit.
- Not sandboxed (Screen Recording + Accessibility require it). No App Store distribution.

## Components

Each component is protocol-fronted so logic can be unit-tested with injected fakes.

### 1. HoverMonitor
- Global `NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved)` (event-driven, no polling).
- Computes notch rect on the built-in display from `NSScreen.safeAreaInsets` / the gap between `auxiliaryTopLeftArea` and `auxiliaryTopRightArea`.
- Cursor enters notch rect → emit `show`. Cursor exits union(notch rect, panel frame) for >0.3s → emit `hide`.
- Disabled when the menu bar is hidden (fullscreen apps).

### 2. StatusItemScanner
- `CGWindowListCopyWindowInfo` filtered to menu-bar-level windows (`kCGStatusWindowLevel` layer), excluding own PID and the system menu bar window itself.
- Per window: owner PID, owner name, frame.
- **Hidden** = frame intersects notch rect, OR frame is off-screen, OR frame.x < 0.
- System items (Control Center, Clock, Siri / owner `Control Center`, `SystemUIServer`) excluded while visible; included if genuinely occluded.
- Secondary source: Accessibility — each running app's `kAXExtrasMenuBarAttribute` children. Union of both sources covers status items whose windows aren't enumerable when hidden.
- Rescan on panel show and every 1s while panel is open.

### 3. IconCapturer
- ScreenCaptureKit, `SCContentFilter(desktopIndependentWindow:)` per hidden item window.
- Single-frame grabs via `SCScreenshotManager` (not streams). Refresh ~1s while panel open, so dynamic icons (battery %, wifi) stay near-live.
- Retina scale respected.
- Per-icon capture failure → fall back to owning app's bundle icon. AX-only items (no window) always use bundle icon.

### 4. NotchPanel
- Borderless non-activating `NSPanel` (`.nonactivatingPanel`), level just above `.statusBar`, never becomes key.
- Dark rounded rect hanging directly below the notch — visually an extension of the notch.
- Horizontal row of icon images at native menu bar size (24pt height), hover highlight per icon.
- Empty state: "nothing hidden" label.

### 5. ClickForwarder
- On icon click: hide panel immediately, then resolve owning app via PID → `AXUIElementCreateApplication` → `kAXExtrasMenuBarAttribute` → children → match by position/title → `AXPress`.
- The item's real menu opens at a macOS-chosen valid on-screen position; non-activating panel never steals key/focus from it.
- Fallback if AXPress fails: synthetic `CGEvent` mouse click at the item window's center.

## Data Flow

hover enter → scanner builds hidden list → capturer grabs images → panel renders → user clicks icon → forwarder AXPresses → panel hides.

## Permissions

- First launch: check `CGPreflightScreenCaptureAccess()` and `AXIsProcessTrusted()`.
- If missing: onboarding window with buttons deep-linking to the relevant System Settings panes.
- App idles safely until granted; re-checks on activation.

## Edge Cases

| Case | Behavior |
|---|---|
| No notch (external-only / older Mac) | App idles; status item reads "No notch on this display." Overflow-without-notch support deferred (YAGNI). |
| Hidden item window not enumerable | AX source unions it in; renders with bundle icon. |
| Fullscreen app (menu bar hidden) | HoverMonitor disabled. |
| Multiple displays | Notch logic pinned to built-in screen only. |
| Panel flicker crossing menu bar | 0.3s grace delay before hide. |

## Error Handling

- Capture failure per icon → bundle-icon fallback, never blank.
- Scanner failure → empty panel with label.
- All failures logged via `os_log`; no user-facing error dialogs in normal use.

## Testing

- **Unit (XCTest):** notch rect math, hidden-detection given fake window frames, scanner filtering/exclusion rules, hover enter/exit state machine with grace delay. Scanner and capturer protocol-wrapped; tests inject fakes.
- **Manual smoke checklist (in repo):** hover shows panel; icons visually match real items; click opens correct item's menu; no flicker on grace path; fullscreen does not trigger; permissions onboarding flow.

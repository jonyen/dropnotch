# DropNotch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** macOS background agent: hovering over the notch drops a panel showing live images of menu bar icons macOS hid (notch-occluded or overflow), clickable to activate the real item.

**Architecture:** SwiftPM package with a `DropNotchCore` library (all logic, unit-testable) and a thin `DropNotch` executable. Pure logic (geometry, hover state machine, hidden-item filtering) is separated from AppKit/ScreenCaptureKit/Accessibility adapters behind protocols. A `make-app.sh` script assembles a `.app` bundle (needed for TCC permissions).

**Tech Stack:** Swift 5.9+, SwiftPM, AppKit + SwiftUI (panel content), ScreenCaptureKit (`SCScreenshotManager`, macOS 14+), CoreGraphics (`CGWindowListCopyWindowInfo`), ApplicationServices (AX), XCTest.

## Global Constraints

- Target macOS 14+ (`platforms: [.macOS(.v14)]`, `LSMinimumSystemVersion` 14.0).
- Bundle ID `com.jyen.DropNotch`, `LSUIElement = true`, not sandboxed, ad-hoc codesigned.
- All internal geometry uses **Cocoa coordinates** (global, bottom-left origin). CG-coordinate data (CGWindowList, CGEvent, AX positions) is converted at adapter boundaries using main-display height.
- Grace delay before panel hide: **0.3s**. Rescan/recapture interval while panel open: **1s**.
- Icon row height in panel: **24pt**.
- No user-facing error dialogs during normal use; failures log via `os_log` (subsystem `com.jyen.DropNotch`).
- Panel must be non-activating (`.nonactivatingPanel`, `canBecomeKey == false`) — it must never steal focus from the menu the clicked item opens.

## File Structure

```
Package.swift
Resources/Info.plist
scripts/make-app.sh
Sources/DropNotch/main.swift                     — executable entry, 5 lines
Sources/DropNotchCore/
  Version.swift                                  — version constant
  MenuBarItemInfo.swift                          — model for a status item window
  NotchGeometry.swift                            — pure: notch rect math, coord conversion
  HoverStateMachine.swift                        — pure: show/hide state machine w/ grace
  StatusItemScanner.swift                        — pure: hidden-item filter rules
  WindowListProvider.swift                       — adapter: CGWindowList → [MenuBarItemInfo]
  AXItemSource.swift                             — adapter: AX extras-menu-bar secondary source
  IconCapturer.swift                             — adapter: SCK per-window screenshot + bundle-icon fallback
  NotchPanelController.swift                     — NSPanel + SwiftUI content view
  ClickForwarder.swift                           — AXPress + CGEvent fallback
  Permissions.swift                              — TCC checks + onboarding window
  StatusMenuController.swift                     — own status item (Pause / Launch at Login / Quit)
  AppCoordinator.swift                           — wires monitors, timers, scan→capture→panel→click
  AppDelegate.swift                              — app lifecycle, permission gate
Tests/DropNotchTests/
  NotchGeometryTests.swift
  HoverStateMachineTests.swift
  StatusItemScannerTests.swift
docs/smoke-checklist.md
```

---

### Task 1: Package scaffold + app bundle script

**Files:**
- Create: `Package.swift`
- Create: `Sources/DropNotchCore/Version.swift`
- Create: `Sources/DropNotch/main.swift`
- Create: `Resources/Info.plist`
- Create: `scripts/make-app.sh`
- Create: `.gitignore`
- Test: `Tests/DropNotchTests/SmokeTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `DropNotchCore` library module all later tasks add files to; `DropNotchCore.AppDelegate` placeholder replaced in Task 9; `scripts/make-app.sh` producing `build/DropNotch.app`.

- [ ] **Step 1: Create package files**

`Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DropNotch",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DropNotchCore", path: "Sources/DropNotchCore"),
        .executableTarget(
            name: "DropNotch",
            dependencies: ["DropNotchCore"],
            path: "Sources/DropNotch"
        ),
        .testTarget(
            name: "DropNotchTests",
            dependencies: ["DropNotchCore"],
            path: "Tests/DropNotchTests"
        ),
    ]
)
```

`Sources/DropNotchCore/Version.swift`:

```swift
public enum DropNotchInfo {
    public static let version = "0.1.0"
    public static let logSubsystem = "com.jyen.DropNotch"
}
```

`Sources/DropNotch/main.swift` (placeholder until Task 9 adds AppDelegate; keep it compiling standalone):

```swift
import AppKit
import DropNotchCore

print("DropNotch \(DropNotchInfo.version)")
```

`Tests/DropNotchTests/SmokeTests.swift`:

```swift
import XCTest
@testable import DropNotchCore

final class SmokeTests: XCTestCase {
    func testVersionNotEmpty() {
        XCTAssertFalse(DropNotchInfo.version.isEmpty)
    }
}
```

`.gitignore`:

```
.build/
build/
.DS_Store
```

`Resources/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>DropNotch</string>
	<key>CFBundleIdentifier</key>
	<string>com.jyen.DropNotch</string>
	<key>CFBundleName</key>
	<string>DropNotch</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
```

`scripts/make-app.sh`:

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=build/DropNotch.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/DropNotch "$APP/Contents/MacOS/DropNotch"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"
```

- [ ] **Step 2: Make script executable, build, test**

Run: `chmod +x scripts/make-app.sh && swift build && swift test`
Expected: `Build complete!` and `Test Suite 'All tests' passed` (1 test).

- [ ] **Step 3: Verify bundle script**

Run: `./scripts/make-app.sh && ls build/DropNotch.app/Contents/MacOS`
Expected: prints `Built build/DropNotch.app`; listing shows `DropNotch`.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: SwiftPM scaffold with app bundle script"
```

---

### Task 2: NotchGeometry (pure)

**Files:**
- Create: `Sources/DropNotchCore/NotchGeometry.swift`
- Test: `Tests/DropNotchTests/NotchGeometryTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `NotchGeometry.notchRect(screenFrame: CGRect, auxLeft: CGRect?, auxRight: CGRect?) -> CGRect?` — notch rect in Cocoa coords, nil when no notch.
  - `NotchGeometry.cocoaRect(fromCGRect: CGRect, mainDisplayHeight: CGFloat) -> CGRect` — CG (top-left) → Cocoa (bottom-left).
  - `NotchGeometry.cgPoint(fromCocoaPoint: CGPoint, mainDisplayHeight: CGFloat) -> CGPoint` — inverse, for CGEvent/AX.

- [ ] **Step 1: Write failing tests**

`Tests/DropNotchTests/NotchGeometryTests.swift`:

```swift
import XCTest
@testable import DropNotchCore

final class NotchGeometryTests: XCTestCase {
    // 3456x2234 screen, menu bar/aux height 38, notch from x=1528 to x=1928
    let screen = CGRect(x: 0, y: 0, width: 3456, height: 2234)
    let auxLeft = CGRect(x: 0, y: 2196, width: 1528, height: 38)
    let auxRight = CGRect(x: 1928, y: 2196, width: 1528, height: 38)

    func testNotchRectBetweenAuxAreas() {
        let notch = NotchGeometry.notchRect(screenFrame: screen, auxLeft: auxLeft, auxRight: auxRight)
        XCTAssertEqual(notch, CGRect(x: 1528, y: 2196, width: 400, height: 38))
    }

    func testNotchRectNilWithoutAuxAreas() {
        XCTAssertNil(NotchGeometry.notchRect(screenFrame: screen, auxLeft: nil, auxRight: nil))
        XCTAssertNil(NotchGeometry.notchRect(screenFrame: screen, auxLeft: auxLeft, auxRight: nil))
    }

    func testNotchRectNilWhenAreasTouch() {
        // no gap => no notch
        let right = CGRect(x: 1528, y: 2196, width: 1928, height: 38)
        XCTAssertNil(NotchGeometry.notchRect(screenFrame: screen, auxLeft: auxLeft, auxRight: right))
    }

    func testCocoaRectConversion() {
        // CG rect at top of a 2234-high main display
        let cg = CGRect(x: 100, y: 0, width: 40, height: 38)
        let cocoa = NotchGeometry.cocoaRect(fromCGRect: cg, mainDisplayHeight: 2234)
        XCTAssertEqual(cocoa, CGRect(x: 100, y: 2196, width: 40, height: 38))
    }

    func testCGPointConversion() {
        let p = NotchGeometry.cgPoint(fromCocoaPoint: CGPoint(x: 100, y: 2196), mainDisplayHeight: 2234)
        XCTAssertEqual(p, CGPoint(x: 100, y: 38))
    }
}
```

- [ ] **Step 2: Run tests, verify failure**

Run: `swift test --filter NotchGeometryTests`
Expected: compile error `cannot find 'NotchGeometry'`.

- [ ] **Step 3: Implement**

`Sources/DropNotchCore/NotchGeometry.swift`:

```swift
import CoreGraphics

/// Pure geometry. All rects Cocoa coordinates (global, bottom-left origin)
/// unless a name says otherwise.
public enum NotchGeometry {
    /// Notch rect = horizontal gap between the two auxiliary top areas.
    /// Returns nil when the screen has no notch.
    public static func notchRect(screenFrame: CGRect, auxLeft: CGRect?, auxRight: CGRect?) -> CGRect? {
        guard let left = auxLeft, let right = auxRight else { return nil }
        let width = right.minX - left.maxX
        guard width > 0 else { return nil }
        return CGRect(x: left.maxX, y: left.minY, width: width, height: left.height)
    }

    /// CGWindowList/CGEvent use top-left-origin global coords; Cocoa uses
    /// bottom-left. Both are anchored to the main display.
    public static func cocoaRect(fromCGRect r: CGRect, mainDisplayHeight: CGFloat) -> CGRect {
        CGRect(x: r.origin.x,
               y: mainDisplayHeight - r.origin.y - r.height,
               width: r.width,
               height: r.height)
    }

    public static func cgPoint(fromCocoaPoint p: CGPoint, mainDisplayHeight: CGFloat) -> CGPoint {
        CGPoint(x: p.x, y: mainDisplayHeight - p.y)
    }
}
```

- [ ] **Step 4: Run tests, verify pass**

Run: `swift test --filter NotchGeometryTests`
Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/DropNotchCore/NotchGeometry.swift Tests/DropNotchTests/NotchGeometryTests.swift
git commit -m "feat: notch rect math and coordinate conversion"
```

---

### Task 3: HoverStateMachine (pure)

**Files:**
- Create: `Sources/DropNotchCore/HoverStateMachine.swift`
- Test: `Tests/DropNotchTests/HoverStateMachineTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum HoverAction: Equatable { case none, show, hide }`
  - `final class HoverStateMachine` with:
    - `init(graceInterval: TimeInterval = 0.3)`
    - `func mouseMoved(to point: CGPoint, notch: CGRect, panel: CGRect?, now: Date) -> HoverAction`
    - `func tick(now: Date) -> HoverAction` (call from a timer while not idle)
    - `var isIdle: Bool`

- [ ] **Step 1: Write failing tests**

`Tests/DropNotchTests/HoverStateMachineTests.swift`:

```swift
import XCTest
@testable import DropNotchCore

final class HoverStateMachineTests: XCTestCase {
    let notch = CGRect(x: 1528, y: 2196, width: 400, height: 38)
    let panel = CGRect(x: 1500, y: 2100, width: 456, height: 96)
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func makeSM() -> HoverStateMachine { HoverStateMachine(graceInterval: 0.3) }

    func testEnterNotchShows() {
        let sm = makeSM()
        let action = sm.mouseMoved(to: CGPoint(x: 1600, y: 2210), notch: notch, panel: nil, now: t0)
        XCTAssertEqual(action, .show)
        XCTAssertFalse(sm.isIdle)
    }

    func testOutsideWhileIdleDoesNothing() {
        let sm = makeSM()
        XCTAssertEqual(sm.mouseMoved(to: CGPoint(x: 10, y: 10), notch: notch, panel: nil, now: t0), .none)
        XCTAssertTrue(sm.isIdle)
    }

    func testMovingIntoPanelKeepsShowing() {
        let sm = makeSM()
        _ = sm.mouseMoved(to: CGPoint(x: 1600, y: 2210), notch: notch, panel: nil, now: t0)
        let action = sm.mouseMoved(to: CGPoint(x: 1600, y: 2150), notch: notch, panel: panel, now: t0)
        XCTAssertEqual(action, .none)
        XCTAssertFalse(sm.isIdle)
    }

    func testLeaveThenGraceExpiryHides() {
        let sm = makeSM()
        _ = sm.mouseMoved(to: CGPoint(x: 1600, y: 2210), notch: notch, panel: panel, now: t0)
        // leave both rects
        XCTAssertEqual(sm.mouseMoved(to: CGPoint(x: 10, y: 10), notch: notch, panel: panel, now: t0), .none)
        // tick before grace expiry: nothing
        XCTAssertEqual(sm.tick(now: t0.addingTimeInterval(0.1)), .none)
        // tick after expiry: hide
        XCTAssertEqual(sm.tick(now: t0.addingTimeInterval(0.35)), .hide)
        XCTAssertTrue(sm.isIdle)
    }

    func testReenterDuringGraceCancelsHide() {
        let sm = makeSM()
        _ = sm.mouseMoved(to: CGPoint(x: 1600, y: 2210), notch: notch, panel: panel, now: t0)
        _ = sm.mouseMoved(to: CGPoint(x: 10, y: 10), notch: notch, panel: panel, now: t0)
        // back inside panel during grace
        XCTAssertEqual(sm.mouseMoved(to: CGPoint(x: 1600, y: 2150), notch: notch, panel: panel, now: t0.addingTimeInterval(0.2)), .none)
        // grace should be cancelled: much later tick does nothing
        XCTAssertEqual(sm.tick(now: t0.addingTimeInterval(5)), .none)
        XCTAssertFalse(sm.isIdle)
    }

    func testMouseMoveAfterGraceExpiryHides() {
        // hide can also be delivered by a mouse move, not only tick
        let sm = makeSM()
        _ = sm.mouseMoved(to: CGPoint(x: 1600, y: 2210), notch: notch, panel: panel, now: t0)
        _ = sm.mouseMoved(to: CGPoint(x: 10, y: 10), notch: notch, panel: panel, now: t0)
        let action = sm.mouseMoved(to: CGPoint(x: 12, y: 10), notch: notch, panel: panel, now: t0.addingTimeInterval(0.4))
        XCTAssertEqual(action, .hide)
        XCTAssertTrue(sm.isIdle)
    }
}
```

- [ ] **Step 2: Run tests, verify failure**

Run: `swift test --filter HoverStateMachineTests`
Expected: compile error `cannot find 'HoverStateMachine'`.

- [ ] **Step 3: Implement**

`Sources/DropNotchCore/HoverStateMachine.swift`:

```swift
import Foundation

public enum HoverAction: Equatable {
    case none, show, hide
}

/// Pure show/hide state machine. Caller feeds mouse positions and clock
/// ticks; machine answers with the action to take. No timers, no AppKit.
public final class HoverStateMachine {
    private enum State {
        case idle
        case showing
        case grace(since: Date)
    }

    private var state: State = .idle
    private let graceInterval: TimeInterval

    public init(graceInterval: TimeInterval = 0.3) {
        self.graceInterval = graceInterval
    }

    public var isIdle: Bool {
        if case .idle = state { return true }
        return false
    }

    public func mouseMoved(to point: CGPoint, notch: CGRect, panel: CGRect?, now: Date) -> HoverAction {
        let insideNotch = notch.contains(point)
        let insidePanel = panel?.contains(point) ?? false

        switch state {
        case .idle:
            if insideNotch {
                state = .showing
                return .show
            }
            return .none

        case .showing:
            if !(insideNotch || insidePanel) {
                state = .grace(since: now)
            }
            return .none

        case .grace(let since):
            if insideNotch || insidePanel {
                state = .showing
                return .none
            }
            if now.timeIntervalSince(since) >= graceInterval {
                state = .idle
                return .hide
            }
            return .none
        }
    }

    public func tick(now: Date) -> HoverAction {
        if case .grace(let since) = state, now.timeIntervalSince(since) >= graceInterval {
            state = .idle
            return .hide
        }
        return .none
    }
}
```

- [ ] **Step 4: Run tests, verify pass**

Run: `swift test --filter HoverStateMachineTests`
Expected: 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/DropNotchCore/HoverStateMachine.swift Tests/DropNotchTests/HoverStateMachineTests.swift
git commit -m "feat: hover state machine with grace delay"
```

---

### Task 4: MenuBarItemInfo model + StatusItemScanner filter (pure)

**Files:**
- Create: `Sources/DropNotchCore/MenuBarItemInfo.swift`
- Create: `Sources/DropNotchCore/StatusItemScanner.swift`
- Test: `Tests/DropNotchTests/StatusItemScannerTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct MenuBarItemInfo: Equatable, Hashable { let windowID: UInt32?; let ownerPID: pid_t; let ownerName: String; let frame: CGRect; let title: String? }` (frame in Cocoa coords; `windowID` nil for AX-sourced items) with memberwise `public init`.
  - `StatusItemScanner.hiddenItems(windows: [MenuBarItemInfo], notch: CGRect?, screenFrame: CGRect, ownPID: pid_t) -> [MenuBarItemInfo]` — sorted left-to-right.
  - `StatusItemScanner.excludedOwners: Set<String>`

- [ ] **Step 1: Write failing tests**

`Tests/DropNotchTests/StatusItemScannerTests.swift`:

```swift
import XCTest
@testable import DropNotchCore

final class StatusItemScannerTests: XCTestCase {
    let screen = CGRect(x: 0, y: 0, width: 3456, height: 2234)
    let notch = CGRect(x: 1528, y: 2196, width: 400, height: 38)
    let ownPID: pid_t = 999

    func item(_ name: String, x: CGFloat, width: CGFloat = 40, pid: pid_t = 100) -> MenuBarItemInfo {
        MenuBarItemInfo(windowID: 1, ownerPID: pid, ownerName: name,
                        frame: CGRect(x: x, y: 2196, width: width, height: 38), title: nil)
    }

    func testVisibleItemNotHidden() {
        let items = StatusItemScanner.hiddenItems(
            windows: [item("Dropbox", x: 2000)], notch: notch, screenFrame: screen, ownPID: ownPID)
        XCTAssertTrue(items.isEmpty)
    }

    func testItemUnderNotchIsHidden() {
        let hidden = item("Docker", x: 1600)
        let items = StatusItemScanner.hiddenItems(
            windows: [hidden], notch: notch, screenFrame: screen, ownPID: ownPID)
        XCTAssertEqual(items, [hidden])
    }

    func testItemPartiallyUnderNotchIsHidden() {
        let hidden = item("Docker", x: 1500) // 1500-1540 overlaps notch start 1528
        let items = StatusItemScanner.hiddenItems(
            windows: [hidden], notch: notch, screenFrame: screen, ownPID: ownPID)
        XCTAssertEqual(items, [hidden])
    }

    func testOffscreenLeftIsHidden() {
        let hidden = item("Overflow", x: -40)
        let items = StatusItemScanner.hiddenItems(
            windows: [hidden], notch: notch, screenFrame: screen, ownPID: ownPID)
        XCTAssertEqual(items, [hidden])
    }

    func testOffscreenRightIsHidden() {
        let hidden = item("Overflow", x: 3440) // extends past 3456
        let items = StatusItemScanner.hiddenItems(
            windows: [hidden], notch: notch, screenFrame: screen, ownPID: ownPID)
        XCTAssertEqual(items, [hidden])
    }

    func testOwnItemsExcluded() {
        let mine = item("DropNotch", x: 1600, pid: 999)
        let items = StatusItemScanner.hiddenItems(
            windows: [mine], notch: notch, screenFrame: screen, ownPID: ownPID)
        XCTAssertTrue(items.isEmpty)
    }

    func testWindowServerExcluded() {
        let ws = item("Window Server", x: 1600)
        let items = StatusItemScanner.hiddenItems(
            windows: [ws], notch: notch, screenFrame: screen, ownPID: ownPID)
        XCTAssertTrue(items.isEmpty)
    }

    func testNilNotchStillCatchesOffscreen() {
        let hidden = item("Overflow", x: -40)
        let visible = item("Dropbox", x: 2000)
        let items = StatusItemScanner.hiddenItems(
            windows: [visible, hidden], notch: nil, screenFrame: screen, ownPID: ownPID)
        XCTAssertEqual(items, [hidden])
    }

    func testSortedLeftToRight() {
        let a = item("B", x: 1700)
        let b = item("A", x: 1550)
        let items = StatusItemScanner.hiddenItems(
            windows: [a, b], notch: notch, screenFrame: screen, ownPID: ownPID)
        XCTAssertEqual(items.map(\.ownerName), ["A", "B"])
    }
}
```

- [ ] **Step 2: Run tests, verify failure**

Run: `swift test --filter StatusItemScannerTests`
Expected: compile error `cannot find 'MenuBarItemInfo'`.

- [ ] **Step 3: Implement**

`Sources/DropNotchCore/MenuBarItemInfo.swift`:

```swift
import CoreGraphics

/// One status-item window in the menu bar. `frame` is Cocoa coordinates.
/// `windowID` is nil for items discovered only via Accessibility.
public struct MenuBarItemInfo: Equatable, Hashable {
    public let windowID: UInt32?
    public let ownerPID: pid_t
    public let ownerName: String
    public let frame: CGRect
    public let title: String?

    public init(windowID: UInt32?, ownerPID: pid_t, ownerName: String, frame: CGRect, title: String?) {
        self.windowID = windowID
        self.ownerPID = ownerPID
        self.ownerName = ownerName
        self.frame = frame
        self.title = title
    }
}
```

`Sources/DropNotchCore/StatusItemScanner.swift`:

```swift
import CoreGraphics

/// Pure filter: which menu bar items can the user not see?
public enum StatusItemScanner {
    /// Owners that are menu bar chrome, not clickable status items.
    public static let excludedOwners: Set<String> = ["Window Server"]

    public static func hiddenItems(
        windows: [MenuBarItemInfo],
        notch: CGRect?,
        screenFrame: CGRect,
        ownPID: pid_t
    ) -> [MenuBarItemInfo] {
        windows
            .filter { $0.ownerPID != ownPID }
            .filter { !excludedOwners.contains($0.ownerName) }
            .filter { isHidden($0.frame, notch: notch, screenFrame: screenFrame) }
            .sorted { $0.frame.minX < $1.frame.minX }
    }

    private static func isHidden(_ frame: CGRect, notch: CGRect?, screenFrame: CGRect) -> Bool {
        if let notch, frame.intersects(notch) { return true }
        if frame.minX < screenFrame.minX { return true }
        if frame.maxX > screenFrame.maxX { return true }
        return false
    }
}
```

- [ ] **Step 4: Run tests, verify pass**

Run: `swift test`
Expected: all tests pass (smoke + geometry + hover + 9 scanner tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/DropNotchCore/MenuBarItemInfo.swift Sources/DropNotchCore/StatusItemScanner.swift Tests/DropNotchTests/StatusItemScannerTests.swift
git commit -m "feat: menu bar item model and hidden-item filter"
```

---

### Task 5: Live adapters — WindowListProvider + AXItemSource

**Files:**
- Create: `Sources/DropNotchCore/WindowListProvider.swift`
- Create: `Sources/DropNotchCore/AXItemSource.swift`

**Interfaces:**
- Consumes: `MenuBarItemInfo`, `NotchGeometry.cocoaRect(fromCGRect:mainDisplayHeight:)`.
- Produces:
  - `protocol WindowListProviding { func menuBarItemWindows() -> [MenuBarItemInfo]; func isMenuBarVisible() -> Bool }`
  - `final class CGWindowListProvider: WindowListProviding`
  - `final class AXItemSource` with `func items() -> [MenuBarItemInfo]` (windowID nil) and `func pressItem(pid: pid_t, nearCocoaX: CGFloat, mainDisplayHeight: CGFloat) -> Bool` (also used by Task 8's ClickForwarder).

These are thin OS adapters — no unit tests; verified by build here and by the smoke checklist in Task 9.

- [ ] **Step 1: Implement WindowListProvider**

`Sources/DropNotchCore/WindowListProvider.swift`:

```swift
import AppKit
import CoreGraphics

public protocol WindowListProviding {
    /// All windows sitting at the menu bar's status level, frames in Cocoa coords.
    func menuBarItemWindows() -> [MenuBarItemInfo]
    /// False while a fullscreen app hides the menu bar.
    func isMenuBarVisible() -> Bool
}

public final class CGWindowListProvider: WindowListProviding {
    public init() {}

    private var mainDisplayHeight: CGFloat {
        CGDisplayBounds(CGMainDisplayID()).height
    }

    public func menuBarItemWindows() -> [MenuBarItemInfo] {
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        guard let list = CGWindowListCopyWindowInfo(
            [.optionAll], kCGNullWindowID) as? [[String: Any]] else { return [] }
        let height = mainDisplayHeight

        return list.compactMap { info in
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == statusLevel,
                  let windowID = info[kCGWindowNumber as String] as? UInt32,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat]
            else { return nil }
            let cgFrame = CGRect(x: boundsDict["X"] ?? 0, y: boundsDict["Y"] ?? 0,
                                 width: boundsDict["Width"] ?? 0, height: boundsDict["Height"] ?? 0)
            return MenuBarItemInfo(
                windowID: windowID,
                ownerPID: pid,
                ownerName: info[kCGWindowOwnerName as String] as? String ?? "?",
                frame: NotchGeometry.cocoaRect(fromCGRect: cgFrame, mainDisplayHeight: height),
                title: info[kCGWindowName as String] as? String)
        }
    }

    public func isMenuBarVisible() -> Bool {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return true }
        return list.contains { info in
            (info[kCGWindowOwnerName as String] as? String) == "Window Server"
                && (info[kCGWindowName as String] as? String) == "Menubar"
        }
    }
}
```

- [ ] **Step 2: Implement AXItemSource**

`Sources/DropNotchCore/AXItemSource.swift`:

```swift
import AppKit
import ApplicationServices

/// Secondary discovery + click path via the Accessibility API.
/// Enumerates each running app's "extras menu bar" (its status items).
public final class AXItemSource {
    public init() {}

    /// Status items discoverable via AX, frames in Cocoa coords, windowID nil.
    public func items() -> [MenuBarItemInfo] {
        let height = CGDisplayBounds(CGMainDisplayID()).height
        var result: [MenuBarItemInfo] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy != .prohibited || app.bundleIdentifier != nil {
            let pid = app.processIdentifier
            guard pid > 0 else { continue }
            for element in extrasChildren(pid: pid) {
                guard let cgFrame = frame(of: element) else { continue }
                result.append(MenuBarItemInfo(
                    windowID: nil,
                    ownerPID: pid,
                    ownerName: app.localizedName ?? "?",
                    frame: NotchGeometry.cocoaRect(fromCGRect: cgFrame, mainDisplayHeight: height),
                    title: title(of: element)))
            }
        }
        return result
    }

    /// AXPress the status item of `pid` whose x-center is closest to `nearCocoaX`.
    public func pressItem(pid: pid_t, nearCocoaX: CGFloat, mainDisplayHeight: CGFloat) -> Bool {
        let children = extrasChildren(pid: pid)
        guard !children.isEmpty else { return false }
        let target: AXUIElement
        if children.count == 1 {
            target = children[0]
        } else {
            target = children.min { a, b in
                distance(of: a, toCocoaX: nearCocoaX, mainDisplayHeight: mainDisplayHeight)
                    < distance(of: b, toCocoaX: nearCocoaX, mainDisplayHeight: mainDisplayHeight)
            } ?? children[0]
        }
        return AXUIElementPerformAction(target, kAXPressAction as CFString) == .success
    }

    // MARK: - AX plumbing

    private func extrasChildren(pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        var extrasRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &extrasRef) == .success,
              let extras = extrasRef, CFGetTypeID(extras) == AXUIElementGetTypeID()
        else { return [] }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(extras as! AXUIElement, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement]
        else { return [] }
        return children
    }

    /// Frame in CG (top-left) coords.
    private func frame(of element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success
        else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: point, size: size)
    }

    private func title(of element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &ref) == .success else { return nil }
        return ref as? String
    }

    private func distance(of element: AXUIElement, toCocoaX x: CGFloat, mainDisplayHeight: CGFloat) -> CGFloat {
        guard let cgFrame = frame(of: element) else { return .greatestFiniteMagnitude }
        let cocoa = NotchGeometry.cocoaRect(fromCGRect: cgFrame, mainDisplayHeight: mainDisplayHeight)
        return abs(cocoa.midX - x)
    }
}
```

- [ ] **Step 3: Build**

Run: `swift build && swift test`
Expected: build succeeds, all existing tests still pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/DropNotchCore/WindowListProvider.swift Sources/DropNotchCore/AXItemSource.swift
git commit -m "feat: CGWindowList and Accessibility adapters"
```

---

### Task 6: IconCapturer + Permissions

**Files:**
- Create: `Sources/DropNotchCore/IconCapturer.swift`
- Create: `Sources/DropNotchCore/Permissions.swift`

**Interfaces:**
- Consumes: `MenuBarItemInfo`.
- Produces:
  - `protocol IconCapturing { func captureIcon(for item: MenuBarItemInfo) async -> NSImage }` — never fails; falls back to owner app's bundle icon, then a generic symbol.
  - `final class SCKIconCapturer: IconCapturing`
  - `enum Permissions { static var screenRecordingGranted: Bool; static var accessibilityGranted: Bool; static var allGranted: Bool; static func requestScreenRecording(); static func promptAccessibility(); static func openScreenRecordingSettings(); static func openAccessibilitySettings() }`

- [ ] **Step 1: Implement IconCapturer**

`Sources/DropNotchCore/IconCapturer.swift`:

```swift
import AppKit
import ScreenCaptureKit
import os.log

public protocol IconCapturing {
    /// Live pixels of the item's window; bundle icon if capture impossible.
    func captureIcon(for item: MenuBarItemInfo) async -> NSImage
}

public final class SCKIconCapturer: IconCapturing {
    private let log = Logger(subsystem: DropNotchInfo.logSubsystem, category: "capture")

    public init() {}

    public func captureIcon(for item: MenuBarItemInfo) async -> NSImage {
        if let windowID = item.windowID, let image = await captureWindow(windowID: windowID) {
            return image
        }
        return fallbackIcon(for: item)
    }

    private func captureWindow(windowID: UInt32) async -> NSImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                log.info("window \(windowID) not in shareable content")
                return nil
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            let scale: CGFloat = 2 // capture at retina scale
            config.width = max(1, Int(window.frame.width * scale))
            config.height = max(1, Int(window.frame.height * scale))
            config.showsCursor = false
            let cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config)
            return NSImage(cgImage: cgImage,
                           size: NSSize(width: window.frame.width, height: window.frame.height))
        } catch {
            log.error("capture failed for window \(windowID): \(error.localizedDescription)")
            return nil
        }
    }

    private func fallbackIcon(for item: MenuBarItemInfo) -> NSImage {
        if let app = NSRunningApplication(processIdentifier: item.ownerPID), let icon = app.icon {
            return icon
        }
        return NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: item.ownerName)
            ?? NSImage()
    }
}
```

- [ ] **Step 2: Implement Permissions**

`Sources/DropNotchCore/Permissions.swift`:

```swift
import AppKit
import ApplicationServices
import CoreGraphics

public enum Permissions {
    public static var screenRecordingGranted: Bool { CGPreflightScreenCaptureAccess() }
    public static var accessibilityGranted: Bool { AXIsProcessTrusted() }
    public static var allGranted: Bool { screenRecordingGranted && accessibilityGranted }

    public static func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
    }

    public static func promptAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    public static func openScreenRecordingSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    public static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private static func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
```

- [ ] **Step 3: Build**

Run: `swift build && swift test`
Expected: build succeeds, tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/DropNotchCore/IconCapturer.swift Sources/DropNotchCore/Permissions.swift
git commit -m "feat: ScreenCaptureKit icon capture and permission checks"
```

---

### Task 7: NotchPanelController (panel UI)

**Files:**
- Create: `Sources/DropNotchCore/NotchPanelController.swift`

**Interfaces:**
- Consumes: `MenuBarItemInfo`.
- Produces:
  - `struct PanelItem: Identifiable { let id: Int; let info: MenuBarItemInfo; let image: NSImage }`
  - `@MainActor final class NotchPanelController` with:
    - `init()`
    - `var onItemClick: ((MenuBarItemInfo) -> Void)?`
    - `func show(items: [PanelItem], notch: CGRect)` — positions panel centered under notch; also updates items when already shown.
    - `func hide()`
    - `var panelFrame: CGRect?` — nil when hidden (fed to `HoverStateMachine.mouseMoved(panel:)`).

- [ ] **Step 1: Implement**

`Sources/DropNotchCore/NotchPanelController.swift`:

```swift
import AppKit
import SwiftUI

public struct PanelItem: Identifiable {
    public let id: Int
    public let info: MenuBarItemInfo
    public let image: NSImage

    public init(id: Int, info: MenuBarItemInfo, image: NSImage) {
        self.id = id
        self.info = info
        self.image = image
    }
}

@MainActor
final class PanelModel: ObservableObject {
    @Published var items: [PanelItem] = []
    var onClick: ((MenuBarItemInfo) -> Void)?
}

struct NotchPanelView: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        HStack(spacing: 8) {
            if model.items.isEmpty {
                Text("Nothing hidden")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.items) { item in
                    IconButton(item: item) { model.onClick?(item.info) }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background(
            UnevenRoundedRectangle(
                cornerRadii: .init(bottomLeading: 14, bottomTrailing: 14),
                style: .continuous)
            .fill(Color.black)
        )
    }
}

private struct IconButton: View {
    let item: PanelItem
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Image(nsImage: item.image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: 24)
            .frame(minWidth: 28)
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hovering ? Color.white.opacity(0.2) : Color.clear)
            )
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
            .help(item.info.title ?? item.info.ownerName)
    }
}

@MainActor
public final class NotchPanelController {
    private let panel: NSPanel
    private let model = PanelModel()

    public var onItemClick: ((MenuBarItemInfo) -> Void)? {
        get { model.onClick }
        set { model.onClick = newValue }
    }

    public var panelFrame: CGRect? {
        panel.isVisible ? panel.frame : nil
    }

    public init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: NotchPanelView(model: model))
    }

    public func show(items: [PanelItem], notch: CGRect) {
        model.items = items
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.contentView?.fittingSize ?? .zero
        let width = max(size.width, notch.width)
        let origin = CGPoint(x: notch.midX - width / 2, y: notch.minY - size.height)
        panel.setFrame(CGRect(origin: origin, size: CGSize(width: width, height: size.height)),
                       display: true)
        panel.orderFrontRegardless()
    }

    public func hide() {
        panel.orderOut(nil)
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build && swift test`
Expected: build succeeds, tests pass.

- [ ] **Step 3: Commit**

```bash
git add Sources/DropNotchCore/NotchPanelController.swift
git commit -m "feat: notch dropdown panel UI"
```

---

### Task 8: ClickForwarder

**Files:**
- Create: `Sources/DropNotchCore/ClickForwarder.swift`

**Interfaces:**
- Consumes: `MenuBarItemInfo`, `AXItemSource.pressItem(pid:nearCocoaX:mainDisplayHeight:)`, `NotchGeometry.cgPoint(fromCocoaPoint:mainDisplayHeight:)`.
- Produces: `final class ClickForwarder { init(axSource: AXItemSource); func activate(_ item: MenuBarItemInfo) }`

- [ ] **Step 1: Implement**

`Sources/DropNotchCore/ClickForwarder.swift`:

```swift
import AppKit
import CoreGraphics
import os.log

/// Activates a real status item: AXPress first, synthetic click fallback.
public final class ClickForwarder {
    private let axSource: AXItemSource
    private let log = Logger(subsystem: DropNotchInfo.logSubsystem, category: "click")

    public init(axSource: AXItemSource) {
        self.axSource = axSource
    }

    public func activate(_ item: MenuBarItemInfo) {
        let height = CGDisplayBounds(CGMainDisplayID()).height
        if axSource.pressItem(pid: item.ownerPID, nearCocoaX: item.frame.midX, mainDisplayHeight: height) {
            return
        }
        log.info("AXPress failed for \(item.ownerName), falling back to synthetic click")
        syntheticClick(at: CGPoint(x: item.frame.midX, y: item.frame.midY), mainDisplayHeight: height)
    }

    private func syntheticClick(at cocoaPoint: CGPoint, mainDisplayHeight: CGFloat) {
        let point = NotchGeometry.cgPoint(fromCocoaPoint: cocoaPoint, mainDisplayHeight: mainDisplayHeight)
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                 mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                               mouseCursorPosition: point, mouseButton: .left)
        else {
            log.error("failed to create CGEvent for synthetic click")
            return
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build && swift test`
Expected: build succeeds, tests pass.

- [ ] **Step 3: Commit**

```bash
git add Sources/DropNotchCore/ClickForwarder.swift
git commit -m "feat: click forwarding via AXPress with CGEvent fallback"
```

---

### Task 9: Wiring — AppCoordinator, StatusMenuController, AppDelegate, onboarding, smoke checklist

**Files:**
- Create: `Sources/DropNotchCore/AppCoordinator.swift`
- Create: `Sources/DropNotchCore/StatusMenuController.swift`
- Create: `Sources/DropNotchCore/AppDelegate.swift`
- Modify: `Sources/DropNotch/main.swift` (replace placeholder)
- Create: `docs/smoke-checklist.md`

**Interfaces:**
- Consumes: everything from Tasks 2–8.
- Produces: runnable app. `AppCoordinator(windowList:axSource:capturer:)` with `func start()`, `func stop()`, `var isPaused: Bool`; `AppDelegate` as `NSApplicationDelegate`.

- [ ] **Step 1: Implement AppCoordinator**

`Sources/DropNotchCore/AppCoordinator.swift`:

```swift
import AppKit
import os.log

/// Wires mouse monitoring, the hover state machine, scanning, capture,
/// the panel, and click forwarding.
@MainActor
public final class AppCoordinator {
    private let stateMachine = HoverStateMachine()
    private let windowList: WindowListProviding
    private let axSource: AXItemSource
    private let capturer: IconCapturing
    private let panelController = NotchPanelController()
    private let clickForwarder: ClickForwarder
    private let log = Logger(subsystem: DropNotchInfo.logSubsystem, category: "coordinator")

    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var graceTimer: Timer?
    private var refreshTimer: Timer?
    private var refreshTask: Task<Void, Never>?

    public var isPaused = false {
        didSet { if isPaused { hidePanel() } }
    }

    public init(windowList: WindowListProviding = CGWindowListProvider(),
                axSource: AXItemSource = AXItemSource(),
                capturer: IconCapturing = SCKIconCapturer()) {
        self.windowList = windowList
        self.axSource = axSource
        self.capturer = capturer
        self.clickForwarder = ClickForwarder(axSource: axSource)
        panelController.onItemClick = { [weak self] item in
            self?.hidePanel()
            self?.clickForwarder.activate(item)
        }
    }

    public func start() {
        // Global monitor misses events over our own panel; local monitor covers those.
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            Task { @MainActor in self?.handleMouseMoved() }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            Task { @MainActor in self?.handleMouseMoved() }
            return event
        }
    }

    public func stop() {
        if let monitor = globalMouseMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = localMouseMonitor { NSEvent.removeMonitor(monitor) }
        globalMouseMonitor = nil
        localMouseMonitor = nil
        hidePanel()
    }

    // MARK: - Hover handling

    private var builtInScreen: NSScreen? {
        NSScreen.screens.first {
            CGDisplayIsBuiltin($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0) != 0
        }
    }

    private var notchRect: CGRect? {
        guard let screen = builtInScreen else { return nil }
        return NotchGeometry.notchRect(
            screenFrame: screen.frame,
            auxLeft: screen.auxiliaryTopLeftArea,
            auxRight: screen.auxiliaryTopRightArea)
    }

    private func handleMouseMoved() {
        guard !isPaused, let notch = notchRect else { return }
        if stateMachine.isIdle && !windowList.isMenuBarVisible() { return }
        let action = stateMachine.mouseMoved(
            to: NSEvent.mouseLocation,
            notch: notch,
            panel: panelController.panelFrame,
            now: Date())
        perform(action, notch: notch)
    }

    private func perform(_ action: HoverAction, notch: CGRect) {
        switch action {
        case .show: showPanel(notch: notch)
        case .hide: hidePanel()
        case .none: break
        }
    }

    // MARK: - Panel lifecycle

    private func showPanel(notch: CGRect) {
        refreshPanel(notch: notch)

        graceTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let notch = self.notchRect else { return }
                self.perform(self.stateMachine.tick(now: Date()), notch: notch)
            }
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let notch = self.notchRect else { return }
                self.refreshPanel(notch: notch)
            }
        }
    }

    private func refreshPanel(notch: CGRect) {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let items = self.scanHiddenItems(notch: notch)
            var panelItems: [PanelItem] = []
            for (index, item) in items.enumerated() {
                let image = await self.capturer.captureIcon(for: item)
                panelItems.append(PanelItem(id: index, info: item, image: image))
            }
            guard !Task.isCancelled, !self.stateMachine.isIdle else { return }
            self.panelController.show(items: panelItems, notch: notch)
        }
    }

    private func scanHiddenItems(notch: CGRect) -> [MenuBarItemInfo] {
        guard let screen = builtInScreen else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let windows = windowList.menuBarItemWindows()
        var hidden = StatusItemScanner.hiddenItems(
            windows: windows, notch: notch, screenFrame: screen.frame, ownPID: pid_t(ownPID))

        // Union in AX-only items: apps whose status item window wasn't enumerable.
        let knownPIDs = Set(windows.map(\.ownerPID))
        let axHidden = StatusItemScanner.hiddenItems(
            windows: axSource.items().filter { !knownPIDs.contains($0.ownerPID) },
            notch: notch, screenFrame: screen.frame, ownPID: pid_t(ownPID))
        hidden.append(contentsOf: axHidden)
        return hidden.sorted { $0.frame.minX < $1.frame.minX }
    }

    private func hidePanel() {
        graceTimer?.invalidate()
        refreshTimer?.invalidate()
        graceTimer = nil
        refreshTimer = nil
        refreshTask?.cancel()
        panelController.hide()
    }
}
```

- [ ] **Step 2: Implement StatusMenuController**

`Sources/DropNotchCore/StatusMenuController.swift`:

```swift
import AppKit
import ServiceManagement

@MainActor
public final class StatusMenuController: NSObject {
    private var statusItem: NSStatusItem!
    private let coordinator: AppCoordinator
    private let pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        super.init()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "rectangle.topthird.inset.filled",
            accessibilityDescription: "DropNotch")

        let menu = NSMenu()
        pauseItem.target = self
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        if !Self.hasNotchedScreen {
            let noNotch = NSMenuItem(title: "No notch on this display", action: nil, keyEquivalent: "")
            noNotch.isEnabled = false
            menu.addItem(noNotch)
            menu.addItem(.separator())
        }
        menu.addItem(pauseItem)
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit DropNotch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private static var hasNotchedScreen: Bool {
        NSScreen.screens.contains { screen in
            NotchGeometry.notchRect(screenFrame: screen.frame,
                                    auxLeft: screen.auxiliaryTopLeftArea,
                                    auxRight: screen.auxiliaryTopRightArea) != nil
        }
    }

    @objc private func togglePause() {
        coordinator.isPaused.toggle()
        pauseItem.state = coordinator.isPaused ? .on : .off
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                loginItem.state = .off
            } else {
                try SMAppService.mainApp.register()
                loginItem.state = .on
            }
        } catch {
            // Registration fails when running outside an app bundle; ignore.
        }
    }
}
```

- [ ] **Step 3: Implement AppDelegate + onboarding window**

`Sources/DropNotchCore/AppDelegate.swift`:

```swift
import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?
    private var statusMenu: StatusMenuController?
    private var onboardingWindow: NSWindow?

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let coordinator = AppCoordinator()
        self.coordinator = coordinator
        statusMenu = StatusMenuController(coordinator: coordinator)

        if Permissions.allGranted {
            coordinator.start()
        } else {
            showOnboarding()
        }
    }

    public func applicationDidBecomeActive(_ notification: Notification) {
        // Re-check after the user visits System Settings.
        if Permissions.allGranted, let coordinator {
            onboardingWindow?.close()
            onboardingWindow = nil
            coordinator.start()
        }
    }

    private func showOnboarding() {
        Permissions.requestScreenRecording()
        Permissions.promptAccessibility()

        let alertText = """
        DropNotch needs two permissions:

        • Screen Recording — to show live images of hidden menu bar icons
        • Accessibility — to click them for you

        Grant both in System Settings, then relaunch DropNotch.
        """
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = "DropNotch Permissions"
        window.center()

        let text = NSTextField(wrappingLabelWithString: alertText)
        let screenButton = NSButton(title: "Open Screen Recording Settings",
                                    target: self, action: #selector(openScreenSettings))
        let axButton = NSButton(title: "Open Accessibility Settings",
                                target: self, action: #selector(openAXSettings))
        let stack = NSStackView(views: [text, screenButton, axButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        window.contentView = stack

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }

    @objc private func openScreenSettings() { Permissions.openScreenRecordingSettings() }
    @objc private func openAXSettings() { Permissions.openAccessibilitySettings() }
}
```

Replace `Sources/DropNotch/main.swift`:

```swift
import AppKit
import DropNotchCore

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 4: Build and test**

Run: `swift build && swift test`
Expected: build succeeds, all tests pass.

- [ ] **Step 5: Write smoke checklist**

`docs/smoke-checklist.md`:

```markdown
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
```

- [ ] **Step 6: Manual smoke test**

Run: `./scripts/make-app.sh && open build/DropNotch.app`
Walk `docs/smoke-checklist.md` top to bottom. Fix anything broken before committing.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: app wiring, status menu, permissions onboarding, smoke checklist"
```

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

import AppKit

/// Native macOS trackpad tactile feedback performer.
enum Haptics {
    /// Gentle alignment click (for hovering, toggling pills, snapping).
    static func tap() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    /// Firm mechanical click (for destructive actions, split view pairing, mode toggles).
    static func click() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}

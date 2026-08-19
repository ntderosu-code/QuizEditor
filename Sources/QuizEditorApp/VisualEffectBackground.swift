import SwiftUI
import AppKit

/// The system's sidebar/inspector material, for a view that is a split-view
/// column but is not a SwiftUI `.inspector`.
///
/// The AI panel used to be an `.inspector`, which supplied this material itself.
/// It had to become an ordinary `HSplitView` child (see #97), and on plain white
/// it read as more editing surface rather than as chrome. SwiftUI's
/// `.regularMaterial` is close but noticeably lighter than the sidebar it sits
/// opposite; `NSVisualEffectView` with the real material matches exactly and
/// keeps the system's own handling of dark mode, Reduce Transparency, and
/// Increased Contrast.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    /// Within the window, not behind it. `.behindWindow` samples the desktop, so
    /// the panel picked up smears of whatever wallpaper happened to be under the
    /// window; the panel is interior chrome, not a window edge.
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        // Follow the window's key state the way the real sidebar does, rather
        // than staying vivid while the window is in the background.
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
    }
}

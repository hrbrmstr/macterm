import Foundation

/// Generates the ghostty config file that libghostty loads. Macterm owns this
/// config entirely — users do not edit it. All user-facing settings live in
/// `Preferences` (UserDefaults); `regenerate()` reads them and writes a fresh
/// ghostty.conf to App Support, which `GhosttyApp.loadConfig` then loads.
///
/// We force `background-opacity = 1` and `background-blur = 0` so ghostty's
/// renderer draws fully opaque terminal content. Window translucency is
/// composited at the window level by Macterm (see `WindowAppearance`),
/// avoiding the double-paint that happens when both ghostty and Macterm
/// tint the same pixels.
@MainActor @Observable
final class MactermConfig {
    static let shared = MactermConfig()

    let ghosttyConfigURL: URL

    private init() {
        let dir = FileStorage.appSupportDirectory()
        ghosttyConfigURL = dir.appendingPathComponent("ghostty.conf")
        // Write a fresh config on every launch so the file always reflects
        // the current Preferences state — no stale lines from previous runs.
        regenerate()
    }

    var ghosttyConfigPath: String { ghosttyConfigURL.path }

    /// Rebuild the ghostty.conf file from current `Preferences` values.
    /// Called on launch and whenever a relevant preference changes.
    func regenerate() {
        let prefs = Preferences.shared
        var lines: [String] = []

        // --- Macterm-managed window appearance ---
        // Ghostty's terminal surface is fully transparent — it draws only the
        // text and cursor. The colored fill behind the text comes from the
        // window's `NSWindow.backgroundColor` (set in `WindowAppearance.sync`
        // to the terminal color tinted by `Preferences.windowOpacity`), which
        // is the single source of window translucency. Keeping all tinting on
        // one layer avoids the double-paint that happens when both ghostty's
        // renderer and SwiftUI/AppKit tint the same pixels.
        lines.append("background-opacity = 0")
        // Blur is driven by our own CGS SPI call, not ghostty's wrapper.
        lines.append("background-blur = 0")

        // --- User-configurable via Settings UI ---
        if !prefs.theme.isEmpty {
            lines.append("theme = \"\(prefs.theme)\"")
        }
        if !prefs.fontFamily.isEmpty {
            lines.append("font-family = \(prefs.fontFamily)")
        }
        lines.append("font-size = \(prefs.fontSize)")
        lines.append("macos-option-as-alt = \(prefs.optionAsAlt)")

        // --- Sensible defaults the user can't currently override ---
        // Keep this list minimal; expose to Settings UI as needed instead of
        // documenting "edit this file." Anything here should be a default that
        // virtually all users will want.
        lines.append("scrollbar = system")
        lines.append("mouse-hide-while-typing = true")
        lines.append("clipboard-trim-trailing-spaces = true")
        lines.append("window-padding-x = 16")
        lines.append("window-padding-y = 16")

        let content = lines.joined(separator: "\n") + "\n"
        try? Data(content.utf8).write(to: ghosttyConfigURL, options: .atomic)
    }
}

import AppKit
import GhosttyKit

extension NSView {
    /// Recursively finds the first descendant view whose class name (as a string)
    /// matches `name`. Used to reach into AppKit's private titlebar view tree —
    /// the only known way to colorize the titlebar to match a transparent
    /// window background. Lifted from Ghostty's NSView+Extension.swift.
    func firstDescendant(withClassName name: String) -> NSView? {
        for subview in subviews {
            if String(describing: type(of: subview)) == name {
                return subview
            }
            if let found = subview.firstDescendant(withClassName: name) {
                return found
            }
        }
        return nil
    }
}

/// Encapsulates the Tahoe-only window styling work needed to make the titlebar
/// blend with a transparent terminal background. AppKit gives us two surface
/// areas — the content view and a separate, system-owned titlebar view tree —
/// that don't compose visually with a single `backgroundColor` setting. To
/// make them look uniform we have to reach into the private titlebar hierarchy
/// and override its layer color directly.
///
/// Mirrors the `syncAppearanceTahoe` path in Ghostty's
/// `TransparentTitlebarTerminalWindow.swift`. Pre-Tahoe macOS releases need
/// different incantations (hiding NSVisualEffectView, etc.) — Macterm targets
/// macOS 26+ so we only ship the Tahoe path.
@MainActor
enum WindowAppearance {
    /// Apply the current opacity/blur settings to `window`. Safe to call any
    /// time — re-applies idempotently. Should be called after the window is
    /// onscreen, on theme changes, and on focus changes (AppKit recreates
    /// titlebar subviews under us in some cases, e.g. tab bar appearing).
    static func sync(window: NSWindow) {
        let opacity = GhosttyApp.shared.backgroundOpacity
        let bg = GhosttyApp.shared.backgroundColor
        let blurEnabled = GhosttyApp.shared.backgroundBlurEnabled
        let isTransparent = opacity < 1.0

        // Native fullscreen draws its own opaque grey background; widgets show
        // through any transparency we apply, so force opaque while fullscreened.
        let forceOpaque = window.styleMask.contains(.fullScreen)
        let effectiveTransparent = isTransparent && !forceOpaque

        if effectiveTransparent {
            window.isOpaque = false
            // The 0.001-alpha-white trick is from Ghostty: `.clear` gets
            // special-cased somewhere in AppKit and produces a visibly
            // different composite. The near-zero alpha works around it.
            window.backgroundColor = .white.withAlphaComponent(0.001)
            if blurEnabled, let app = GhosttyApp.shared.app {
                ghostty_set_window_background_blur(app, Unmanaged.passUnretained(window).toOpaque())
            }
        } else {
            window.isOpaque = true
            window.backgroundColor = bg
        }

        // Override the titlebar's private background layer so its color
        // matches the terminal background (or stays transparent when the
        // window is). Without this the titlebar paints its own material
        // and you get a visible seam at y=titlebarHeight.
        syncTitlebar(window: window, isTransparent: effectiveTransparent, bg: bg)
    }

    private static func syncTitlebar(window: NSWindow, isTransparent: Bool, bg: NSColor) {
        guard let container = titlebarContainer(in: window) else { return }

        if let titlebarView = container.firstDescendant(withClassName: "NSTitlebarView") {
            titlebarView.wantsLayer = true
            // On Tahoe with liquid glass, the NavigationSplitView's sidebar
            // is a system glass surface that extends behind the titlebar by
            // design. Painting a flat color over the titlebar covers that
            // glass and creates a visible break across the sidebar. Instead,
            // leave the titlebar transparent and let the system materials
            // (glass sidebar on one side, detail view's painted bg on the
            // other) show through. In the opaque case we still fill so the
            // titlebar matches the terminal background.
            titlebarView.layer?.backgroundColor = isTransparent
                ? NSColor.clear.cgColor
                : bg.cgColor
        }

        // NSTitlebarBackgroundView has subviews that force their own background
        // colors; hiding it is the only way to keep our override visible.
        container.firstDescendant(withClassName: "NSTitlebarBackgroundView")?.isHidden = true
    }

    private static func titlebarContainer(in window: NSWindow) -> NSView? {
        // The titlebar container lives on the window's content view's root in
        // normal mode, and on a separate NSToolbarFullScreenWindow in native
        // fullscreen. We don't support native fullscreen tab bars, so the
        // first path suffices for Macterm.
        guard let contentView = window.contentView else { return nil }
        var root: NSView = contentView
        while let s = root.superview {
            root = s
        }
        if String(describing: type(of: root)) == "NSTitlebarContainerView" { return root }
        return root.firstDescendant(withClassName: "NSTitlebarContainerView")
    }
}

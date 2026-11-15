import AppKit
import SwiftUI

/// The Settings window (⌘,): RandAmp's own options, gathered in one place. A window of its own,
/// like the player's, so it opens the same way from the menu bar, the Dock and the menus.
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView())
            host.sizingOptions = [.preferredContentSize]
            let created = NSWindow(contentViewController: host)
            created.title = "RandAmp Settings"
            created.styleMask = [.titled, .closable]
            created.isReleasedWhenClosed = false
            created.center()
            created.setFrameAutosaveName("SettingsWindow")
            window = created
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// "Settings…" for the "…" menus.
struct SettingsMenuItem: View {
    var body: some View {
        Button("Settings…") { SettingsWindow.show() }
    }
}

struct SettingsView: View {
    @AppStorage(AppIcon.key) private var coverAsIcon = false
    @AppStorage(PlayerWindow.dockKey) private var showsInDock = true
    @State private var openAtLogin = LoginItem.isEnabled
    @State private var loginMessage: String?

    var body: some View {
        Form {
            Section("App icon") {
                Toggle("Show the cover of the album playing as the app icon", isOn: $coverAsIcon)
                    .onChange(of: coverAsIcon) { _ in AppIcon.apply() }
                Text("In the Dock and in ⌘-Tab, while RandAmp is there. The usual icon comes back when nothing plays.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Dock and login") {
                Toggle("Show in the Dock while the player window is open", isOn: $showsInDock)
                    .onChange(of: showsInDock) { _ in PlayerWindow.updateDockIcon() }
                Toggle("Open at login", isOn: Binding(
                    get: { openAtLogin },
                    set: { newValue in
                        loginMessage = LoginItem.set(newValue)
                        openAtLogin = LoginItem.isEnabled
                    }))
                if let loginMessage {
                    Text(loginMessage).font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        // macOS can change the login item too (System Settings): read it again on each opening.
        .onAppear { openAtLogin = LoginItem.isEnabled }
    }
}

/// "Show the cover of the album playing as the app icon": the Dock and ⌘-Tab show the cover, in the
/// shape of a macOS icon, instead of RandAmp's. macOS forgets it when the app quits.
@MainActor
enum AppIcon {
    static let key = "coverAsAppIcon"
    static var isOn: Bool { UserDefaults.standard.bool(forKey: key) }

    /// Shows the cover playing, or RandAmp's own icon when the setting is off or nothing plays.
    static func apply() {
        guard isOn, let cover = Player.shared.cover else {
            NSApp.applicationIconImage = nil // Back to the icon of the app bundle.
            return
        }
        NSApp.applicationIconImage = icon(from: cover)
    }

    /// The cover on macOS's icon grid: a rounded square of 824 points in 1024, with a soft shadow,
    /// so it sits in the Dock like the other icons.
    static func icon(from cover: NSImage) -> NSImage {
        let size = NSSize(width: 1024, height: 1024)
        return NSImage(size: size, flipped: false) { _ in
            let square = NSRect(x: 100, y: 100, width: 824, height: 824)
            let shape = NSBezierPath(roundedRect: square, xRadius: 185, yRadius: 185)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = .black.withAlphaComponent(0.3)
            shadow.shadowBlurRadius = 20
            shadow.shadowOffset = NSSize(width: 0, height: -10)
            shadow.set()
            NSColor.black.setFill()
            shape.fill()
            NSGraphicsContext.restoreGraphicsState()
            shape.addClip()
            // Fills the square, cropped in the middle when the cover isn't square.
            let ratio = cover.size.width / max(cover.size.height, 1)
            var drawn = square
            if ratio > 1 { drawn.size.width = square.height * ratio; drawn.origin.x = square.midX - drawn.width / 2 }
            if ratio < 1 { drawn.size.height = square.width / ratio; drawn.origin.y = square.midY - drawn.height / 2 }
            cover.draw(in: drawn, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
    }
}

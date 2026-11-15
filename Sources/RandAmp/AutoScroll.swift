import AppKit
import SwiftUI

/// Settings › "Scroll each tab slowly to the bottom": while the side panel goes through the tabs of
/// the album playing, each tab scrolls down by itself. The tabs' SwiftUI scroll views are AppKit
/// scroll views underneath; a marker in their content finds them.
@MainActor
enum PanelScroll {
    static let key = "panelAutoScroll"
    /// Slow enough to read along.
    static let pointsPerSecond: CGFloat = 30
    /// The time to look at the top of a tab before it starts moving, from when its content shows.
    static let pause: Double = 1.5

    private final class Weak {
        weak var view: NSScrollView?
        init(_ view: NSScrollView?) { self.view = view }
    }
    private static var views: [ArtistsView.Tab: Weak] = [:]

    /// Posted when you scroll or click in a tab of the album playing, which stops the tab cycle.
    static let userActed = Notification.Name("PanelScroll.userActed")
    private static var monitor: Any?

    static func register(_ tab: ArtistsView.Tab, _ view: NSScrollView?) {
        views[tab] = Weak(view)
        guard monitor == nil else { return }
        // The scrolling of this loop makes no events: these are yours.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .leftMouseDown]) { event in
            MainActor.assumeIsolated { noteUserAction(event) }
            return event
        }
    }

    private static func noteUserAction(_ event: NSEvent) {
        guard let window = event.window else { return }
        let inTab = views.values.contains { entry in
            guard let view = entry.view, view.window === window else { return false }
            return view.bounds.contains(view.convert(event.locationInWindow, from: nil))
        }
        if inTab { NotificationCenter.default.post(name: userActed, object: nil) }
    }

    /// Scrolls the tab down slowly, 1.5 seconds after its content shows. Returns at the bottom (once
    /// the content stops growing), when the task is cancelled, or as soon as you scroll it yourself.
    static func scrollToBottom(_ tab: ArtistsView.Tab) async {
        let frame: UInt64 = 16_666_667 // A 60th of a second.
        var expected: CGFloat?
        var atBottomSince: Date?
        var waited = 0
        var paused = false
        while !Task.isCancelled {
            guard let scrollView = views[tab]?.view, scrollView.window != nil,
                  let document = scrollView.documentView else {
                // The tab may still be loading: give it 10 seconds.
                waited += 1
                if waited > 600 { return }
                try? await Task.sleep(nanoseconds: frame)
                continue
            }
            if !paused {
                paused = true
                try? await Task.sleep(nanoseconds: UInt64(pause * 1_000_000_000))
                continue // The content may have been replaced meanwhile: find it again.
            }
            let clip = scrollView.contentView
            let current = clip.bounds.origin
            // Moved by something else than this loop: you scrolled. Leave it there.
            if let expected, abs(current.y - expected) > 2 { return }
            let step = pointsPerSecond / 60 * (document.isFlipped ? 1 : -1)
            let target = clip.constrainBoundsRect(NSRect(origin: NSPoint(x: current.x, y: current.y + step),
                                                         size: clip.bounds.size)).origin
            if abs(target.y - current.y) < 0.01 {
                // At the bottom. A picture or a list that loads can still make it longer.
                let since = atBottomSince ?? Date()
                atBottomSince = since
                if Date().timeIntervalSince(since) > 0.6 { return }
                expected = current.y
            } else {
                atBottomSince = nil
                clip.scroll(to: target)
                scrollView.reflectScrolledClipView(clip)
                expected = target.y
            }
            try? await Task.sleep(nanoseconds: frame)
        }
    }
}

extension View {
    /// Marks the content of a panel tab's ScrollView, so the tab cycle can scroll it.
    func panelScrollable(_ tab: ArtistsView.Tab) -> some View {
        background(PanelScrollMarker(tab: tab))
    }
}

private struct PanelScrollMarker: NSViewRepresentable {
    let tab: ArtistsView.Tab

    func makeNSView(context: Context) -> NSView { Marker(tab: tab) }
    func updateNSView(_ view: NSView, context: Context) {}

    final class Marker: NSView {
        let tab: ArtistsView.Tab
        init(tab: ArtistsView.Tab) {
            self.tab = tab
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            // The scroll view is set up around the content right after.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                PanelScroll.register(self.tab, self.enclosingScrollView)
            }
        }
    }
}

import AppKit
import SwiftUI

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Owns the see-through window that sits over the notch, and opens or closes
/// the island as the mouse comes and goes.
@MainActor
final class IslandController {
    private let store: SessionStore
    private let ui = IslandUI()
    private let panel: IslandPanel
    private var pinned: Bool
    private var hoverTimer: Timer?
    private var outsideSince: Date?
    /// After the minus button, don't pop open again until the mouse has left
    private var waitForMouseOut = false
    private var peekTask: Task<Void, Never>?

    init(store: SessionStore, pinned: Bool) {
        self.store = store
        self.pinned = pinned

        panel = IslandPanel(contentRect: NSRect(origin: .zero, size: ui.canvas),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true

        let actions = IslandActions(
            open: { [weak self] in self?.open($0) },
            select: { [weak self] in self?.ui.selectedId = $0.id },
            minimize: { [weak self] in self?.minimize() },
            markAllSeen: { [weak self] in self?.store.acknowledgeAll() },
            editCritters: { [weak self] in
                guard let self else { return }
                CrewLooks.shared.openFile(projects: self.store.sessions.map(\.cwd))
            },
            quit: { NSApp.terminate(nil) }
        )
        let host = FirstMouseHostingView(rootView: IslandView(store: store, ui: ui, actions: actions))
        host.sizingOptions = []
        panel.contentView = host

        placePanel()
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.placePanel() }
        }

        store.onAlert = { [weak self] in self?.showPeek($0) }

        if pinned {
            ui.mode = .expanded
            panel.ignoresMouseEvents = false
        }
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    // MARK: placement

    private func placePanel() {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        let top = screen.safeAreaInsets.top
        if top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            ui.notchSize = CGSize(width: screen.frame.width - left.width - right.width, height: top)
        } else {
            // No notch: sit as a pill in the middle of the menu bar
            let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
            ui.notchSize = CGSize(width: 120, height: max(menuBar, 24))
        }
        let c = ui.canvas
        panel.setFrame(NSRect(x: screen.frame.midX - c.width / 2, y: screen.frame.maxY - c.height,
                              width: c.width, height: c.height), display: true)
    }

    private func islandRect() -> NSRect {
        let size = ui.islandSize(sessionCount: store.sessions.count)
        let f = panel.frame
        return NSRect(x: f.midX - size.width / 2, y: f.maxY - size.height, width: size.width, height: size.height)
    }

    // MARK: hover

    private func tick() {
        guard !pinned else { return }
        let inside = islandRect().insetBy(dx: -6, dy: -6).contains(NSEvent.mouseLocation)
        if inside {
            outsideSince = nil
            if ui.mode == .collapsed && !waitForMouseOut { expand() }
        } else if waitForMouseOut {
            waitForMouseOut = false
        } else if ui.mode == .expanded {
            if let since = outsideSince {
                if Date().timeIntervalSince(since) > 0.4 { collapse() }
            } else {
                outsideSince = Date()
            }
        }
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
    }

    private func expand() {
        peekTask?.cancel()
        ui.peek = nil
        ui.selectedId = store.sessions.first?.id
        ui.mode = .expanded
    }

    private func collapse() {
        outsideSince = nil
        ui.mode = .collapsed
    }

    private func minimize() {
        pinned = false
        waitForMouseOut = true
        collapse()
    }

    // MARK: actions

    private func open(_ session: CrewSession) {
        store.acknowledge(session)
        if let host = session.hostSessionId, var c = URLComponents(string: "claude://code/continue") {
            c.queryItems = [URLQueryItem(name: "session", value: host)]
            if let url = c.url { NSWorkspace.shared.open(url) }
        } else {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/Claude.app"),
                                               configuration: NSWorkspace.OpenConfiguration())
        }
        if !pinned { collapse() }
    }

    private func showPeek(_ session: CrewSession) {
        bounce(times: 3)
        guard ui.mode == .collapsed else { return }
        ui.peek = session
        peekTask?.cancel()
        peekTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(7))
            guard !Task.isCancelled else { return }
            self?.ui.peek = nil
        }
    }

    private func bounce(times: Int) {
        Task { @MainActor [weak self] in
            for _ in 0..<times {
                self?.ui.bump = true
                try? await Task.sleep(for: .milliseconds(170))
                self?.ui.bump = false
                try? await Task.sleep(for: .milliseconds(260))
            }
        }
    }
}

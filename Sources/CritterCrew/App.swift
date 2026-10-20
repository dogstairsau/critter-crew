import AppKit
import SwiftUI

@main
enum CritterCrewApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = SessionStore()
    private var island: IslandController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        // --snapshot <file.png> saves a picture of the open island and quits
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            snapshot(to: URL(fileURLWithPath: args[i + 1]))
            NSApp.terminate(nil)
            return
        }
        // --pinned keeps the island open, handy for checking the layout
        let pinned = args.contains("--pinned")
        island = IslandController(store: store, pinned: pinned)
        store.start()
    }

    private func snapshot(to url: URL) {
        store.refresh()
        let ui = IslandUI()
        ui.mode = .expanded
        if let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }),
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            ui.notchSize = CGSize(width: screen.frame.width - left.width - right.width, height: screen.safeAreaInsets.top)
        }
        let noop = IslandActions(open: { _ in }, select: { _ in }, minimize: {}, markAllSeen: {}, editCritters: {}, quit: {})
        let view = IslandView(store: store, ui: ui, actions: noop)
            .background(Color(hex: "#33456F"))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let cg = renderer.cgImage else { return }
        let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
        try? png?.write(to: url)
    }
}

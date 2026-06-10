import AppKit
import SpriteKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var skView: SKView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let size = CGSize(width: 1180, height: 820)
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.collectionBehavior = [.fullScreenPrimary]
        window.title = "PARTICLE"
        window.backgroundColor = .black
        window.center()
        window.acceptsMouseMovedEvents = true
        window.delegate = self

        skView = SKView(frame: NSRect(origin: .zero, size: size))
        skView.autoresizingMask = [.width, .height]
        skView.preferredFramesPerSecond = 60
        skView.ignoresSiblingOrder = true

        let scene = GameScene(size: size)
        scene.scaleMode = .resizeFill
        skView.presentScene(scene)

        // Tracking area ensures mouseMoved events reach the scene without clicking first
        let tracking = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: skView,
            userInfo: nil
        )
        skView.addTrackingArea(tracking)

        // Wrap skView in a plain container so autoresizingMask propagates
        // correctly through macOS fullscreen transitions
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.autoresizingMask = [.width, .height]
        container.addSubview(skView)

        window.contentView = container
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(skView)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: - NSWindowDelegate (quit confirmation)

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Quit PARTICLE?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: - NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        guard let cv = window.contentView else { return }
        skView.frame = cv.bounds
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let cv = self.window.contentView else { return }
            self.skView.frame = cv.bounds
        }
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let cv = self.window.contentView else { return }
            self.skView.frame = cv.bounds
        }
    }
}

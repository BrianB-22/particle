import AppKit
import SpriteKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let size = CGSize(width: 1180, height: 820)
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PARTICLE"
        window.backgroundColor = .black
        window.center()
        window.acceptsMouseMovedEvents = true

        let skView = SKView(frame: NSRect(origin: .zero, size: size))
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

        window.contentView = skView
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(skView)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

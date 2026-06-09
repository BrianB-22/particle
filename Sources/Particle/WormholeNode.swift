import SpriteKit

final class WormholeNode: SKNode {
    static let gravityRadius:   CGFloat = 160
    static let killRadius:      CGFloat = 24
    static let gravityStrength: CGFloat = 1.8

    var velocity: CGVector = .zero

    override init() {
        super.init()
        buildVisuals()
        let angle = CGFloat.random(in: 0...(2 * .pi))
        velocity = CGVector(dx: cos(angle) * 16, dy: sin(angle) * 16)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildVisuals() {
        // Faint gravity-field disc
        let field = SKShapeNode(circleOfRadius: WormholeNode.gravityRadius)
        field.fillColor = NSColor(red: 0.28, green: 0, blue: 0.5, alpha: 0.04)
        field.strokeColor = NSColor(red: 0.5, green: 0, blue: 0.9, alpha: 0.12)
        field.lineWidth = 1
        addChild(field)

        // Event horizon glow ring
        let horizon = SKShapeNode(circleOfRadius: WormholeNode.killRadius + 6)
        horizon.fillColor = .clear
        horizon.strokeColor = NSColor(red: 0.8, green: 0, blue: 1, alpha: 0.9)
        horizon.lineWidth = 2
        horizon.glowWidth = 16
        addChild(horizon)
        horizon.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.35, duration: 0.55),
            .fadeAlpha(to: 1.00, duration: 0.55)
        ])))

        // Singularity core
        let core = SKShapeNode(circleOfRadius: WormholeNode.killRadius)
        core.fillColor = NSColor(red: 0.04, green: 0, blue: 0.08, alpha: 0.97)
        core.strokeColor = .clear
        core.glowWidth = 4
        addChild(core)

        // Inner ring — 10 dots, counter-clockwise
        addChild(makeDotRing(count: 10, radius: WormholeNode.killRadius + 13,
                             dotR: 2.5, accent: 3, color: NSColor(red: 0.8, green: 0.1, blue: 1, alpha: 1),
                             duration: -1.7))

        // Outer ring — 7 dots, clockwise
        addChild(makeDotRing(count: 7, radius: WormholeNode.killRadius + 26,
                             dotR: 1.8, accent: 0, color: NSColor(red: 0.5, green: 0, blue: 0.8, alpha: 0.5),
                             duration: 3.1))
    }

    // duration < 0 = counter-clockwise
    private func makeDotRing(count: Int, radius: CGFloat, dotR: CGFloat,
                              accent: Int, color: NSColor, duration: Double) -> SKNode {
        let ring = SKNode()
        for i in 0..<count {
            let isBig = accent > 0 && i % accent == 0
            let r: CGFloat = isBig ? dotR * 1.4 : dotR
            let dot = SKShapeNode(circleOfRadius: r)
            dot.fillColor = isBig ? color : color.withAlphaComponent(0.5)
            dot.strokeColor = .clear
            let a = CGFloat(i) / CGFloat(count) * 2 * .pi
            dot.position = CGPoint(x: cos(a) * radius, y: sin(a) * radius)
            ring.addChild(dot)
        }
        let angle: CGFloat = duration < 0 ? -.pi * 2 : .pi * 2
        ring.run(.repeatForever(.rotate(byAngle: angle, duration: abs(duration))))
        return ring
    }
}

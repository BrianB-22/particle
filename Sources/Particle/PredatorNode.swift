import SpriteKit

final class PredatorNode: SKNode {
    var velocity: CGVector = CGVector(dx: 0, dy: 0)
    private(set) var isActive: Bool = false
    var ghostOnScreenTime: CGFloat = 0

    private let body: SKShapeNode

    override init() {
        body = SKShapeNode(circleOfRadius: 9)
        // Starts ghostly blue — not yet hunting
        body.fillColor   = PlatformColor(red: 0.30, green: 0.55, blue: 1.00, alpha: 0.70)
        body.strokeColor = PlatformColor(red: 0.55, green: 0.75, blue: 1.00, alpha: 0.90)
        body.lineWidth = 1.5
        body.glowWidth = 12

        super.init()
        addChild(body)

        // Slow ghost pulse while inactive
        body.run(.repeatForever(.sequence([
            .scale(to: 1.15, duration: 0.7),
            .scale(to: 1.00, duration: 0.7)
        ])))
    }

    // Called after the grace period — predator goes live
    func activate() {
        guard !isActive else { return }
        isActive = true

        body.removeAllActions()
        body.fillColor   = .white
        body.strokeColor = .white
        body.glowWidth   = 22
        body.setScale(1.6)

        // Flash white then settle into hunting orange
        body.run(.sequence([
            .group([
                .scale(to: 1.0, duration: 0.25),
                .run { [weak self] in
                    self?.body.fillColor   = PlatformColor(red: 1.0, green: 0.38, blue: 0.0, alpha: 1)
                    self?.body.strokeColor = PlatformColor(red: 1.0, green: 0.65, blue: 0.1, alpha: 1)
                    self?.body.glowWidth   = 10
                }
            ]),
            .repeatForever(.sequence([
                .scale(to: 1.3, duration: 0.4),
                .scale(to: 1.0, duration: 0.4)
            ]))
        ]))
    }

    required init?(coder: NSCoder) { fatalError() }

    func faceDirection(_ v: CGVector) {
        guard v.magnitude > 0.1 else { return }
        zRotation = atan2(v.dy, v.dx) - (.pi / 2)
    }

    func setHunting(_ hunting: Bool) {
        body.fillColor = hunting
            ? PlatformColor(red: 1.0, green: 0.10, blue: 0.0, alpha: 1)
            : PlatformColor(red: 1.0, green: 0.38, blue: 0.0, alpha: 1)
    }

    // Rage shake → grow → shrink out. Calls completion when done.
    func playRageExit(completion: @escaping () -> Void) {
        body.removeAllActions()

        // Turn red-hot
        body.fillColor = PlatformColor(red: 1.0, green: 0.05, blue: 0.05, alpha: 1)
        body.strokeColor = PlatformColor(red: 1.0, green: 0.4, blue: 0.0, alpha: 1)
        body.glowWidth = 18

        // Shake = rapid left-right offsets on the body
        let shakeOffset: CGFloat = 5
        let shake = SKAction.sequence([
            .moveBy(x: -shakeOffset, y:  shakeOffset * 0.5, duration: 0.04),
            .moveBy(x:  shakeOffset, y: -shakeOffset * 0.5, duration: 0.04),
            .moveBy(x: -shakeOffset, y: -shakeOffset * 0.5, duration: 0.04),
            .moveBy(x:  shakeOffset, y:  shakeOffset * 0.5, duration: 0.04),
        ])
        let rageShake = SKAction.repeat(shake, count: 6)  // ~0.96s of shaking

        // Grow while shaking
        let grow = SKAction.scale(to: 2.4, duration: 0.8)

        body.run(.group([rageShake, grow])) { [weak self] in
            // Shrink to nothing
            self?.body.run(.sequence([
                .group([.scale(to: 0, duration: 0.3), .fadeOut(withDuration: 0.3)]),
                .removeFromParent()
            ])) { completion() }
        }
    }
}

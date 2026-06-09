import SpriteKit

enum BoidState { case spawning, wandering, threatened, safe, dying }

final class BoidNode: SKNode {
    var velocity: CGVector
    var state: BoidState = .spawning

    let neonColor: PlatformColor
    private let core: SKShapeNode
    private let halo: SKShapeNode

    private static let palette: [PlatformColor] = [
        PlatformColor(red: 0.00, green: 0.96, blue: 1.00, alpha: 1), // electric cyan
        PlatformColor(red: 1.00, green: 0.18, blue: 0.47, alpha: 1), // hot pink
        PlatformColor(red: 0.22, green: 1.00, blue: 0.08, alpha: 1), // acid green
    ]

    override init() {
        neonColor = BoidNode.palette.randomElement()!
        let speed = CGFloat.random(in: 8...22)
        let angle = CGFloat.random(in: 0...(2 * .pi))
        velocity = CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed)

        halo = SKShapeNode(circleOfRadius: 10)
        halo.fillColor = PlatformColor.white.withAlphaComponent(0.06)
        halo.strokeColor = .clear
        halo.zPosition = -1

        core = SKShapeNode(circleOfRadius: 4)
        core.lineWidth = 1
        core.glowWidth = 6

        super.init()
        addChild(halo)
        addChild(core)
        applyStateAppearance()
    }

    required init?(coder: NSCoder) { fatalError() }

    func playDeathAnimation(completion: @escaping () -> Void) {
        removeAllActions()

        // Flash core bright white
        core.fillColor = .white
        core.strokeColor = .white
        core.glowWidth = 22

        // Core: spike up then implode to nothing
        core.run(.sequence([
            .scale(to: 2.2, duration: 0.07),
            .group([.scale(to: 0, duration: 0.20), .fadeOut(withDuration: 0.15)])
        ]))

        // Halo: blooms outward and dissipates
        halo.run(.group([
            .scale(to: 3.5, duration: 0.28),
            .fadeOut(withDuration: 0.28)
        ]))

        run(.wait(forDuration: 0.32)) { [weak self] in
            self?.removeFromParent()
            completion()
        }
    }

    func applyStateAppearance() {
        switch state {
        case .spawning:
            core.fillColor = neonColor
            core.strokeColor = neonColor.withAlphaComponent(0.5)
            core.glowWidth = 4
        case .wandering:
            core.fillColor = neonColor
            core.strokeColor = neonColor.withAlphaComponent(0.5)
            core.glowWidth = 6
            halo.fillColor = PlatformColor.white.withAlphaComponent(0.06)
        case .threatened:
            core.fillColor = .white
            core.strokeColor = PlatformColor(red: 1, green: 0.3, blue: 0.3, alpha: 0.8)
            core.glowWidth = 3
            halo.fillColor = PlatformColor.red.withAlphaComponent(0.08)
        case .safe:
            core.fillColor = neonColor.withAlphaComponent(0.75)
            core.strokeColor = neonColor
            core.glowWidth = 10
            halo.fillColor = neonColor.withAlphaComponent(0.18)
        case .dying:
            break
        }
    }
}

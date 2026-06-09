import SpriteKit

final class SafeZoneNode: SKNode {
    let radius: CGFloat
    let capacity: Int           // Int.max = unlimited (waves 1-3)

    private(set) var occupancy: Int = 0
    var isFull:      Bool { occupancy >= capacity }
    var remaining:   Int  { capacity == Int.max ? Int.max : max(0, capacity - occupancy) }
    var isUnlimited: Bool { capacity == Int.max }

    private let ring:      SKShapeNode
    private let centerLbl: SKLabelNode
    private var wasFull  = false

    // Unlimited zone — waves 1-3
    init(radius: CGFloat) {
        self.radius   = radius
        self.capacity = Int.max
        ring          = SKShapeNode(circleOfRadius: radius)
        centerLbl     = SKLabelNode()
        super.init()
        build()
    }

    // Capacity-limited zone — wave 4+
    init(radius: CGFloat, capacity: Int) {
        self.radius   = radius
        self.capacity = capacity
        ring          = SKShapeNode(circleOfRadius: radius)
        centerLbl     = SKLabelNode()
        super.init()
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Build

    private func build() {
        // Fill disc
        let fill = SKShapeNode(circleOfRadius: radius)
        fill.fillColor   = PlatformColor(red: 0.55, green: 0.10, blue: 0.90, alpha: 0.10)
        fill.strokeColor = .clear
        addChild(fill)

        // Animated ring
        ring.fillColor   = .clear
        ring.strokeColor = PlatformColor(red: 0.70, green: 0.27, blue: 1.00, alpha: 0.70)
        ring.lineWidth   = 2
        ring.glowWidth   = 8
        addChild(ring)
        ring.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.45, duration: 1.4),
            .fadeAlpha(to: 1.00, duration: 1.4)
        ])))

        // Centre label
        centerLbl.fontName               = "Courier-Bold"
        centerLbl.verticalAlignmentMode  = .center
        centerLbl.horizontalAlignmentMode = .center
        centerLbl.zPosition              = 1
        addChild(centerLbl)

        updateDisplay()
    }

    // MARK: - Occupancy

    func resetOccupancy() {
        occupancy = 0
        wasFull   = false
    }

    func incrementOccupancy() {
        occupancy += 1
        if isFull && !wasFull {
            wasFull = true
            playFullEffect()
        }
        updateDisplay()
    }

    func updateDisplay() {
        if isUnlimited {
            centerLbl.text      = "SAFE"
            centerLbl.fontSize  = 11
            centerLbl.fontColor = PlatformColor(red: 0.70, green: 0.27, blue: 1.00, alpha: 0.60)
        } else if isFull {
            centerLbl.text      = "FULL"
            centerLbl.fontSize  = 14
            centerLbl.fontColor = PlatformColor(red: 1, green: 0.18, blue: 0.18, alpha: 0.90)
        } else {
            let rem   = remaining
            let ratio = CGFloat(occupancy) / CGFloat(capacity)
            centerLbl.text     = "\(rem)"
            centerLbl.fontSize = 22
            centerLbl.fontColor = labelColor(for: ratio)
        }
    }

    private func labelColor(for ratio: CGFloat) -> PlatformColor {
        switch ratio {
        case ..<0.33: return PlatformColor(red: 0.00, green: 0.96, blue: 1.00, alpha: 0.80)   // cyan — plenty
        case ..<0.66: return PlatformColor(red: 1.00, green: 0.90, blue: 0.00, alpha: 0.85)   // yellow — filling
        default:      return PlatformColor(red: 1.00, green: 0.45, blue: 0.00, alpha: 0.90)   // orange — almost full
        }
    }

    private func playFullEffect() {
        // Ring flashes red
        ring.removeAllActions()
        ring.strokeColor = PlatformColor(red: 1, green: 0.15, blue: 0.15, alpha: 1)
        ring.glowWidth   = 14
        ring.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.30, duration: 0.35),
            .fadeAlpha(to: 1.00, duration: 0.35)
        ])))

        // Brief shake to signal rejection
        let bump = SKAction.sequence([
            .scale(to: 1.06, duration: 0.07),
            .scale(to: 1.00, duration: 0.07),
        ])
        run(.repeat(bump, count: 3))
    }

    // MARK: - Geometry

    func contains(point: CGPoint) -> Bool {
        position.distance(to: point) < radius
    }
}

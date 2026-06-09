import SpriteKit

// MARK: - Tuning knobs

private enum Config {
    static let boidCount = 50

    // Base speeds — wave scaling adds on top each wave
    static let baseBoidSpeed:      CGFloat = 55
    static let basePredatorSpeed:  CGFloat = 46
    static let minSpeed:           CGFloat = 6
    static let damping:            CGFloat = 0.965

    // Neighbourhood radii
    static let rSeparation: CGFloat = 28
    static let rAlignment:  CGFloat = 55
    static let rCohesion:   CGFloat = 80
    static let rThreat:     CGFloat = 115
    static let rCatch:      CGFloat = 22
    static let rPlayer:     CGFloat = 190

    // Force weights
    static let wSep:    CGFloat = 1.0
    static let wAlign:  CGFloat = 0.6
    static let wCohese: CGFloat = 0.35
    static let wFlee:   CGFloat = 0.7
    static let wPlayer: CGFloat = 3.5
    static let wWander: CGFloat = 0.18
}

// MARK: - GameScene

final class GameScene: SKScene {

    // MARK: Entities
    private var boids:     [BoidNode]      = []
    private var predators: [PredatorNode]  = []
    private var safeZones: [SafeZoneNode]  = []
    private var wormholes: [WormholeNode]  = []

    // MARK: Input
    private var mousePos    = CGPoint.zero
    private var mouseActive = false
    private var mouseRepels = false

    // MARK: Game state
    private enum Phase { case title, playing, waveComplete, gameOver, enteringInitials, scoreboard }
    private var phase             = Phase.title
    private var initialsInput     = ""
    private var initialsLabel:    SKLabelNode?
    private var initialsPanel:    SKNode?
    private var score             = 0
    private var lives             = 3
    private var wave              = 1
    private var waveCompleteGuard      = false
    private var timerFired             = false
    private var wormholeSpawnedThisWave  = false
    private var wormholeRolledThisWave   = false  // 50% chance roll result for this wave

    // MARK: Timer
    private var waveTimeRemaining: Double = 0
    private var waveDurationValue: Double = 0   // stored so we can compute ratio

    // MARK: HUD
    private var scoreLabel:     SKLabelNode!
    private var livesLabel:     SKLabelNode!
    private var waveLabel:      SKLabelNode!
    private var timerLabel:     SKLabelNode!
    private var boidCountLabel: SKLabelNode!

    private var lastTime: TimeInterval?

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = NSColor(red: 0.04, green: 0.00, blue: 0.07, alpha: 1)
        drawGrid()
        showTitleScreen()
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date else { return "  --/--/--" }
        let f = DateFormatter()
        f.dateFormat = "MM/dd/yy"
        return f.string(from: date)
    }

    private func showTitleScreen() {
        phase = .title
        AudioManager.shared.stopBackground()
        AudioManager.shared.startIntro()

        // Ambient drifting boids — no predators, no HUD
        spawnAmbientBoids()

        let panel = SKNode()
        panel.name = "titlePanel"
        panel.zPosition = 40
        addChild(panel)

        // Dim vignette
        let bg = SKShapeNode(rect: CGRect(origin: .zero, size: size))
        bg.fillColor = NSColor.black.withAlphaComponent(0.55)
        bg.strokeColor = .clear
        panel.addChild(bg)

        // Title
        let title = SKLabelNode(text: "PARTICLE")
        title.fontName  = "Courier-Bold"
        title.fontSize  = 72
        title.fontColor = NSColor(red: 1.00, green: 0.18, blue: 0.47, alpha: 1)
        title.position  = CGPoint(x: size.width/2, y: size.height/2 + 60)
        title.horizontalAlignmentMode = .center
        panel.addChild(title)
        title.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.7, duration: 1.2),
            .fadeAlpha(to: 1.0, duration: 1.2)
        ])))

        // Subtitle / tagline
        let sub = SKLabelNode(text: "herd the swarm · escape the predators")
        sub.fontName  = "Courier"
        sub.fontSize  = 16
        sub.fontColor = NSColor(red: 0.00, green: 0.96, blue: 1.00, alpha: 0.70)
        sub.position  = CGPoint(x: size.width/2, y: size.height/2 + 14)
        sub.horizontalAlignmentMode = .center
        panel.addChild(sub)

        // Controls hint
        let ctrl = SKLabelNode(text: "hover to attract   right-click to repel")
        ctrl.fontName  = "Courier"
        ctrl.fontSize  = 13
        ctrl.fontColor = NSColor(red: 0.22, green: 1.00, blue: 0.08, alpha: 0.60)
        ctrl.position  = CGPoint(x: size.width/2, y: size.height/2 - 16)
        ctrl.horizontalAlignmentMode = .center
        panel.addChild(ctrl)

        // Start button
        let btnBg = SKShapeNode(rectOf: CGSize(width: 220, height: 48), cornerRadius: 6)
        btnBg.fillColor   = NSColor(red: 0.55, green: 0.10, blue: 0.90, alpha: 0.25)
        btnBg.strokeColor = NSColor(red: 0.70, green: 0.27, blue: 1.00, alpha: 0.85)
        btnBg.lineWidth   = 2
        btnBg.glowWidth   = 8
        btnBg.position    = CGPoint(x: size.width/2, y: size.height/2 - 78)
        panel.addChild(btnBg)
        btnBg.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.45, duration: 0.6),
            .fadeAlpha(to: 1.00, duration: 0.6)
        ])))

        let btnLabel = SKLabelNode(text: "CLICK TO START")
        btnLabel.fontName  = "Courier-Bold"
        btnLabel.fontSize  = 20
        btnLabel.fontColor = NSColor(red: 0.70, green: 0.27, blue: 1.00, alpha: 1)
        btnLabel.verticalAlignmentMode = .center
        btnLabel.position = .zero
        btnBg.addChild(btnLabel)

        addScrollingScores(to: panel)
    }

    private func addScrollingScores(to panel: SKNode) {
        let entries = ScoreManager.shared.scores
        guard !entries.isEmpty else { return }

        let cx     = size.width / 2
        let bandCY: CGFloat = 108   // centre of the scrolling band
        let bandH:  CGFloat = 130
        let bandW:  CGFloat = size.width - 60
        let rowH:   CGFloat = 24

        // Section header above the band
        let header = SKLabelNode(text: "— HIGH SCORES —")
        header.fontName  = "Courier-Bold"
        header.fontSize  = 12
        header.fontColor = NSColor(red: 0, green: 0.96, blue: 1, alpha: 0.55)
        header.position  = CGPoint(x: cx, y: bandCY + bandH / 2 + 14)
        panel.addChild(header)

        // Crop node clips the scrolling list to the band
        let cropNode = SKCropNode()
        let maskRect = CGRect(x: -bandW / 2, y: -bandH / 2, width: bandW, height: bandH)
        let maskShape = SKShapeNode(rect: maskRect)
        maskShape.fillColor = .white
        cropNode.maskNode = maskShape
        cropNode.position = CGPoint(x: cx, y: bandCY)
        panel.addChild(cropNode)

        // Build content with rows going downward (y=0, -rowH, -2*rowH …)
        let content = SKNode()
        cropNode.addChild(content)

        let colors: [NSColor] = [
            NSColor(red: 1.00, green: 0.90, blue: 0.00, alpha: 1),  // gold   — #1
            NSColor(red: 0.75, green: 0.75, blue: 0.75, alpha: 1),  // silver — #2
            NSColor(red: 1.00, green: 0.55, blue: 0.20, alpha: 1),  // bronze — #3
        ]

        func addRow(_ i: Int, _ entry: ScoreEntry, atY y: CGFloat) {
            let rank    = i + 1
            let init3   = entry.initials.padding(toLength: 3, withPad: " ", startingAt: 0)
            let scoreS  = String(entry.score).leftPad(toLength: 6)
            let dateS   = formatDate(entry.date)
            let text    = "\(String(format: "%2d", rank)).  \(init3)   \(scoreS)   W\(entry.wave)   \(dateS)"
            let lbl = SKLabelNode(text: text)
            lbl.fontName  = "Courier-Bold"
            lbl.fontSize  = 14
            lbl.fontColor = i < colors.count ? colors[i] : NSColor(white: 0.70, alpha: 1)
            lbl.position  = CGPoint(x: 0, y: y)
            content.addChild(lbl)
        }

        // Double the list so the loop is seamless
        let totalListH = CGFloat(entries.count) * rowH
        for rep in 0..<2 {
            let baseY = -CGFloat(rep) * totalListH
            for (i, entry) in entries.enumerated() {
                addRow(i, entry, atY: baseY - CGFloat(i) * rowH)
            }
        }

        // Scroll: start with row-0 at band bottom, move up until list repeats, then loop
        let moveAmt  = totalListH
        let duration = Double(moveAmt) / 28.0   // 28 px/s — comfortable reading pace

        content.position = CGPoint(x: 0, y: -bandH / 2)
        content.run(.sequence([
            .wait(forDuration: 1.0),            // brief pause before scrolling starts
            .repeatForever(.sequence([
                .moveBy(x: 0, y: moveAmt, duration: duration),
                .run { content.position = CGPoint(x: 0, y: -bandH / 2) }
            ]))
        ]))

        // Top and bottom fade overlays (painted over the crop node, outside it)
        let fadeH: CGFloat = 28
        for (sign, offsetY): (CGFloat, CGFloat) in [(1, bandH / 2 - fadeH / 2), (-1, -bandH / 2 + fadeH / 2)] {
            let fade = SKShapeNode(rectOf: CGSize(width: bandW, height: fadeH))
            fade.fillColor  = NSColor(red: 0.04, green: 0, blue: 0.07,
                                      alpha: sign > 0 ? 0.92 : 0.88)
            fade.strokeColor = .clear
            fade.position   = CGPoint(x: cx, y: bandCY + offsetY)
            panel.addChild(fade)
        }
    }

    private func spawnAmbientBoids() {
        let margin: CGFloat = 60
        for _ in 0..<35 {
            let b = BoidNode()
            b.position = CGPoint(
                x: CGFloat.random(in: margin...(size.width  - margin)),
                y: CGFloat.random(in: margin...(size.height - margin))
            )
            b.alpha = 0
            let delay = Double.random(in: 0...2.0)
            b.run(.sequence([.wait(forDuration: delay), .fadeIn(withDuration: 0.8)])) {
                b.state = .wandering
                b.applyStateAppearance()
            }
            boids.append(b)
            addChild(b)
        }
    }

    private func beginGame() {
        // Remove title panel and ambient boids, then set up properly
        childNode(withName: "titlePanel")?.removeFromParent()
        boids.forEach { $0.removeFromParent() }
        boids.removeAll()

        placeSafeZones()
        spawnBoids()
        spawnPredators(1)
        buildHUD()
        resetTimer()
        phase = .playing
        AudioManager.shared.stopBackground()
        AudioManager.shared.startGameplay()
    }

    // MARK: - Wave scaling helpers

    private func waveBoidMaxSpeed() -> CGFloat {
        switch wave {
        case 1:  return Config.baseBoidSpeed        // 55 — floaty intro
        case 2:  return 95                          // big jump
        default: return min(95 + CGFloat(wave - 2) * 16, 320)
        // wave 5≈143  wave 7≈175  wave 10≈223  wave 15≈303
        }
    }
    private func wavePredatorMaxSpeed() -> CGFloat {
        switch wave {
        case 1:  return 75                          // faster than boid max (55) so they can hunt
        case 2:  return 120                         // faster than boid max (95)
        default: return min(120 + CGFloat(wave - 2) * 20, 440)
        // wave 5≈180  wave 7≈220  wave 10≈280  wave 15≈380  (always > boid max)
        }
    }
    private func wavePredatorCount()     -> Int     { 1 + (wave - 1) / 3 }
    private func waveEjectSpeed()        -> CGFloat {
        switch wave {
        case 1:  return 80
        case 2:  return 140
        default: return min(140 + CGFloat(wave - 2) * 12, 260)
        }
    }
    private func waveDuration()          -> Double  { max(90.0 - Double(wave - 1) * 3.0, 40.0) }
    private func safeZoneRadius()        -> CGFloat {
        let shrinks = (wave - 1) / 5
        return max(65 - CGFloat(shrinks) * 7, 38)
    }

    // MARK: - Setup

    private func drawGrid() {
        let step: CGFloat = 56
        let color = NSColor(red: 0.14, green: 0.00, blue: 0.22, alpha: 1)
        let path = CGMutablePath()
        var x: CGFloat = 0
        while x <= size.width  { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += step }
        var y: CGFloat = 0
        while y <= size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += step }
        let grid = SKShapeNode(path: path)
        grid.strokeColor = color
        grid.lineWidth = 0.8
        grid.zPosition = -10
        addChild(grid)
    }

    // Radius scales with capacity: 1 zone = large, 2 = medium, 3 = small
    private func zoneRadius(capacity: Int, base: CGFloat) -> CGFloat {
        guard capacity != Int.max else { return base }
        let ratio = CGFloat(capacity) / CGFloat(Config.boidCount)
        if ratio >= 1.0 { return base }
        if ratio >= 0.5 { return base * 0.85 }
        return base * 0.72
    }

    private func waveZoneCount() -> Int {
        wave <= 3 ? 3 : Int.random(in: 1...3)
    }

    private func waveZoneCapacities(count: Int) -> [Int] {
        guard wave > 3 else { return Array(repeating: Int.max, count: count) }
        let total  = Config.boidCount
        let base   = total / count
        let extra  = total % count
        // distribute remainder so total always >= boidCount
        return (0..<count).map { i in i < extra ? base + 1 : base }
    }

    private func placeSafeZones() {
        let base  = safeZoneRadius()
        let count = waveZoneCount()
        let caps  = waveZoneCapacities(count: count)
        let radii = caps.map { zoneRadius(capacity: $0, base: base) }
        let pts   = safeZonePositions(count: count, radius: radii.max() ?? base)
        for i in 0..<count {
            let r = radii[i]
            let z = caps[i] == Int.max ? SafeZoneNode(radius: r)
                                       : SafeZoneNode(radius: r, capacity: caps[i])
            z.position = pts[i]
            safeZones.append(z)
            addChild(z)
        }
    }

    private func safeZonePositions(count: Int, radius: CGFloat) -> [CGPoint] {
        let m = radius + 45
        switch count {
        case 1:
            return [CGPoint(x: CGFloat.random(in: size.width * 0.3...(size.width * 0.7)),
                            y: CGFloat.random(in: m...(size.height - m)))]
        case 2:
            return [
                CGPoint(x: CGFloat.random(in: m...(size.width * 0.40)),
                        y: CGFloat.random(in: m...(size.height - m))),
                CGPoint(x: CGFloat.random(in: size.width * 0.60...(size.width - m)),
                        y: CGFloat.random(in: m...(size.height - m))),
            ]
        default:
            return [
                CGPoint(x: CGFloat.random(in: m...(size.width * 0.38)),
                        y: CGFloat.random(in: m...(size.height - m))),
                CGPoint(x: CGFloat.random(in: size.width * 0.62...(size.width - m)),
                        y: CGFloat.random(in: m...(size.height - m))),
                CGPoint(x: CGFloat.random(in: size.width * 0.3...(size.width * 0.7)),
                        y: CGFloat.random(in: m...(size.height * 0.45))),
            ]
        }
    }

    private func repositionSafeZones() {
        safeZones.forEach { $0.removeFromParent() }
        safeZones.removeAll()
        let base  = safeZoneRadius()
        let count = waveZoneCount()
        let caps  = waveZoneCapacities(count: count)
        let radii = caps.map { zoneRadius(capacity: $0, base: base) }
        let pts   = safeZonePositions(count: count, radius: radii.max() ?? base)
        for i in 0..<count {
            let r = radii[i]
            let z = caps[i] == Int.max ? SafeZoneNode(radius: r)
                                       : SafeZoneNode(radius: r, capacity: caps[i])
            z.position = pts[i]
            z.alpha = 0
            z.run(.fadeIn(withDuration: 0.7))
            safeZones.append(z)
            addChild(z)
        }
    }

    private func spawnBoids() {
        let margin: CGFloat = 80
        for _ in 0..<Config.boidCount {
            let b = BoidNode()
            b.position = CGPoint(
                x: CGFloat.random(in: margin...(size.width  - margin)),
                y: CGFloat.random(in: margin...(size.height - margin))
            )
            b.alpha = 0
            let delay = Double.random(in: 0...1.8)
            b.run(.sequence([.wait(forDuration: delay), .fadeIn(withDuration: 0.6)])) {
                b.state = .wandering
                b.applyStateAppearance()
            }
            boids.append(b)
            addChild(b)
        }
    }

    private func spawnPredators(_ count: Int) {
        for _ in 0..<count {
            let p = PredatorNode()
            p.position = randomEdgePoint()
            let angle = CGFloat.random(in: 0...(2 * .pi))
            p.velocity = CGVector(dx: cos(angle) * 30, dy: sin(angle) * 30)
            p.alpha = 0
            predators.append(p)
            addChild(p)
            // Fade in over 2s, then ghost for another 2s, then activate
            p.run(.sequence([
                .fadeIn(withDuration: 2.0),
                .wait(forDuration: 2.0),
                .run { p.activate() }
            ]))
        }
    }

    // Triggered mid-wave once half the boids are safe — spawn far from the loose cluster
    private func checkWormholeSpawn() {
        guard wave > 4, wormholeRolledThisWave, !wormholeSpawnedThisWave, phase == .playing else { return }
        let safeCount = boids.filter { $0.state == .safe }.count
        guard safeCount >= Config.boidCount / 2 else { return }

        wormholeSpawnedThisWave = true
        AudioManager.shared.play("wormhole_appear")
        let spawnPt = spawnPointFarFromBoids()

        // Warning pulse at spawn point — 1.5s before the wormhole materialises
        let warning = SKShapeNode(circleOfRadius: WormholeNode.killRadius * 2.5)
        warning.fillColor = .clear
        warning.strokeColor = NSColor(red: 0.8, green: 0, blue: 1, alpha: 0.7)
        warning.lineWidth = 2
        warning.glowWidth = 10
        warning.position = spawnPt
        warning.zPosition = 5
        addChild(warning)
        warning.run(.sequence([
            .repeat(.sequence([
                .scale(to: 1.4, duration: 0.3),
                .scale(to: 0.9, duration: 0.3)
            ]), count: 3),
            .removeFromParent()
        ]))

        // Wormhole fades in after the warning, gravity builds with alpha
        let w = WormholeNode()
        w.position = spawnPt
        w.alpha = 0
        w.run(.sequence([
            .wait(forDuration: 1.5),
            .fadeIn(withDuration: 2.5)
        ]))
        wormholes.append(w)
        addChild(w)
    }

    // Grid-based search: sample the screen in cells, return the point that
    // maximises minimum distance from every living boid AND every safe zone edge.
    private func spawnPointFarFromBoids() -> CGPoint {
        let margin: CGFloat = 120
        let cols = 7, rows = 5
        let liveBoids = boids.filter { $0.state != .dying }

        var bestPoint = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        var bestDist:  CGFloat = 0

        let cellW = (size.width  - margin * 2) / CGFloat(cols)
        let cellH = (size.height - margin * 2) / CGFloat(rows)

        for row in 0..<rows {
            for col in 0..<cols {
                // Two jittered samples per cell for better coverage
                for _ in 0..<2 {
                    let x = margin + (CGFloat(col) + CGFloat.random(in: 0.15...0.85)) * cellW
                    let y = margin + (CGFloat(row) + CGFloat.random(in: 0.15...0.85)) * cellH
                    let pt = CGPoint(x: x, y: y)

                    // Nearest boid
                    var minDist = liveBoids.reduce(CGFloat.greatestFiniteMagnitude) {
                        min($0, pt.distance(to: $1.position))
                    }
                    // Nearest safe zone edge (distance to zone centre minus radius)
                    for z in safeZones {
                        minDist = min(minDist, max(0, pt.distance(to: z.position) - z.radius))
                    }

                    if minDist > bestDist {
                        bestDist = minDist
                        bestPoint = pt
                    }
                }
            }
        }

        return bestPoint
    }

    // MARK: - HUD

    private func buildHUD() {
        let yellow = NSColor(red: 1.00, green: 0.90, blue: 0.00, alpha: 1)
        let pink   = NSColor(red: 1.00, green: 0.18, blue: 0.47, alpha: 1)
        let cyan   = NSColor(red: 0.00, green: 0.96, blue: 1.00, alpha: 1)

        scoreLabel = hudLabel(text: "SCORE: 0",   color: yellow, size: 16)
        scoreLabel.position = CGPoint(x: 14, y: size.height - 28)
        scoreLabel.horizontalAlignmentMode = .left

        livesLabel = hudLabel(text: livesString(), color: pink, size: 16)
        livesLabel.position = CGPoint(x: size.width - 14, y: size.height - 28)
        livesLabel.horizontalAlignmentMode = .right

        waveLabel = hudLabel(text: "WAVE 1", color: cyan, size: 16)
        waveLabel.position = CGPoint(x: size.width / 2, y: size.height - 28)
        waveLabel.horizontalAlignmentMode = .center

        timerLabel = hudLabel(text: "TIME: --", color: cyan, size: 13)
        timerLabel.position = CGPoint(x: size.width / 2, y: size.height - 48)
        timerLabel.horizontalAlignmentMode = .center

        boidCountLabel = hudLabel(text: "SAFE: 0  FREE: \(Config.boidCount)", color: NSColor(red: 0.22, green: 1, blue: 0.08, alpha: 0.85), size: 13)
        boidCountLabel.position = CGPoint(x: 14, y: size.height - 48)
        boidCountLabel.horizontalAlignmentMode = .left

        [scoreLabel, livesLabel, waveLabel, timerLabel, boidCountLabel].forEach { addChild($0!) }
    }

    private func hudLabel(text: String, color: NSColor, size: CGFloat) -> SKLabelNode {
        let l = SKLabelNode(text: text)
        l.fontName = "Courier-Bold"
        l.fontSize = size
        l.fontColor = color
        l.zPosition = 20
        return l
    }

    private func livesString() -> String {
        lives > 0 ? String(repeating: "♦ ", count: lives).trimmingCharacters(in: .whitespaces) : "---"
    }

    private func refreshHUD() {
        scoreLabel.text = "SCORE: \(score)"
        livesLabel.text = livesString()
        waveLabel.text  = "WAVE \(wave)"
    }

    private func refreshBoidCount() {
        let safe = boids.filter { $0.state == .safe }.count
        let free = boids.filter { $0.state == .wandering || $0.state == .threatened }.count
        boidCountLabel.text = "SAFE: \(safe)  FREE: \(free)"
        boidCountLabel.fontColor = free == 0
            ? NSColor(red: 0.7, green: 0.27, blue: 1, alpha: 1)   // purple when all in
            : NSColor(red: 0.22, green: 1, blue: 0.08, alpha: 0.85) // acid green normally
    }

    private func refreshTimer() {
        let secs = Int(ceil(waveTimeRemaining))
        timerLabel.text = secs > 0 ? "TIME: \(secs)" : "TIME: --"
        let ratio = waveDurationValue > 0 ? waveTimeRemaining / waveDurationValue : 1
        if ratio < 0.25 {
            timerLabel.fontColor = NSColor(red: 1, green: 0.18, blue: 0.18, alpha: 1)
        } else if ratio < 0.5 {
            timerLabel.fontColor = NSColor(red: 1, green: 0.55, blue: 0,    alpha: 1)
        } else {
            timerLabel.fontColor = NSColor(red: 0, green: 0.96, blue: 1,    alpha: 1)
        }
    }

    private func resetTimer() {
        waveDurationValue  = waveDuration()
        waveTimeRemaining  = waveDurationValue
        timerFired         = false
        refreshTimer()
    }

    // MARK: - Update

    override func update(_ currentTime: TimeInterval) {
        // Title screen: just drift the ambient boids for atmosphere
        if phase == .title {
            let dt: CGFloat = lastTime.map { CGFloat(min(currentTime - $0, 1/30.0)) } ?? (1/60.0)
            lastTime = currentTime
            boids.forEach { b in
                guard b.state != .dying else { return }
                b.velocity = b.velocity * 0.97
                let wa = CGFloat.random(in: -.pi ... .pi)
                b.velocity = (b.velocity + CGVector(dx: cos(wa), dy: sin(wa)) * 0.25)
                    .clamped(min: 4, max: 40)
                b.position = b.position + b.velocity * dt
                wrap(b)
            }
            return
        }
        guard phase == .playing else { return }

        let dt: CGFloat
        if let last = lastTime {
            dt = CGFloat(min(currentTime - last, 1.0 / 30.0))
        } else {
            dt = CGFloat(1.0 / 60.0)
        }
        lastTime = currentTime

        tickTimer(dt: dt)

        predators.forEach { updatePredator($0, dt: dt) }
        wormholes.forEach  { updateWormhole($0, dt: dt) }
        boids.forEach { b in
            guard b.state != .dying else { return }
            updateBoid(b, dt: dt)
            wrap(b)
        }

        checkSafeZones()
        enforceFullZoneBoundaries()
        checkCatches()
        checkWormholeSpawn()
        checkWormholes()
        checkWaveComplete()
    }

    // MARK: - Timer

    private func tickTimer(dt: CGFloat) {
        guard waveTimeRemaining > 0 else { return }
        waveTimeRemaining -= Double(dt)
        if waveTimeRemaining <= 0 {
            waveTimeRemaining = 0
            if !timerFired {
                timerFired = true
                flashTimesUp()
            }
        }
        refreshTimer()
    }

    private func flashTimesUp() {
        let lbl = addLabel("TIME'S UP!", at: CGPoint(x: size.width/2, y: size.height/2 + 55),
                           font: 28, color: NSColor(red: 1, green: 0.45, blue: 0, alpha: 1), z: 25)
        lbl.run(.sequence([.wait(forDuration: 1.6), .fadeOut(withDuration: 0.4), .removeFromParent()]))
    }

    // MARK: - Boid steering

    private func updateBoid(_ boid: BoidNode, dt: CGFloat) {
        // Catch check first — before position update so fast boids can't slip through
        for pred in predators where pred.isActive {
            if boid.position.distance(to: pred.position) < Config.rCatch {
                devour(boid); return
            }
        }

        // Safe boids settle toward zone centre
        if boid.state == .safe {
            if let zone = safeZones.first(where: { $0.contains(point: boid.position) }) {
                let toCenter = zone.position - boid.position
                boid.velocity = (boid.velocity + toCenter.normalized() * 0.4) * 0.88
            } else {
                boid.velocity = boid.velocity * 0.85
            }
            boid.velocity = boid.velocity.limited(to: 14)
            boid.position = boid.position + boid.velocity * dt
            return
        }

        // Damping drops quickly after wave 1 so boids actually reach higher speeds
        let damping: CGFloat = wave == 1 ? Config.damping : max(0.86, Config.damping - CGFloat(wave - 1) * 0.012)
        boid.velocity = boid.velocity * damping

        var force = CGVector.zero

        // Wander noise
        let wa = CGFloat.random(in: -.pi ... .pi)
        force += CGVector(dx: cos(wa), dy: sin(wa)) * Config.wWander

        let neighbors = boids.filter {
            $0 !== boid && $0.state != .dying &&
            boid.position.distance(to: $0.position) < Config.rCohesion
        }

        // Separation
        var sep = CGVector.zero; var sepN = 0
        for n in neighbors {
            let d = boid.position.distance(to: n.position)
            if d < Config.rSeparation && d > 0 {
                sep += (boid.position - n.position).normalized() * (Config.rSeparation / d)
                sepN += 1
            }
        }
        if sepN > 0 { force += sep.normalized() * Config.wSep }

        // Alignment
        let ap = neighbors.filter { boid.position.distance(to: $0.position) < Config.rAlignment }
        if !ap.isEmpty {
            let n = CGFloat(ap.count)
            let avg = ap.reduce(CGVector.zero) { $0 + $1.velocity }
            force += CGVector(dx: avg.dx/n, dy: avg.dy/n).normalized() * Config.wAlign
        }

        // Cohesion
        if !neighbors.isEmpty {
            let n = CGFloat(neighbors.count)
            let cx = neighbors.reduce(CGFloat(0)) { $0 + $1.position.x } / n
            let cy = neighbors.reduce(CGFloat(0)) { $0 + $1.position.y } / n
            let tc = CGPoint(x: cx, y: cy) - boid.position
            if tc.magnitude > 0 { force += tc.normalized() * Config.wCohese }
        }

        // Flee predators — inactive (ghost) predators don't scare boids
        var threatened = false
        for pred in predators where pred.isActive {
            let d = boid.position.distance(to: pred.position)
            if d < Config.rCatch {
                threatened = true
            } else if d < Config.rThreat {
                force += (boid.position - pred.position).normalized() * Config.wFlee * (1 - d/Config.rThreat)
                threatened = true
            }
        }

        // Wormhole gravity — scales with alpha so danger grows with the fade-in
        for wh in wormholes {
            let d = boid.position.distance(to: wh.position)
            if d < WormholeNode.gravityRadius && d > 0 {
                let s = (1 - d / WormholeNode.gravityRadius)
                force += (wh.position - boid.position).normalized() * WormholeNode.gravityStrength * s * s * wh.alpha
                if wh.alpha > 0.3 { threatened = true }
            }
        }

        // Mouse influence — linear falloff, scaled with wave speed so it
        // always has enough authority to override the flee force
        if mouseActive {
            let tm = mousePos - boid.position
            let d  = tm.magnitude
            if d < Config.rPlayer && d > 0 {
                let s = 1.0 - (d / Config.rPlayer)   // linear, stronger at distance than quadratic was
                let speedScale = sqrt(waveBoidMaxSpeed() / Config.baseBoidSpeed)
                force += (mouseRepels ? -tm.normalized() : tm.normalized()) * Config.wPlayer * s * speedScale
            }
        }

        let prev = boid.state
        boid.state = threatened ? .threatened : .wandering
        // Minimum speed scales with wave — forces boids to actually use the higher caps
        let waveMin: CGFloat = wave == 1 ? Config.minSpeed : waveBoidMaxSpeed() * 0.42
        boid.velocity = (boid.velocity + force).clamped(min: waveMin, max: waveBoidMaxSpeed())
        boid.position = boid.position + boid.velocity * dt
        if boid.state != prev { boid.applyStateAppearance() }
    }

    // MARK: - Predator steering

    private func updatePredator(_ pred: PredatorNode, dt: CGFloat) {
        // Ghost phase — drift slowly, no hunting
        if !pred.isActive {
            pred.velocity = (pred.velocity * 0.98).limited(to: 30)
            pred.position = pred.position + pred.velocity * dt
            wrap(pred)
            return
        }

        // Safe zone repulsion — predators steer around zones, not through them
        var avoidForce = CGVector.zero
        for zone in safeZones {
            let d = pred.position.distance(to: zone.position)
            let avoidR = zone.radius + 38
            if d < avoidR && d > 0 {
                let s = 1.0 - (d / avoidR)
                avoidForce += (pred.position - zone.position).normalized() * 5.5 * s * s
            }
        }

        let targets = boids.filter { $0.state == .wandering || $0.state == .threatened }
        if let target = targets.min(by: {
            $0.position.distance(to: pred.position) < $1.position.distance(to: pred.position)
        }) {
            let predicted = target.position + target.velocity * 0.4
            let steer = (predicted - pred.position).normalized()
            pred.velocity = (pred.velocity * 0.97 + steer * 0.35 + avoidForce).limited(to: wavePredatorMaxSpeed())
            pred.setHunting(pred.position.distance(to: target.position) < 80)
        } else {
            pred.velocity = (pred.velocity * 0.97 + avoidForce).limited(to: wavePredatorMaxSpeed())
        }
        pred.faceDirection(pred.velocity)
        pred.position = pred.position + pred.velocity * dt
        wrap(pred)
    }

    // MARK: - Wormhole update

    private func updateWormhole(_ wh: WormholeNode, dt: CGFloat) {
        wh.position = wh.position + wh.velocity * dt
        wrap(wh)
    }

    // MARK: - Zone / catch / wormhole checks

    private func checkSafeZones() {
        // Pass 1 — recount occupancy from already-safe boids; handle drift-outs
        safeZones.forEach { $0.resetOccupancy() }
        for boid in boids where boid.state == .safe {
            if let zone = safeZones.first(where: { $0.contains(point: boid.position) }) {
                zone.incrementOccupancy()
            } else {
                boid.state = .wandering
                boid.applyStateAppearance()
                refreshBoidCount()
            }
        }

        // Pass 2 — admit new boids only into zones that still have room
        for boid in boids where boid.state == .wandering || boid.state == .threatened {
            if let zone = safeZones.first(where: { $0.contains(point: boid.position) && !$0.isFull }) {
                boid.state = .safe
                boid.applyStateAppearance()
                score += 10
                refreshHUD()
                refreshBoidCount()
                floatScore("+10", at: boid.position)
                AudioManager.shared.play("boid_safe")
                zone.incrementOccupancy()
            }
        }

        safeZones.forEach { $0.updateDisplay() }
    }

    // Hard wall: position-correct any non-safe boid that ended up inside a full zone
    private func enforceFullZoneBoundaries() {
        for boid in boids where boid.state == .wandering || boid.state == .threatened {
            for zone in safeZones where zone.isFull {
                let d = boid.position.distance(to: zone.position)
                guard d < zone.radius else { continue }
                // Push to zone surface
                let outDir: CGVector = d > 0.1
                    ? (boid.position - zone.position).normalized()
                    : CGVector(dx: 1, dy: 0)
                boid.position = zone.position + outDir * (zone.radius + 1)
                // Reflect the inward velocity component so boid bounces away
                let vDot = boid.velocity.dx * outDir.dx + boid.velocity.dy * outDir.dy
                if vDot < 0 {
                    boid.velocity = boid.velocity - outDir * (vDot * 2)
                }
            }
        }
    }

    private func checkCatches() {
        for pred in predators where pred.isActive {
            for boid in boids where boid.state == .wandering || boid.state == .threatened {
                if pred.position.distance(to: boid.position) < Config.rCatch { devour(boid) }
            }
        }
    }

    private func checkWormholes() {
        for wh in wormholes where wh.alpha > 0.7 {   // not lethal while still materialising
            for boid in boids where boid.state == .wandering || boid.state == .threatened {
                if wh.position.distance(to: boid.position) < WormholeNode.killRadius { suckIn(boid) }
            }
        }
    }

    private func checkWaveComplete() {
        guard phase == .playing, !waveCompleteGuard else { return }
        let escapees = boids.filter { $0.state == .wandering || $0.state == .threatened }
        let survivors = boids.filter { $0.state == .safe }
        guard escapees.isEmpty, !survivors.isEmpty else { return }

        waveCompleteGuard = true
        phase = .waveComplete

        let timeBonus     = Int(max(0, waveTimeRemaining)) * 2
        let survivalBonus = survivors.count * 5
        let totalBonus    = timeBonus + survivalBonus
        score += totalBonus
        refreshHUD()

        ragePredators { [weak self] in
            guard let self else { return }
            var msg = "WAVE \(self.wave) CLEAR  +\(totalBonus)"
            if timeBonus > 0 { msg += "  (\(Int(self.waveTimeRemaining))s left)" }
            let lbl = self.addLabel(msg, at: CGPoint(x: self.size.width/2, y: self.size.height/2),
                                    font: 34, color: NSColor(red: 0, green: 0.96, blue: 1, alpha: 1), z: 30)
            lbl.run(.sequence([
                .group([.scale(to: 1.2, duration: 0.2), .fadeAlpha(to: 1, duration: 0.2)]),
                .wait(forDuration: 1.3),
                .group([.scale(to: 0.8, duration: 0.4), .fadeOut(withDuration: 0.4)]),
                .removeFromParent()
            ])) { [weak self] in self?.advanceWave() }
        }
    }

    // MARK: - Wave advance

    private func ragePredators(completion: @escaping () -> Void) {
        guard !predators.isEmpty else { completion(); return }
        AudioManager.shared.play("pred_lose")
        var remaining = predators.count
        for pred in predators {
            pred.velocity = .zero
            pred.playRageExit { remaining -= 1; if remaining == 0 { completion() } }
        }
        predators.removeAll()
    }

    private func advanceWave() {
        wave += 1
        waveCompleteGuard = false
        phase = .playing

        // Eject safe boids — velocity and distance both scale with wave
        let ejectSpeed = waveEjectSpeed()
        for boid in boids where boid.state == .safe {
            if let zone = safeZones.first(where: { $0.contains(point: boid.position) }) {
                let diff   = boid.position - zone.position
                let outDir = diff.magnitude > 0.1
                    ? diff.normalized()
                    : CGVector(dx: CGFloat.random(in: -1...1), dy: CGFloat.random(in: -1...1)).normalized()
                boid.position = zone.position + outDir * (zone.radius + 25)
                boid.velocity = outDir * ejectSpeed
            }
            boid.state = .wandering
            boid.applyStateAppearance()
        }

        // Reposition safe zones every wave (radius shrinks every 5)
        repositionSafeZones()

        // Wave 11+ : 50% chance wormhole appears mid-wave
        if wave > 4 {
            wormholes.forEach { $0.removeFromParent() }
            wormholes.removeAll()
            wormholeSpawnedThisWave  = false
            wormholeRolledThisWave   = Bool.random()   // coin flip each wave
        }

        spawnPredators(wavePredatorCount())
        resetTimer()
        refreshHUD()
    }

    // MARK: - Kill handlers

    private func devour(_ boid: BoidNode) {
        boid.state = .dying
        lives = max(lives - 1, 0)
        refreshHUD(); refreshBoidCount()
        AudioManager.shared.play("boid_dead")

        let pos   = boid.position
        let color = boid.neonColor
        spawnDeathExplosion(at: pos, color: color)

        boid.playDeathAnimation { [weak self] in
            self?.boids.removeAll { $0 === boid }
            if self?.lives == 0 { self?.endGame() }
        }
    }

    private func spawnDeathExplosion(at pos: CGPoint, color: NSColor) {
        // Primary shockwave ring
        let ring = SKShapeNode(circleOfRadius: 5)
        ring.fillColor  = .clear
        ring.strokeColor = color
        ring.lineWidth  = 1.5
        ring.glowWidth  = 8
        ring.position   = pos
        ring.zPosition  = 20
        addChild(ring)
        ring.run(.sequence([
            .group([.scale(to: 5.5, duration: 0.40), .fadeOut(withDuration: 0.40)]),
            .removeFromParent()
        ]))

        // Secondary white ring — slight delay so it reads as two pulses
        let ring2 = SKShapeNode(circleOfRadius: 4)
        ring2.fillColor  = .clear
        ring2.strokeColor = NSColor.white.withAlphaComponent(0.75)
        ring2.lineWidth  = 1
        ring2.glowWidth  = 4
        ring2.position   = pos
        ring2.zPosition  = 20
        addChild(ring2)
        ring2.run(.sequence([
            .wait(forDuration: 0.07),
            .group([.scale(to: 3.5, duration: 0.28), .fadeOut(withDuration: 0.28)]),
            .removeFromParent()
        ]))

        // Sparks flying outward
        let sparkColors: [NSColor] = [
            color,
            color.withAlphaComponent(0.6),
            NSColor(red: 1, green: 0.55, blue: 0, alpha: 1),
            .white,
        ]
        for i in 0..<10 {
            let angle = CGFloat(i) / 10 * .pi * 2 + CGFloat.random(in: -0.3...0.3)
            let speed = CGFloat.random(in: 38...110)
            let spark = SKShapeNode(circleOfRadius: CGFloat.random(in: 1.2...2.8))
            spark.fillColor  = sparkColors.randomElement()!
            spark.strokeColor = .clear
            spark.glowWidth  = 4
            spark.position   = pos
            spark.zPosition  = 20
            addChild(spark)
            let dur = Double.random(in: 0.28...0.55)
            spark.run(.sequence([
                .group([
                    .moveBy(x: cos(angle) * speed, y: sin(angle) * speed, duration: dur),
                    .sequence([
                        .wait(forDuration: dur * 0.35),
                        .group([.fadeOut(withDuration: dur * 0.65),
                                .scale(to: 0.1, duration: dur * 0.65)])
                    ])
                ]),
                .removeFromParent()
            ]))
        }
    }

    private func suckIn(_ boid: BoidNode) {
        boid.state = .dying
        lives = max(lives - 1, 0)
        refreshHUD(); refreshBoidCount()
        AudioManager.shared.play("boid_dead")
        let spiral = SKAction.group([
            .scale(to: 0.1, duration: 0.45),
            .fadeOut(withDuration: 0.45),
            .rotate(byAngle: .pi * 5, duration: 0.45)
        ])
        boid.run(.sequence([spiral, .removeFromParent()])) { [weak self] in
            self?.boids.removeAll { $0 === boid }
            if self?.lives == 0 { self?.endGame() }
        }
    }

    // MARK: - End / restart

    private func endGame() {
        phase = .gameOver
        AudioManager.shared.stopBackground()
        AudioManager.shared.play("gameover")

        let overlay = SKShapeNode(rect: CGRect(origin: .zero, size: size))
        overlay.fillColor = NSColor.black.withAlphaComponent(0.70)
        overlay.strokeColor = .clear
        overlay.zPosition = 50
        overlay.name = "gameOverOverlay"
        addChild(overlay)

        let cx = size.width / 2, cy = size.height / 2
        addLabel("GAME OVER",
                 at: CGPoint(x: cx, y: cy + 60),
                 font: 52, color: NSColor(red: 1, green: 0.18, blue: 0.47, alpha: 1), z: 51)
        addLabel("SCORE: \(score)   WAVE \(wave)",
                 at: CGPoint(x: cx, y: cy + 10),
                 font: 22, color: NSColor(red: 1, green: 0.90, blue: 0, alpha: 1), z: 51)

        // After a moment, slide into initials entry
        run(.sequence([.wait(forDuration: 1.8), .run { [weak self] in self?.showInitialsEntry() }]))
    }

    private func showInitialsEntry() {
        phase = .enteringInitials
        initialsInput = ""

        let cx = size.width / 2, cy = size.height / 2

        let panel = SKNode()
        panel.name = "initialsPanel"
        panel.zPosition = 52
        addChild(panel)
        initialsPanel = panel

        let prompt = SKLabelNode(text: "ENTER YOUR INITIALS")
        prompt.fontName = "Courier-Bold"
        prompt.fontSize = 20
        prompt.fontColor = NSColor(red: 0, green: 0.96, blue: 1, alpha: 1)
        prompt.position = CGPoint(x: cx, y: cy - 40)
        panel.addChild(prompt)

        let hint = SKLabelNode(text: "TYPE UP TO 3 LETTERS  •  BACKSPACE TO DELETE  •  RETURN TO CONFIRM")
        hint.fontName = "Courier"
        hint.fontSize = 11
        hint.fontColor = NSColor(white: 0.55, alpha: 1)
        hint.position = CGPoint(x: cx, y: cy - 100)
        panel.addChild(hint)

        let slots = SKLabelNode(text: "_ _ _")
        slots.fontName = "Courier-Bold"
        slots.fontSize = 48
        slots.fontColor = NSColor(red: 1, green: 0.18, blue: 0.47, alpha: 1)
        slots.position = CGPoint(x: cx, y: cy - 72)
        slots.name = "initialsSlots"
        panel.addChild(slots)
        initialsLabel = slots

        // Cursor blink on the slots label
        slots.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.4, duration: 0.5),
            .fadeAlpha(to: 1.0, duration: 0.5)
        ])))
    }

    private func confirmInitials() {
        let name = initialsInput.isEmpty ? "AAA" : initialsInput
        ScoreManager.shared.add(initials: name, score: score, wave: wave)
        showScoreboard()
    }

    private func showScoreboard() {
        phase = .scoreboard
        initialsPanel?.removeFromParent()
        initialsPanel = nil

        // Remove old game over overlay
        childNode(withName: "gameOverOverlay")?.removeFromParent()

        let bg = SKShapeNode(rect: CGRect(origin: .zero, size: size))
        bg.fillColor = NSColor(red: 0.04, green: 0, blue: 0.10, alpha: 0.95)
        bg.strokeColor = .clear
        bg.zPosition = 53
        bg.name = "scoreboardBg"
        addChild(bg)

        let cx = size.width / 2
        var y = size.height / 2 + 200

        let title = SKLabelNode(text: "HIGH SCORES")
        title.fontName = "Courier-Bold"
        title.fontSize = 32
        title.fontColor = NSColor(red: 0, green: 0.96, blue: 1, alpha: 1)
        title.position = CGPoint(x: cx, y: y)
        title.zPosition = 54
        addChild(title)
        y -= 50

        let entries = ScoreManager.shared.scores
        for (i, entry) in entries.enumerated() {
            let rank = i + 1
            let isNew = entry.initials == (initialsInput.isEmpty ? "AAA" : initialsInput) &&
                        entry.score == score && entry.wave == wave
            let initPadded  = entry.initials.padding(toLength: 3, withPad: " ", startingAt: 0)
            let scorePadded = String(entry.score).leftPad(toLength: 6)
            let dateS       = formatDate(entry.date)
            let line = "\(String(format: "%2d", rank)).  \(initPadded)   \(scorePadded)   W\(entry.wave)   \(dateS)"
            let lbl = SKLabelNode(text: line)
            lbl.fontName = "Courier-Bold"
            lbl.fontSize = 16
            lbl.fontColor = isNew
                ? NSColor(red: 1, green: 0.90, blue: 0, alpha: 1)
                : NSColor(white: 0.80, alpha: 1)
            lbl.position = CGPoint(x: cx, y: y)
            lbl.zPosition = 54
            addChild(lbl)
            y -= 26
        }

        if entries.isEmpty {
            let lbl = SKLabelNode(text: "NO SCORES YET")
            lbl.fontName = "Courier"
            lbl.fontSize = 16
            lbl.fontColor = NSColor(white: 0.5, alpha: 1)
            lbl.position = CGPoint(x: cx, y: y)
            lbl.zPosition = 54
            addChild(lbl)
        }

        let tap = SKLabelNode(text: "[ CLICK TO PLAY AGAIN ]")
        tap.fontName = "Courier-Bold"
        tap.fontSize = 16
        tap.fontColor = NSColor(red: 0, green: 0.96, blue: 1, alpha: 1)
        tap.position = CGPoint(x: cx, y: size.height / 2 - 200)
        tap.zPosition = 54
        tap.run(.repeatForever(.sequence([.fadeAlpha(to: 0.25, duration: 0.55), .fadeAlpha(to: 1, duration: 0.55)])))
        addChild(tap)
    }

    @discardableResult
    private func addLabel(_ text: String, at pt: CGPoint, font: CGFloat, color: NSColor, z: CGFloat) -> SKLabelNode {
        let l = SKLabelNode(text: text)
        l.fontName = "Courier-Bold"
        l.fontSize = font
        l.fontColor = color
        l.position = pt
        l.zPosition = z
        l.horizontalAlignmentMode = .center
        addChild(l)
        return l
    }

    private func restart() {
        removeAllChildren(); removeAllActions()
        boids.removeAll(); predators.removeAll(); safeZones.removeAll(); wormholes.removeAll()
        score = 0; lives = 3; wave = 1; lastTime = nil
        waveCompleteGuard = false; timerFired = false
        wormholeSpawnedThisWave = false; wormholeRolledThisWave = false
        backgroundColor = NSColor(red: 0.04, green: 0.00, blue: 0.07, alpha: 1)
        drawGrid()
        showTitleScreen()   // back to title between runs
    }

    // MARK: - Helpers

    private func wrap(_ node: SKNode) {
        let m: CGFloat = 30
        if node.position.x < -m             { node.position.x = size.width + m }
        if node.position.x > size.width + m  { node.position.x = -m }
        if node.position.y < -m             { node.position.y = size.height + m }
        if node.position.y > size.height + m { node.position.y = -m }
    }

    private func randomEdgePoint() -> CGPoint {
        switch Int.random(in: 0...3) {
        case 0:  return CGPoint(x: CGFloat.random(in: 0...size.width), y: -20)
        case 1:  return CGPoint(x: CGFloat.random(in: 0...size.width), y: size.height + 20)
        case 2:  return CGPoint(x: -20, y: CGFloat.random(in: 0...size.height))
        default: return CGPoint(x: size.width + 20, y: CGFloat.random(in: 0...size.height))
        }
    }

    private func floatScore(_ text: String, at point: CGPoint) {
        let l = SKLabelNode(text: text)
        l.fontName = "Courier-Bold"
        l.fontSize = 13
        l.fontColor = NSColor(red: 0.70, green: 0.27, blue: 1, alpha: 1)
        l.position = point
        l.zPosition = 20
        addChild(l)
        l.run(.sequence([.group([.moveBy(x: 0, y: 28, duration: 0.65), .fadeOut(withDuration: 0.65)]), .removeFromParent()]))
    }

    // MARK: - Mouse

    override func mouseMoved(with event: NSEvent) {
        mousePos = event.location(in: self)
        mouseActive = true
    }

    override func mouseDown(with event: NSEvent) {
        switch phase {
        case .title:      beginGame(); return
        case .scoreboard: restart();   return
        default: break
        }
        mousePos    = event.location(in: self)
        mouseActive = true
        mouseRepels = false
    }

    override func rightMouseDown(with event: NSEvent) {
        mousePos    = event.location(in: self)
        mouseActive = true
        mouseRepels = true
    }

    override func rightMouseUp(with event: NSEvent) { mouseRepels = false }

    override func mouseDragged(with event: NSEvent) { mousePos = event.location(in: self) }

    // MARK: - Debug keys

    override func keyDown(with event: NSEvent) {
        // Initials entry
        if phase == .enteringInitials {
            let keyCode = event.keyCode
            if keyCode == 51 {  // Backspace
                if !initialsInput.isEmpty { initialsInput.removeLast() }
                updateInitialsDisplay()
            } else if keyCode == 36 || keyCode == 76 {  // Return / Enter
                confirmInitials()
            } else if let ch = event.characters?.first, ch.isLetter, initialsInput.count < 3 {
                initialsInput.append(ch.uppercased().first!)
                updateInitialsDisplay()
                if initialsInput.count == 3 { confirmInitials() }
            }
            return
        }

        guard let ch = event.characters else { return }
        switch ch {
        case "w":   // Win current wave instantly
            debugWinWave()
        case "k":   // Kill a boid (stress test lives)
            if let b = boids.first(where: { $0.state == .wandering }) { devour(b) }
        default:
            break
        }
    }

    private func updateInitialsDisplay() {
        let filled = initialsInput.map { String($0) }
        let slots  = (0..<3).map { i in filled.indices.contains(i) ? filled[i] : "_" }
        initialsLabel?.text = slots.joined(separator: " ")
    }

    private func debugWinWave() {
        guard phase == .playing, !waveCompleteGuard else { return }
        // Scatter all loose boids into safe zones so checkWaveComplete fires naturally
        let loose = boids.filter { $0.state == .wandering || $0.state == .threatened }
        for (i, boid) in loose.enumerated() {
            let zone  = safeZones[i % safeZones.count]
            let angle = CGFloat(i) / CGFloat(max(loose.count, 1)) * 2 * .pi
            let r     = CGFloat.random(in: 5...(zone.radius - 14))
            boid.position = CGPoint(x: zone.position.x + cos(angle) * r,
                                    y: zone.position.y + sin(angle) * r)
            boid.velocity = .zero
        }
        // checkWaveComplete will fire on the next update tick
    }
}

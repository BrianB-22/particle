import SpriteKit

// MARK: - Tuning knobs

private enum Config {
    static let boidCount = 50
    static let showBoidTrails = true

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

    // Feature flags
    static let boidTrails:   Bool = true
    static let devDebugMode: Bool = true   // set false before release

    // Meteor strike
    struct Meteor {
        static let minWave:      Int     = 3
        static let chance:       Double  = 0.30
        static let replaceDelay: Double  = 3.0
        static let speed:        CGFloat = 700
        static let ejectSpeed:   CGFloat = 220
    }

    // Predator aggressiveness — 5 levels, mapped per wave range below
    struct PredatorAggression {
        let speedScale:    CGFloat  // multiplier on wavePredatorMaxSpeed()
        let predictTime:   CGFloat  // seconds ahead to predict target position
        let gracePeriod:   CGFloat  // on-screen seconds before activating
        let steerStrength: CGFloat  // how hard they turn toward target each tick
        let turnDamping:   CGFloat  // velocity damping (lower = snappier turns)

        // steerStrength / (1 - turnDamping) = steady-state speed. All levels use same damping for consistent feel.
        static let level1 = PredatorAggression(speedScale: 0.25, predictTime: 0.10, gracePeriod: 4.5, steerStrength: 0.7,  turnDamping: 0.930)  // SS ~10  — docile
        static let level2 = PredatorAggression(speedScale: 0.38, predictTime: 0.20, gracePeriod: 3.0, steerStrength: 1.4,  turnDamping: 0.930)  // SS ~20  — easy
        static let level3 = PredatorAggression(speedScale: 0.50, predictTime: 0.35, gracePeriod: 2.0, steerStrength: 2.1,  turnDamping: 0.930)  // SS ~30  — normal
        static let level4 = PredatorAggression(speedScale: 0.62, predictTime: 0.45, gracePeriod: 1.0, steerStrength: 2.8,  turnDamping: 0.930)  // SS ~40  — hard
        static let level5 = PredatorAggression(speedScale: 0.75, predictTime: 0.50, gracePeriod: 0.5, steerStrength: 3.5,  turnDamping: 0.930)  // SS ~50  — lethal

        // ── Wave mapping — edit this to tune per-wave aggressiveness ──
        static func forWave(_ wave: Int) -> PredatorAggression {
            switch wave {
            case 1...2:   return .level1
            case 3...4:   return .level2
            case 5...9:   return .level3
            case 10...15: return .level4
            default:      return .level5
            }
        }
    }
}

// MARK: - GameScene

final class GameScene: SKScene {

    // MARK: Entities
    private var boids:     [BoidNode]      = []
    private var predators: [PredatorNode]  = []
    private var safeZones: [SafeZoneNode]  = []
    private var blackHoles: [BlackHoleNode]  = []

    // MARK: Input
    private struct InputState {
        var position: CGPoint = .zero
        var active:   Bool    = false
        var repels:   Bool    = false
    }
    private var input = InputState()

    // MARK: Game state
    private enum Phase { case title, help, playing, waveComplete, gameOver, enteringInitials, scoreboard }
    private var phase             = Phase.title
    private var initialsInput     = ""
    private var initialsLabel:    SKLabelNode?
    private var initialsPanel:    SKNode?
    private var score             = 0
    private var lives             = 3
    private var wave              = 1
    private var nextLifeThreshold = 4000  // bonus life every 4k points
    private var waveCompleteGuard         = false
    private var timerFired                = false
    private var blackHoleSpawnedThisWave  = false
    private var blackHoleRolledThisWave   = false

    // Meteor strike state
    private var meteorFiredThisWave = false
    private var meteorNode:     SKShapeNode? = nil
    private var meteorTarget:   SafeZoneNode? = nil
    private var meteorVelocity: CGVector = .zero
    private var meteorTrailTimer: CGFloat = 0

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
    private var lastKnownSize: CGSize = .zero
    private var sizeScale: CGFloat = 1.0   // size.width / 1180 reference — keeps speeds screen-relative

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        sizeScale = max(0.5, size.width / 1180)
        backgroundColor = PlatformColor(red: 0.04, green: 0.00, blue: 0.07, alpha: 1)
        drawGrid()
        spawnNebulas()
        showTitleScreen()
        lastKnownSize = size
    }

    private func adaptToCurrentSize() {
        sizeScale = max(0.5, size.width / 1180)
        enumerateChildNodes(withName: "grid") { node, _ in node.removeFromParent() }
        drawGrid()
        enumerateChildNodes(withName: "nebula") { node, _ in node.removeFromParent() }
        spawnNebulas()
        if scoreLabel != nil {
            scoreLabel.position     = CGPoint(x: 14,              y: size.height - 28)
            livesLabel.position     = CGPoint(x: size.width - 14, y: size.height - 28)
            waveLabel.position      = CGPoint(x: size.width / 2,  y: size.height - 28)
            timerLabel.position     = CGPoint(x: size.width / 2,  y: size.height - 48)
            boidCountLabel.position = CGPoint(x: 14,              y: size.height - 48)
        }
        if phase == .title { buildTitleUI() }
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
        spawnAmbientBoids()
        spawnPredators(3)
        buildTitleUI()
    }

    private func buildTitleUI() {
        childNode(withName: "titlePanel")?.removeFromParent()

        let panel = SKNode()
        panel.name = "titlePanel"
        panel.zPosition = 40
        addChild(panel)

        // Dim vignette
        let bg = SKShapeNode(rect: CGRect(origin: .zero, size: size))
        bg.fillColor = PlatformColor.black.withAlphaComponent(0.55)
        bg.strokeColor = .clear
        panel.addChild(bg)

        // Title image — load via bundle so SPM and Xcode both work
        #if SWIFT_PACKAGE
        let titleBundle = Bundle.module
        #else
        let titleBundle = Bundle.main
        #endif
        let titleImg: SKSpriteNode
        if let url = titleBundle.url(forResource: "title", withExtension: "png") {
            let tex = SKTexture(imageNamed: url.path)
            titleImg = SKSpriteNode(texture: tex)
            let imgW = min(tex.size().width, size.width * 0.72)
            let s = imgW / tex.size().width
            titleImg.size = CGSize(width: imgW, height: tex.size().height * s)
        } else {
            let lbl = SKLabelNode(text: "PARTICLE")
            lbl.fontName = "Courier-Bold"; lbl.fontSize = 72
            lbl.fontColor = PlatformColor(red: 1.00, green: 0.18, blue: 0.47, alpha: 1)
            lbl.horizontalAlignmentMode = .center
            titleImg = SKSpriteNode()
            panel.addChild(lbl)
            lbl.position = CGPoint(x: size.width / 2, y: size.height / 2 + 50)
        }
        titleImg.position = CGPoint(x: size.width / 2, y: size.height / 2 + 50)
        panel.addChild(titleImg)
        titleImg.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.80, duration: 1.2),
            .fadeAlpha(to: 1.00, duration: 1.2)
        ])))


        // Start button
        let btnBg = SKShapeNode(rectOf: CGSize(width: 220, height: 48), cornerRadius: 6)
        btnBg.fillColor   = PlatformColor(red: 0.55, green: 0.10, blue: 0.90, alpha: 0.25)
        btnBg.strokeColor = PlatformColor(red: 0.70, green: 0.27, blue: 1.00, alpha: 0.85)
        btnBg.lineWidth   = 2
        btnBg.glowWidth   = 8
        let btnOffset = size.height * 0.12   // ~98pt windowed, ~118pt fullscreen
        btnBg.position    = CGPoint(x: size.width/2, y: size.height/2 - btnOffset)
        panel.addChild(btnBg)
        btnBg.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.45, duration: 0.6),
            .fadeAlpha(to: 1.00, duration: 0.6)
        ])))

        let btnLabel = SKLabelNode(text: "CLICK TO START")
        btnLabel.fontName  = "Courier-Bold"
        btnLabel.fontSize  = 20
        btnLabel.fontColor = PlatformColor(red: 0.70, green: 0.27, blue: 1.00, alpha: 1)
        btnLabel.verticalAlignmentMode = .center
        btnLabel.position = .zero
        btnBg.addChild(btnLabel)

        // Help button — bottom-left corner, same style as fullscreen button
        let helpBacking = SKShapeNode(rectOf: CGSize(width: 100, height: 28), cornerRadius: 4)
        helpBacking.name        = "helpBtn"
        helpBacking.fillColor   = PlatformColor(white: 1, alpha: 0.001)
        helpBacking.strokeColor = .clear
        helpBacking.position    = CGPoint(x: 62, y: 20)
        helpBacking.zPosition   = 41
        panel.addChild(helpBacking)

        let helpBtn = SKLabelNode(text: "?  HELP")
        helpBtn.name                   = "helpBtn"
        helpBtn.fontName               = "Courier"
        helpBtn.fontSize               = 12
        helpBtn.fontColor              = PlatformColor(white: 0.50, alpha: 1)
        helpBtn.horizontalAlignmentMode = .center
        helpBtn.verticalAlignmentMode  = .center
        helpBtn.position               = .zero
        helpBacking.addChild(helpBtn)

        #if os(macOS)
        let fsBacking = SKShapeNode(rectOf: CGSize(width: 140, height: 28), cornerRadius: 4)
        fsBacking.name        = "fullscreenBtn"
        fsBacking.fillColor   = PlatformColor(white: 1, alpha: 0.001)
        fsBacking.strokeColor = .clear
        fsBacking.position    = CGPoint(x: size.width - 86, y: 20)
        fsBacking.zPosition   = 41
        panel.addChild(fsBacking)

        let fsBtn = SKLabelNode(text: "⛶  FULLSCREEN  (F)")
        fsBtn.name                   = "fullscreenBtn"
        fsBtn.fontName               = "Courier"
        fsBtn.fontSize               = 12
        fsBtn.fontColor              = PlatformColor(white: 0.50, alpha: 1)
        fsBtn.horizontalAlignmentMode = .center
        fsBtn.verticalAlignmentMode  = .center
        fsBtn.position               = .zero
        fsBacking.addChild(fsBtn)
        #endif

        // Demo badge — above title logo, floating + color flash
        let demo = SKLabelNode(text: "✦  DEMO BUILD  •  FEEDBACK WANTED  ✦")
        demo.fontName               = "Courier-Bold"
        demo.fontSize               = 16
        demo.fontColor              = PlatformColor(red: 0, green: 0.96, blue: 1, alpha: 1)
        demo.horizontalAlignmentMode = .center
        demo.zPosition              = 41
        demo.position               = CGPoint(x: size.width / 2, y: size.height / 2 + size.height * 0.20)
        demo.run(.repeatForever(.sequence([
            .group([
                .sequence([
                    .moveBy(x: 0, y: 6, duration: 1.1),
                    .moveBy(x: 0, y: -6, duration: 1.1)
                ]),
                .sequence([
                    .colorize(with: PlatformColor(red: 1, green: 0.18, blue: 0.87, alpha: 1), colorBlendFactor: 1, duration: 1.1),
                    .colorize(with: PlatformColor(red: 0, green: 0.96, blue: 1, alpha: 1), colorBlendFactor: 1, duration: 1.1)
                ])
            ])
        ])))
        panel.addChild(demo)

        // Version — upper-right corner
        let verLbl = SKLabelNode(text: "v\(gameVersion)")
        verLbl.fontName                = "Courier"
        verLbl.fontSize                = 11
        verLbl.fontColor               = PlatformColor(white: 0.40, alpha: 1)
        verLbl.horizontalAlignmentMode = .right
        verLbl.position                = CGPoint(x: size.width - 10, y: size.height - 20)
        panel.addChild(verLbl)

        addScrollingScores(to: panel)
    }

    private func showHelpScreen() {
        phase = .help

        let panel = SKNode()
        panel.name      = "helpPanel"
        panel.zPosition = 60
        addChild(panel)

        let cardW: CGFloat = 600
        let cardH: CGFloat = 520
        let cx = size.width / 2
        let cy = size.height / 2

        // Card background
        let card = SKShapeNode(rectOf: CGSize(width: cardW, height: cardH), cornerRadius: 12)
        card.fillColor   = PlatformColor(red: 0.04, green: 0.00, blue: 0.10, alpha: 0.97)
        card.strokeColor = PlatformColor(red: 0.00, green: 0.96, blue: 1.00, alpha: 0.60)
        card.lineWidth   = 2
        card.glowWidth   = 10
        card.position    = CGPoint(x: cx, y: cy)
        panel.addChild(card)

        let left = cx - cardW/2 + 36

        func heading(_ text: String, y: CGFloat) {
            let lbl = SKLabelNode(text: text)
            lbl.fontName             = "Courier-Bold"
            lbl.fontSize             = 13
            lbl.fontColor            = PlatformColor(red: 0.00, green: 0.96, blue: 1.00, alpha: 1)
            lbl.horizontalAlignmentMode = .left
            lbl.position             = CGPoint(x: left, y: cy + y)
            panel.addChild(lbl)
        }

        func row(_ text: String, y: CGFloat) {
            let lbl = SKLabelNode(text: text)
            lbl.fontName             = "Courier"
            lbl.fontSize             = 12
            lbl.fontColor            = PlatformColor(white: 0.85, alpha: 1)
            lbl.horizontalAlignmentMode = .left
            lbl.position             = CGPoint(x: left, y: cy + y)
            panel.addChild(lbl)
        }

        // Title
        let title = SKLabelNode(text: "HOW TO PLAY")
        title.fontName               = "Courier-Bold"
        title.fontSize               = 22
        title.fontColor              = PlatformColor(red: 1.00, green: 0.18, blue: 0.47, alpha: 1)
        title.horizontalAlignmentMode = .center
        title.position               = CGPoint(x: cx, y: cy + 222)
        panel.addChild(title)

        heading("GOAL", y: 192)
        row("Guide boids into glowing safe zones before the timer",   y: 172)
        row("runs out. Lose a life when a boid is caught by a",       y: 157)
        row("predator, swallowed by a black hole, or hit by a meteor.",y: 142)

        heading("CONTROLS", y: 114)
        #if os(macOS)
        row("Move mouse       Attract nearby boids toward cursor",  y:  94)
        row("Right-click      Repel boids — scatter predators too", y:  79)
        row("F                Toggle fullscreen (title screen only)",y:  64)
        row("ESC              Quit",                                 y:  49)
        #else
        row("Drag             Attract nearby boids",   y: 94)
        row("Two-finger drag  Repel nearby boids",     y: 79)
        #endif

        heading("BOID TYPES", y: 22)
        row("Small (skittish)   Fast, flee predators early, hard to herd", y:   2)
        row("Normal             Balanced flocking behaviour",               y: -13)
        row("Large (stubborn)   Slow, ignores the flock, wanders alone",    y: -28)

        heading("HAZARDS", y: -55)
        row("Predators    Ghost blue at wave start, activate after grace period.", y:  -75)
        row("             More waves = more predators, faster and smarter.",       y:  -90)
        row("Black holes  Wave 3+  —  gravity pulls boids in and destroys them.",  y: -105)
        row("Meteor       Wave 3+  —  targets your busiest safe zone. Boids",      y: -120)
        row("             scatter and can be re-herded. Zone respawns in 3s.",      y: -135)

        heading("SCORING", y: -160)
        row("+10 per boid saved                        ",                        y: -180)
        row("+10 per second remaining at wave end",                               y: -195)
        row("Extra life every 4,000 points  (max 6 lives)",                       y: -210)

        // GitHub readme link
        let readme = SKLabelNode(text: "github.com/BrianB-22/particle  —  full readme & tips")
        readme.fontName               = "Courier"
        readme.fontSize               = 11
        readme.fontColor              = PlatformColor(red: 0.70, green: 0.27, blue: 1.00, alpha: 0.85)
        readme.horizontalAlignmentMode = .center
        readme.position               = CGPoint(x: cx, y: cy - cardH/2 + 38)
        readme.name                   = "readmeLink"
        panel.addChild(readme)

        // Dismiss hint
        let dismiss = SKLabelNode(text: "CLICK ANYWHERE TO CLOSE")
        dismiss.fontName               = "Courier"
        dismiss.fontSize               = 11
        dismiss.fontColor              = PlatformColor(white: 0.35, alpha: 1)
        dismiss.horizontalAlignmentMode = .center
        dismiss.position               = CGPoint(x: cx, y: cy - cardH/2 + 18)
        panel.addChild(dismiss)

        panel.alpha = 0
        panel.run(.fadeIn(withDuration: 0.18))
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
        header.fontColor = PlatformColor(red: 0, green: 0.96, blue: 1, alpha: 0.55)
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

        let colors: [PlatformColor] = [
            PlatformColor(red: 1.00, green: 0.90, blue: 0.00, alpha: 1),  // gold   — #1
            PlatformColor(red: 0.75, green: 0.75, blue: 0.75, alpha: 1),  // silver — #2
            PlatformColor(red: 1.00, green: 0.55, blue: 0.20, alpha: 1),  // bronze — #3
        ]

        func addRow(_ i: Int, _ entry: ScoreEntry, atY y: CGFloat) {
            let init3   = entry.initials.padding(toLength: 3, withPad: " ", startingAt: 0)
            let scoreS  = String(entry.score).leftPad(toLength: 6)
            let dateS   = formatDate(entry.date)
            let text    = "\(init3)   \(scoreS)   Wave \(entry.wave)   \(dateS)"
            let lbl = SKLabelNode(text: text)
            lbl.fontName  = "Courier-Bold"
            lbl.fontSize  = 14
            lbl.fontColor = i < colors.count ? colors[i] : PlatformColor(white: 0.70, alpha: 1)
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

    }

    private func spawnAmbientBoids(count: Int = 35) {
        let margin: CGFloat = 60
        for _ in 0..<count {
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
        // Remove title panel, ambient boids, and title predators
        childNode(withName: "titlePanel")?.removeFromParent()
        boids.forEach { $0.removeFromParent() }
        boids.removeAll()
        predators.forEach { $0.removeFromParent() }
        predators.removeAll()

        placeSafeZones()
        spawnBoids()
        spawnPredators(1)
        buildHUD()
        resetTimer()
        phase = .playing
        AudioManager.shared.stopBackground()
        AudioManager.shared.startGameplay()
        meteorFiredThisWave = false
        rollMeteor()
    }

    // MARK: - Wave scaling helpers

    private func waveBoidMaxSpeed() -> CGFloat {
        let base: CGFloat
        switch wave {
        case 1:  base = Config.baseBoidSpeed        // 55 — floaty intro
        case 2:  base = 95                          // big jump
        default: base = min(95 + CGFloat(wave - 2) * 16, 320)
        // wave 5≈143  wave 7≈175  wave 10≈223  wave 15≈303
        }
        return base * sizeScale
    }
    private func wavePredatorMaxSpeed() -> CGFloat {
        let base: CGFloat
        switch wave {
        case 1:  base = 75                          // faster than boid max (55) so they can hunt
        case 2:  base = 120                         // faster than boid max (95)
        default: base = min(120 + CGFloat(wave - 2) * 20, 440)
        // wave 5≈180  wave 7≈220  wave 10≈280  wave 15≈380  (always > boid max)
        }
        return base * sizeScale
    }
    private func wavePredatorCount()     -> Int     { 1 + (wave - 1) / 3 }
    private func waveEjectSpeed()        -> CGFloat {
        let base: CGFloat
        switch wave {
        case 1:  base = 80
        case 2:  base = 140
        default: base = min(140 + CGFloat(wave - 2) * 12, 260)
        }
        return base * sizeScale
    }
    private func waveDuration()          -> Double  { max(90.0 - Double(wave - 1) * 3.0, 40.0) }
    private func safeZoneRadius()        -> CGFloat {
        let shrinks = (wave - 1) / 5
        return max(65 - CGFloat(shrinks) * 7, 38)
    }

    // MARK: - Setup

    private func drawGrid() {
        let step: CGFloat = 56
        let color = PlatformColor(red: 0.14, green: 0.00, blue: 0.22, alpha: 1)
        let path = CGMutablePath()
        var x: CGFloat = 0
        while x <= size.width  { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += step }
        var y: CGFloat = 0
        while y <= size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += step }
        let grid = SKShapeNode(path: path)
        grid.name = "grid"
        grid.strokeColor = color
        grid.lineWidth = 0.8
        grid.zPosition = -10
        addChild(grid)
    }

    private func spawnNebulas() {
        let palette: [(CGFloat, CGFloat, CGFloat)] = [
            (0.00, 0.80, 1.00),  // cyan
            (0.55, 0.10, 0.90),  // purple
            (1.00, 0.18, 0.47),  // pink
            (0.22, 1.00, 0.08),  // acid green
        ]
        for i in 0..<6 {
            let color = palette[i % palette.count]
            let radius = CGFloat.random(in: 100...180)

            let effect = SKEffectNode()
            effect.filter = CIFilter(name: "CIGaussianBlur", parameters: ["inputRadius": 60])
            effect.shouldRasterize = true
            effect.zPosition = -5
            effect.position = CGPoint(
                x: CGFloat.random(in: 160...(size.width  - 160)),
                y: CGFloat.random(in: 160...(size.height - 160))
            )
            effect.name = "nebula"

            let circle = SKShapeNode(circleOfRadius: radius)
            circle.fillColor   = PlatformColor(red: color.0, green: color.1, blue: color.2, alpha: 1.0)
            circle.strokeColor = .clear
            effect.addChild(circle)

            let speed: CGFloat = CGFloat.random(in: 14...24)
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let vx = cos(angle) * speed
            let vy = sin(angle) * speed
            effect.userData = ["vx": vx, "vy": vy]

            // Alpha pulse
            let fadeMin = CGFloat.random(in: 0.04...0.06)
            let fadeMax = CGFloat.random(in: 0.08...0.11)
            let fadeDur = Double.random(in: 3.0...5.0)
            effect.alpha = CGFloat.random(in: fadeMin...fadeMax)
            effect.run(.repeatForever(.sequence([
                .fadeAlpha(to: fadeMax, duration: fadeDur),
                .fadeAlpha(to: fadeMin, duration: fadeDur)
            ])))

            // Scale breathe — offsets from fade so they feel independent
            let scaleDur = Double.random(in: 4.0...8.0)
            circle.run(.repeatForever(.sequence([
                .scale(to: CGFloat.random(in: 1.15...1.35), duration: scaleDur),
                .scale(to: CGFloat.random(in: 0.75...0.90), duration: scaleDur)
            ])))

            addChild(effect)
        }
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
            // Fade in over 2s; activation is gated on being visible on-screen (see updatePredator)
            p.run(.fadeIn(withDuration: 2.0))
        }
    }

    // Triggered mid-wave once half the boids are safe — spawn far from the loose cluster
    private func checkBlackHoleSpawn() {
        guard wave > 4, blackHoleRolledThisWave, !blackHoleSpawnedThisWave, phase == .playing else { return }
        let safeCount = boids.filter { $0.state == .safe }.count
        guard safeCount >= Config.boidCount / 2 else { return }

        blackHoleSpawnedThisWave = true
        AudioManager.shared.play("blackhole_appear")
        let spawnPt = spawnPointFarFromBoids()

        // Warning pulse at spawn point — 1.5s before the wormhole materialises
        let warning = SKShapeNode(circleOfRadius: BlackHoleNode.killRadius * 2.5)
        warning.fillColor = .clear
        warning.strokeColor = PlatformColor(red: 0.8, green: 0, blue: 1, alpha: 0.7)
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
        let w = BlackHoleNode()
        w.position = spawnPt
        w.alpha = 0
        w.run(.sequence([
            .wait(forDuration: 1.5),
            .fadeIn(withDuration: 2.5)
        ]))
        blackHoles.append(w)
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
        let yellow = PlatformColor(red: 1.00, green: 0.90, blue: 0.00, alpha: 1)
        let pink   = PlatformColor(red: 1.00, green: 0.18, blue: 0.47, alpha: 1)
        let cyan   = PlatformColor(red: 0.00, green: 0.96, blue: 1.00, alpha: 1)

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

        boidCountLabel = hudLabel(text: "SAFE: 0  FREE: \(Config.boidCount)", color: PlatformColor(red: 0.22, green: 1, blue: 0.08, alpha: 0.85), size: 13)
        boidCountLabel.position = CGPoint(x: 14, y: size.height - 48)
        boidCountLabel.horizontalAlignmentMode = .left

        [scoreLabel, livesLabel, waveLabel, timerLabel, boidCountLabel].forEach { addChild($0!) }
    }

    private func hudLabel(text: String, color: PlatformColor, size: CGFloat) -> SKLabelNode {
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
        checkExtraLife()
    }

    private func checkExtraLife() {
        guard phase == .playing, score >= nextLifeThreshold, lives < 6 else { return }
        lives += 1
        nextLifeThreshold += 4000
        AudioManager.shared.play("extra_player")
        refreshHUD()

        let lbl = addLabel("+1 LIFE", at: CGPoint(x: size.width / 2, y: size.height / 2 + 30),
                           font: 32, color: PlatformColor(red: 0.22, green: 1.00, blue: 0.08, alpha: 1), z: 30)
        lbl.run(.sequence([
            .group([.scale(to: 1.3, duration: 0.2), .fadeAlpha(to: 1, duration: 0.2)]),
            .wait(forDuration: 0.9),
            .group([.scale(to: 0.8, duration: 0.3), .fadeOut(withDuration: 0.3)]),
            .removeFromParent()
        ]))
    }

    private func refreshBoidCount() {
        let safe = boids.filter { $0.state == .safe }.count
        let free = boids.filter { $0.state == .wandering || $0.state == .threatened }.count
        boidCountLabel.text = "SAFE: \(safe)  FREE: \(free)"
        boidCountLabel.fontColor = free == 0
            ? PlatformColor(red: 0.7, green: 0.27, blue: 1, alpha: 1)   // purple when all in
            : PlatformColor(red: 0.22, green: 1, blue: 0.08, alpha: 0.85) // acid green normally
    }

    private func refreshTimer() {
        let secs = Int(ceil(waveTimeRemaining))
        timerLabel.text = secs > 0 ? "TIME: \(secs)" : "TIME: --"
        let ratio = waveDurationValue > 0 ? waveTimeRemaining / waveDurationValue : 1
        if ratio < 0.25 {
            timerLabel.fontColor = PlatformColor(red: 1, green: 0.18, blue: 0.18, alpha: 1)
        } else if ratio < 0.5 {
            timerLabel.fontColor = PlatformColor(red: 1, green: 0.55, blue: 0,    alpha: 1)
        } else {
            timerLabel.fontColor = PlatformColor(red: 0, green: 0.96, blue: 1,    alpha: 1)
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
        // Detect view resize (fullscreen toggle) — more reliable than didChangeSize
        if size.width > 0 && size != lastKnownSize {
            lastKnownSize = size
            adaptToCurrentSize()
        }

        // Title attract screen — full boid/predator simulation, no HUD or scoring
        if phase == .title {
            let dt: CGFloat = lastTime.map { CGFloat(min(currentTime - $0, 1/30.0)) } ?? (1/60.0)
            lastTime = currentTime

            predators.forEach { updatePredator($0, dt: dt) }
            boids.forEach { b in
                guard b.state != .dying else { return }
                updateBoid(b, dt: dt)
                wrap(b)
            }

            // Replenish when the predators have thinned the herd
            let active = boids.filter { $0.state != .dying }.count
            if active <= 10 { spawnAmbientBoids(count: 15) }

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

        // Drift nebula clouds
        enumerateChildNodes(withName: "nebula") { node, _ in
            guard let vx = node.userData?["vx"] as? CGFloat,
                  let vy = node.userData?["vy"] as? CGFloat else { return }
            node.position.x += vx * dt
            node.position.y += vy * dt
            // Bounce off edges
            if node.position.x < 0 || node.position.x > self.size.width  { node.userData?["vx"] = -vx }
            if node.position.y < 0 || node.position.y > self.size.height { node.userData?["vy"] = -vy }
        }

        predators.forEach { updatePredator($0, dt: dt) }
        blackHoles.forEach  { updateBlackHole($0, dt: dt) }
        updateMeteor(dt: dt)
        boids.forEach { b in
            guard b.state != .dying else { return }
            updateBoid(b, dt: dt)
            wrap(b)
        }

        checkSafeZones()
        enforceFullZoneBoundaries()
        checkCatches()
        checkBlackHoleSpawn()
        checkBlackHoles()
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
                           font: 28, color: PlatformColor(red: 1, green: 0.45, blue: 0, alpha: 1), z: 25)
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

        let p = boid.personality

        // Alignment
        let ap = neighbors.filter { boid.position.distance(to: $0.position) < Config.rAlignment }
        if !ap.isEmpty {
            let n = CGFloat(ap.count)
            let avg = ap.reduce(CGVector.zero) { $0 + $1.velocity }
            force += CGVector(dx: avg.dx/n, dy: avg.dy/n).normalized() * Config.wAlign * p.alignmentScale
        }

        // Cohesion
        if !neighbors.isEmpty {
            let n = CGFloat(neighbors.count)
            let cx = neighbors.reduce(CGFloat(0)) { $0 + $1.position.x } / n
            let cy = neighbors.reduce(CGFloat(0)) { $0 + $1.position.y } / n
            let tc = CGPoint(x: cx, y: cy) - boid.position
            if tc.magnitude > 0 { force += tc.normalized() * Config.wCohese * p.cohesionScale }
        }

        // Flee predators — inactive (ghost) predators don't scare boids
        var threatened = false
        for pred in predators where pred.isActive {
            let d = boid.position.distance(to: pred.position)
            if d < Config.rCatch {
                threatened = true
            } else if d < Config.rThreat * p.threatScale {
                force += (boid.position - pred.position).normalized() * Config.wFlee * p.fleeScale * (1 - d / (Config.rThreat * p.threatScale))
                threatened = true
            }
        }

        // Wormhole gravity — scales with alpha so danger grows with the fade-in
        for wh in blackHoles {
            let d = boid.position.distance(to: wh.position)
            if d < BlackHoleNode.gravityRadius && d > 0 {
                let s = (1 - d / BlackHoleNode.gravityRadius)
                force += (wh.position - boid.position).normalized() * BlackHoleNode.gravityStrength * s * s * wh.alpha
                if wh.alpha > 0.3 { threatened = true }
            }
        }

        // Mouse influence — linear falloff, scaled with wave speed so it
        // always has enough authority to override the flee force
        if input.active {
            let tm = input.position - boid.position
            let d  = tm.magnitude
            if d < Config.rPlayer && d > 0 {
                let s = 1.0 - (d / Config.rPlayer)   // linear, stronger at distance than quadratic was
                let speedScale = sqrt(waveBoidMaxSpeed() / Config.baseBoidSpeed)
                force += (input.repels ? -tm.normalized() : tm.normalized()) * Config.wPlayer * s * speedScale
            }
        }

        // Edge avoidance — push boids away from screen edges so they stay visible
        let edgeM: CGFloat = 5
        let edgeStr: CGFloat = 14
        if boid.position.x < edgeM               { force.dx += (edgeM - boid.position.x) * edgeStr }
        if boid.position.x > size.width  - edgeM { force.dx -= (boid.position.x - (size.width  - edgeM)) * edgeStr }
        if boid.position.y < edgeM               { force.dy += (edgeM - boid.position.y) * edgeStr }
        if boid.position.y > size.height - edgeM { force.dy -= (boid.position.y - (size.height - edgeM)) * edgeStr }

        if Config.boidTrails && boid.state != .safe {
            boid.trailTimer += dt
            if boid.trailTimer >= 0.05 {
                boid.trailTimer = 0
                let dot = SKShapeNode(circleOfRadius: 2.5)
                dot.fillColor   = boid.neonColor.withAlphaComponent(0.55)
                dot.strokeColor = .clear
                dot.glowWidth   = 4
                dot.position    = boid.position
                dot.zPosition   = boid.zPosition - 1
                addChild(dot)
                dot.run(.sequence([
                    .fadeOut(withDuration: 0.45),
                    .removeFromParent()
                ]))
            }
        }

        let prev = boid.state
        boid.state = threatened ? .threatened : .wandering
        // Minimum speed scales with wave — forces boids to actually use the higher caps
        let waveMax = waveBoidMaxSpeed() * p.speedScale
        let waveMin: CGFloat = wave == 1 ? Config.minSpeed * sizeScale : waveMax * 0.42
        boid.velocity = (boid.velocity + force).clamped(min: waveMin, max: waveMax)
        if Config.showBoidTrails { spawnTrail(at: boid.position, color: boid.neonColor) }
        boid.position = boid.position + boid.velocity * dt
        if boid.state != prev { boid.applyStateAppearance() }
    }

    private func spawnTrail(at pos: CGPoint, color: PlatformColor) {
        let dot = SKShapeNode(circleOfRadius: 2.2)
        dot.fillColor = color.withAlphaComponent(0.55)
        dot.strokeColor = .clear
        dot.glowWidth = 3
        dot.position = pos
        dot.zPosition = 4
        addChild(dot)
        dot.run(.sequence([
            .group([
                .scale(to: 0.2, duration: 0.35),
                .fadeOut(withDuration: 0.35)
            ]),
            .removeFromParent()
        ]))
    }

    // MARK: - Predator steering

    private func updatePredator(_ pred: PredatorNode, dt: CGFloat) {
        // Ghost phase — drift slowly, no hunting
        if !pred.isActive {
            let onScreen = pred.position.x >= 0 && pred.position.x <= size.width &&
                           pred.position.y >= 0 && pred.position.y <= size.height
            if onScreen {
                pred.velocity = (pred.velocity * 0.98).limited(to: 30 * sizeScale)
                // Only count down once fully faded in
                if pred.alpha >= 0.99 {
                    pred.ghostOnScreenTime += dt
                    let ag = phase == .title ? Config.PredatorAggression.level5 : Config.PredatorAggression.forWave(wave)
                    if pred.ghostOnScreenTime >= ag.gracePeriod {
                        pred.activate()
                        if phase != .title { AudioManager.shared.play("pred_danger") }
                    }
                }
            } else {
                // Steer toward screen center so the predator enters before activating
                let toCenter = CGVector(dx: size.width / 2 - pred.position.x,
                                        dy: size.height / 2 - pred.position.y).normalized() * (80 * sizeScale)
                pred.velocity = (pred.velocity + toCenter * dt).limited(to: 60 * sizeScale)
            }
            pred.position = pred.position + pred.velocity * dt
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

        let ag = phase == .title ? Config.PredatorAggression.level5 : Config.PredatorAggression.forWave(wave)
        let topSpeed = wavePredatorMaxSpeed() * ag.speedScale

        let targets = boids.filter { $0.state == .wandering || $0.state == .threatened }
        if let target = targets.min(by: {
            $0.position.distance(to: pred.position) < $1.position.distance(to: pred.position)
        }) {
            let predicted = target.position + target.velocity * ag.predictTime
            let steer = (predicted - pred.position).normalized()
            pred.velocity = (pred.velocity * ag.turnDamping + steer * ag.steerStrength * sizeScale + avoidForce).limited(to: topSpeed)
            pred.setHunting(pred.position.distance(to: target.position) < 80)
        } else {
            pred.velocity = (pred.velocity * ag.turnDamping + avoidForce).limited(to: topSpeed)
        }
        pred.faceDirection(pred.velocity)
        pred.position = pred.position + pred.velocity * dt
        wrap(pred)
    }

    // MARK: - Wormhole update

    private func updateBlackHole(_ wh: BlackHoleNode, dt: CGFloat) {
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

    private func checkBlackHoles() {
        for wh in blackHoles where wh.alpha > 0.7 {   // not lethal while still materialising
            for boid in boids where boid.state == .wandering || boid.state == .threatened {
                if wh.position.distance(to: boid.position) < BlackHoleNode.killRadius { suckIn(boid) }
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

        let timeBonus     = Int(max(0, waveTimeRemaining)) * 10
        let survivalBonus = survivors.count * 5
        let totalBonus    = timeBonus + survivalBonus
        score += totalBonus
        refreshHUD()

        ragePredators { [weak self] in
            guard let self else { return }
            var msg = "WAVE \(self.wave) CLEAR  +\(totalBonus)"
            if timeBonus > 0 { msg += "  (\(Int(self.waveTimeRemaining))s left)" }
            let lbl = self.addLabel(msg, at: CGPoint(x: self.size.width/2, y: self.size.height/2),
                                    font: 34, color: PlatformColor(red: 0, green: 0.96, blue: 1, alpha: 1), z: 30)
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
            blackHoles.forEach { $0.removeFromParent() }
            blackHoles.removeAll()
            blackHoleSpawnedThisWave  = false
            blackHoleRolledThisWave   = Bool.random()   // coin flip each wave
        }

        spawnPredators(wavePredatorCount())
        resetTimer()
        refreshHUD()

        // Cancel any in-flight meteor and roll for this wave
        removeAction(forKey: "meteorDelay")
        meteorNode?.removeFromParent(); meteorNode = nil; meteorTarget = nil
        meteorFiredThisWave = false
        rollMeteor()
    }

    // MARK: - Meteor strike

    private func rollMeteor() {
        guard wave >= Config.Meteor.minWave, !meteorFiredThisWave else { return }
        guard Double.random(in: 0...1) < Config.Meteor.chance else { return }
        let delay = Double.random(in: 6...18)
        run(.sequence([
            .wait(forDuration: delay),
            .run { [weak self] in
                guard let self, self.phase == .playing else { return }
                self.launchMeteorAtBestZone()
            }
        ]), withKey: "meteorDelay")
    }

    private func forceMeteor() {
        removeAction(forKey: "meteorDelay")
        launchMeteorAtBestZone()
    }

    private func launchMeteorAtBestZone() {
        guard meteorNode == nil else { return }
        // Target zone with most boids (even if empty — per design)
        guard let target = safeZones.max(by: { $0.occupancy < $1.occupancy }) else { return }
        launchMeteor(at: target)
    }

    private func launchMeteor(at target: SafeZoneNode) {
        meteorFiredThisWave = true
        meteorTarget = target

        // Sound fires before the meteor is visible
        AudioManager.shared.play("meteor_inbound")

        run(.sequence([
            .wait(forDuration: 0.55),
            .run { [weak self] in
                guard let self, let tgt = self.meteorTarget else { return }
                let start = self.randomEdgePoint()
                let head = SKShapeNode(circleOfRadius: 12)
                head.fillColor   = PlatformColor(red: 1.0, green: 0.65, blue: 0.10, alpha: 1)
                head.strokeColor = PlatformColor(red: 1.0, green: 0.90, blue: 0.55, alpha: 1)
                head.lineWidth   = 2
                head.glowWidth   = 20
                head.position    = start
                head.zPosition   = 25
                self.addChild(head)
                self.meteorNode = head
                let diff = CGVector(dx: tgt.position.x - start.x, dy: tgt.position.y - start.y)
                self.meteorVelocity = diff.normalized() * (Config.Meteor.speed * self.sizeScale)
            }
        ]))
    }

    private func updateMeteor(dt: CGFloat) {
        guard let meteor = meteorNode, let target = meteorTarget else { return }

        meteor.position = meteor.position + meteorVelocity * dt

        // Burning sparkle trail — two layers at different intervals
        meteorTrailTimer += dt
        if meteorTrailTimer >= 0.012 {
            meteorTrailTimer = 0

            // Hot white/orange core ember
            let ember = SKShapeNode(circleOfRadius: CGFloat.random(in: 1.5...3.5))
            ember.fillColor   = Bool.random()
                ? PlatformColor(red: 1.0, green: 0.95, blue: 0.70, alpha: 1.0)   // white-hot
                : PlatformColor(red: 1.0, green: 0.55, blue: 0.05, alpha: 0.95)  // deep orange
            ember.strokeColor = .clear
            ember.glowWidth   = 6
            // Slight perpendicular scatter so trail has width
            let perp = CGVector(dx: -meteorVelocity.dy, dy: meteorVelocity.dx).normalized()
            let scatter = CGFloat.random(in: -5...5)
            ember.position  = CGPoint(x: meteor.position.x + perp.dx * scatter,
                                      y: meteor.position.y + perp.dy * scatter)
            ember.zPosition = 24
            addChild(ember)
            ember.run(.sequence([
                .group([.scale(to: 0.05, duration: 0.22), .fadeOut(withDuration: 0.22)]),
                .removeFromParent()
            ]))

            // Occasional larger glow blob for the burn haze
            if Int.random(in: 0...3) == 0 {
                let blob = SKShapeNode(circleOfRadius: CGFloat.random(in: 5...9))
                blob.fillColor   = PlatformColor(red: 1.0, green: 0.45, blue: 0.05, alpha: 0.35)
                blob.strokeColor = .clear
                blob.glowWidth   = 12
                blob.position    = meteor.position
                blob.zPosition   = 23
                addChild(blob)
                blob.run(.sequence([
                    .group([.scale(to: 1.6, duration: 0.28), .fadeOut(withDuration: 0.28)]),
                    .removeFromParent()
                ]))
            }
        }

        if meteor.position.distance(to: target.position) < 25 {
            triggerMeteorImpact()
        }
    }

    private func triggerMeteorImpact() {
        guard let meteor = meteorNode, let target = meteorTarget else { return }
        let impactPos = target.position

        meteor.removeFromParent()
        meteorNode = nil
        meteorTarget = nil

        AudioManager.shared.play("meteor_explosion")

        // Small hot flash at the core
        let flash = SKShapeNode(circleOfRadius: 18)
        flash.fillColor   = PlatformColor(red: 1.0, green: 0.90, blue: 0.60, alpha: 0.95)
        flash.strokeColor = .clear
        flash.glowWidth   = 18
        flash.position    = impactPos
        flash.zPosition   = 32
        addChild(flash)
        flash.run(.sequence([
            .group([.scale(to: 2.2, duration: 0.15), .fadeOut(withDuration: 0.15)]),
            .removeFromParent()
        ]))

        // Two compact neon rings
        let neonRings: [(PlatformColor, CGFloat, Double)] = [
            (PlatformColor(red: 0.00, green: 0.96, blue: 1.00, alpha: 1), target.radius * 1.6 / 8, 0.45),
            (PlatformColor(red: 1.00, green: 0.18, blue: 0.47, alpha: 1), target.radius * 1.0 / 8, 0.30),
        ]
        for (color, scale, dur) in neonRings {
            let r = SKShapeNode(circleOfRadius: 8)
            r.fillColor   = .clear
            r.strokeColor = color
            r.lineWidth   = 2.5
            r.glowWidth   = 8
            r.position    = impactPos
            r.zPosition   = 31
            addChild(r)
            r.run(.sequence([
                .group([.scale(to: scale, duration: dur), .fadeOut(withDuration: dur)]),
                .removeFromParent()
            ]))
        }

        // Small neon sparkles — short range, tight cluster
        let sparkColors: [PlatformColor] = [
            PlatformColor(red: 0.00, green: 0.96, blue: 1.00, alpha: 1),
            PlatformColor(red: 1.00, green: 0.18, blue: 0.47, alpha: 1),
            PlatformColor(red: 0.22, green: 1.00, blue: 0.08, alpha: 1),
            PlatformColor(red: 0.70, green: 0.27, blue: 1.00, alpha: 1),
            PlatformColor(red: 1.00, green: 0.90, blue: 0.40, alpha: 1),
        ]
        for _ in 0..<14 {
            let spark = SKShapeNode(circleOfRadius: CGFloat.random(in: 1.5...3.0))
            spark.fillColor   = sparkColors.randomElement()!
            spark.strokeColor = .clear
            spark.glowWidth   = 6
            spark.position    = impactPos
            spark.zPosition   = 31
            addChild(spark)
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let dist  = CGFloat.random(in: 15...65)
            let dest  = CGPoint(x: impactPos.x + cos(angle) * dist, y: impactPos.y + sin(angle) * dist)
            let dur   = Double.random(in: 0.25...0.50)
            spark.run(.sequence([
                .group([.move(to: dest, duration: dur), .fadeOut(withDuration: dur), .scale(to: 0.1, duration: dur)]),
                .removeFromParent()
            ]))
        }

        // Eject boids with outward velocity burst
        for boid in boids where boid.state == .safe {
            guard boid.position.distance(to: impactPos) < target.radius + 30 else { continue }
            boid.state = .wandering
            boid.applyStateAppearance()
            let dir: CGVector = boid.position.distance(to: impactPos) > 1
                ? (boid.position - impactPos).normalized()
                : CGVector(dx: CGFloat.random(in: -1...1), dy: CGFloat.random(in: -1...1)).normalized()
            boid.velocity = dir * CGFloat.random(in: (Config.Meteor.ejectSpeed * sizeScale)...(Config.Meteor.ejectSpeed * sizeScale * 1.4))
        }

        // Remove the struck zone
        if let idx = safeZones.firstIndex(of: target) { safeZones.remove(at: idx) }
        target.removeFromParent()
        refreshBoidCount()

        // Spawn replacement zone after delay
        run(.sequence([
            .wait(forDuration: Config.Meteor.replaceDelay),
            .run { [weak self] in self?.spawnMeteorReplacementZone() }
        ]))
    }

    private func spawnMeteorReplacementZone() {
        guard phase == .playing else { return }
        let r   = safeZoneRadius()
        let cap = wave > 3 ? Config.boidCount / max(safeZones.count + 1, 1) : Int.max
        let zone = cap == Int.max ? SafeZoneNode(radius: r) : SafeZoneNode(radius: r, capacity: cap)

        // Place away from predators
        let margin: CGFloat = r + 60
        let minPredDist: CGFloat = 160
        var pos = CGPoint(x: size.width / 2, y: size.height / 2)
        for _ in 0..<30 {
            let candidate = CGPoint(
                x: CGFloat.random(in: margin...(size.width  - margin)),
                y: CGFloat.random(in: margin...(size.height - margin))
            )
            if !predators.contains(where: { $0.position.distance(to: candidate) < minPredDist }) {
                pos = candidate; break
            }
        }

        zone.position = pos
        zone.alpha    = 0
        zone.setScale(0.1)
        zone.run(.group([.scale(to: 1.0, duration: 0.5), .fadeIn(withDuration: 0.5)]))
        safeZones.append(zone)
        addChild(zone)
        refreshBoidCount()
    }

    // MARK: - Kill handlers

    private func devour(_ boid: BoidNode) {
        boid.state = .dying
        if phase != .title { AudioManager.shared.play("boid_dead") }

        let pos   = boid.position
        let color = boid.neonColor
        spawnDeathExplosion(at: pos, color: color)

        // Title screen — no lives, no HUD, no game-over
        if phase == .title {
            boid.playDeathAnimation { [weak self] in
                self?.boids.removeAll { $0 === boid }
            }
            return
        }

        lives = max(lives - 1, 0)
        refreshHUD(); refreshBoidCount()

        boid.playDeathAnimation { [weak self] in
            self?.boids.removeAll { $0 === boid }
            if self?.lives == 0 { self?.endGame() }
        }
    }

    private func spawnDeathExplosion(at pos: CGPoint, color: PlatformColor) {
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
        ring2.strokeColor = PlatformColor.white.withAlphaComponent(0.75)
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
        let sparkColors: [PlatformColor] = [
            color,
            color.withAlphaComponent(0.6),
            PlatformColor(red: 1, green: 0.55, blue: 0, alpha: 1),
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
        overlay.fillColor = PlatformColor.black.withAlphaComponent(0.70)
        overlay.strokeColor = .clear
        overlay.zPosition = 50
        overlay.name = "gameOverOverlay"
        addChild(overlay)

        let cx = size.width / 2, cy = size.height / 2
        addLabel("GAME OVER",
                 at: CGPoint(x: cx, y: cy + 60),
                 font: 52, color: PlatformColor(red: 1, green: 0.18, blue: 0.47, alpha: 1), z: 51)
        addLabel("SCORE: \(score)   WAVE \(wave)",
                 at: CGPoint(x: cx, y: cy + 10),
                 font: 22, color: PlatformColor(red: 1, green: 0.90, blue: 0, alpha: 1), z: 51)

        // After a moment, go to initials entry only if score qualifies for the leaderboard
        run(.sequence([.wait(forDuration: 1.8), .run { [weak self] in
            guard let self else { return }
            if ScoreManager.shared.qualifies(score: self.score) {
                self.showInitialsEntry()
            } else {
                self.showScoreboard()
            }
        }]))
    }

    private func showInitialsEntry() {
        phase = .enteringInitials
        initialsInput = ""

        #if os(iOS)
        // Use a system alert for initials entry on iPad/iPhone
        let alert = UIAlertController(title: "ENTER INITIALS", message: nil, preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "AAA"
            tf.autocapitalizationType = .allCharacters
            tf.returnKeyType = .done
        }
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self, weak alert] _ in
            let raw = alert?.textFields?.first?.text ?? ""
            self?.initialsInput = String(raw.uppercased().prefix(3))
            self?.confirmInitials()
        })
        let vc = view?.window?.rootViewController
        vc?.present(alert, animated: true)
        #else
        let cx = size.width / 2, cy = size.height / 2

        let panel = SKNode()
        panel.name = "initialsPanel"
        panel.zPosition = 52
        addChild(panel)
        initialsPanel = panel

        let prompt = SKLabelNode(text: "ENTER YOUR INITIALS")
        prompt.fontName = "Courier-Bold"
        prompt.fontSize = 20
        prompt.fontColor = PlatformColor(red: 0, green: 0.96, blue: 1, alpha: 1)
        prompt.position = CGPoint(x: cx, y: cy - 40)
        panel.addChild(prompt)

        let hint = SKLabelNode(text: "TYPE UP TO 3 LETTERS  •  BACKSPACE TO DELETE  •  RETURN TO CONFIRM")
        hint.fontName = "Courier"
        hint.fontSize = 11
        hint.fontColor = PlatformColor(white: 0.55, alpha: 1)
        hint.position = CGPoint(x: cx, y: cy - 100)
        panel.addChild(hint)

        let slots = SKLabelNode(text: "_ _ _")
        slots.fontName = "Courier-Bold"
        slots.fontSize = 48
        slots.fontColor = PlatformColor(red: 1, green: 0.18, blue: 0.47, alpha: 1)
        slots.position = CGPoint(x: cx, y: cy - 72)
        slots.name = "initialsSlots"
        panel.addChild(slots)
        initialsLabel = slots

        slots.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.4, duration: 0.5),
            .fadeAlpha(to: 1.0, duration: 0.5)
        ])))
        #endif
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
        bg.fillColor = PlatformColor(red: 0.04, green: 0, blue: 0.10, alpha: 0.95)
        bg.strokeColor = .clear
        bg.zPosition = 53
        bg.name = "scoreboardBg"
        addChild(bg)

        let cx = size.width / 2
        var y = size.height / 2 + 200

        let title = SKLabelNode(text: "HIGH SCORES")
        title.fontName = "Courier-Bold"
        title.fontSize = 32
        title.fontColor = PlatformColor(red: 0, green: 0.96, blue: 1, alpha: 1)
        title.position = CGPoint(x: cx, y: y)
        title.zPosition = 54
        addChild(title)
        y -= 50

        let entries = ScoreManager.shared.scores
        for (_, entry) in entries.enumerated() {
            let isNew = entry.initials == (initialsInput.isEmpty ? "AAA" : initialsInput) &&
                        entry.score == score && entry.wave == wave
            let initPadded  = entry.initials.padding(toLength: 3, withPad: " ", startingAt: 0)
            let scorePadded = String(entry.score).leftPad(toLength: 6)
            let dateS       = formatDate(entry.date)
            let line = "\(initPadded)   \(scorePadded)   Wave \(entry.wave)   \(dateS)"
            let lbl = SKLabelNode(text: line)
            lbl.fontName = "Courier-Bold"
            lbl.fontSize = 16
            lbl.fontColor = isNew
                ? PlatformColor(red: 1, green: 0.90, blue: 0, alpha: 1)
                : PlatformColor(white: 0.80, alpha: 1)
            lbl.position = CGPoint(x: cx, y: y)
            lbl.zPosition = 54
            addChild(lbl)
            y -= 26
        }

        if entries.isEmpty {
            let lbl = SKLabelNode(text: "NO SCORES YET")
            lbl.fontName = "Courier"
            lbl.fontSize = 16
            lbl.fontColor = PlatformColor(white: 0.5, alpha: 1)
            lbl.position = CGPoint(x: cx, y: y)
            lbl.zPosition = 54
            addChild(lbl)
        }

        let tap = SKLabelNode(text: "[ CLICK TO PLAY AGAIN ]")
        tap.fontName = "Courier-Bold"
        tap.fontSize = 16
        tap.fontColor = PlatformColor(red: 0, green: 0.96, blue: 1, alpha: 1)
        tap.position = CGPoint(x: cx, y: size.height / 2 - 200)
        tap.zPosition = 54
        tap.run(.repeatForever(.sequence([.fadeAlpha(to: 0.25, duration: 0.55), .fadeAlpha(to: 1, duration: 0.55)])))
        addChild(tap)

        let feedback = SKLabelNode(text: "[ PROVIDE FEEDBACK ]")
        feedback.fontName = "Courier"
        feedback.fontSize = 13
        feedback.fontColor = PlatformColor(red: 1, green: 0.65, blue: 0, alpha: 0.75)
        feedback.position = CGPoint(x: cx, y: size.height / 2 - 228)
        feedback.zPosition = 54
        feedback.name = "feedbackBtn"
        addChild(feedback)
    }

    @discardableResult
    private func addLabel(_ text: String, at pt: CGPoint, font: CGFloat, color: PlatformColor, z: CGFloat) -> SKLabelNode {
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
        boids.removeAll(); predators.removeAll(); safeZones.removeAll(); blackHoles.removeAll()
        score = 0; lives = 3; wave = 1; lastTime = nil; nextLifeThreshold = 4000
        waveCompleteGuard = false; timerFired = false
        blackHoleSpawnedThisWave = false; blackHoleRolledThisWave = false
        meteorFiredThisWave = false; meteorNode = nil; meteorTarget = nil
        backgroundColor = PlatformColor(red: 0.04, green: 0.00, blue: 0.07, alpha: 1)
        drawGrid()
        spawnNebulas()
        showTitleScreen()   // back to title between runs
    }

    // MARK: - Helpers

    private func wrap(_ node: SKNode) {
        if node.position.x < 0            { node.position.x = size.width }
        if node.position.x > size.width   { node.position.x = 0 }
        if node.position.y < 0            { node.position.y = size.height }
        if node.position.y > size.height  { node.position.y = 0 }
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
        l.fontColor = PlatformColor(red: 0.70, green: 0.27, blue: 1, alpha: 1)
        l.position = point
        l.zPosition = 20
        addChild(l)
        l.run(.sequence([.group([.moveBy(x: 0, y: 28, duration: 0.65), .fadeOut(withDuration: 0.65)]), .removeFromParent()]))
    }

    // MARK: - Input (macOS)

    #if os(macOS)
    override func mouseMoved(with event: NSEvent) {
        input.position = event.location(in: self)
        input.active   = true
    }

    override func mouseDown(with event: NSEvent) {
        switch phase {
        case .title:
            let loc = event.location(in: self)
            if nodes(at: loc).contains(where: { $0.name == "helpBtn" }) {
                showHelpScreen(); return
            }
            if nodes(at: loc).contains(where: { $0.name == "fullscreenBtn" }) {
                view?.window?.toggleFullScreen(nil); return
            }
            beginGame(); return
        case .help:
            #if os(macOS)
            if nodes(at: event.location(in: self)).contains(where: { $0.name == "readmeLink" }) {
                if let url = URL(string: "https://github.com/BrianB-22/particle") {
                    NSWorkspace.shared.open(url)
                }
                return
            }
            #endif
            childNode(withName: "helpPanel")?.run(.sequence([.fadeOut(withDuration: 0.15), .removeFromParent()]))
            phase = .title; return
        case .scoreboard:
            if nodes(at: event.location(in: self)).contains(where: { $0.name == "feedbackBtn" }) {
                #if os(macOS)
                if let url = URL(string: "https://tally.so/r/ODEWrM") {
                    NSWorkspace.shared.open(url)
                }
                #endif
                return
            }
            restart(); return
        default: break
        }
        input.position = event.location(in: self)
        input.active   = true
        input.repels   = false
    }

    override func rightMouseDown(with event: NSEvent) {
        input.position = event.location(in: self)
        input.active   = true
        input.repels   = true
    }

    override func rightMouseUp(with event: NSEvent)  { input.repels = false }
    override func mouseDragged(with event: NSEvent)  { input.position = event.location(in: self) }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc — quit prompt
            let alert = NSAlert()
            alert.messageText = "Quit PARTICLE?"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Quit")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                NSApp.terminate(nil)
            }
            return
        }
        if event.keyCode == 3, phase == .title { // F key — only from title screen
            view?.window?.toggleFullScreen(nil); return
        }
        if phase == .enteringInitials {
            let keyCode = event.keyCode
            if keyCode == 51 {
                if !initialsInput.isEmpty { initialsInput.removeLast() }
                updateInitialsDisplay()
            } else if keyCode == 36 || keyCode == 76 {
                confirmInitials()
            } else if let ch = event.characters?.first, ch.isLetter, initialsInput.count < 3 {
                initialsInput.append(ch.uppercased().first!)
                updateInitialsDisplay()
                if initialsInput.count == 3 { confirmInitials() }
            }
            return
        }
        if Config.devDebugMode, phase == .playing, let ch = event.characters {
            switch ch {
            case "w": debugWinWave()
            case "k": if let b = boids.first(where: { $0.state == .wandering }) { devour(b) }
            case "m": forceMeteor()
            default:  break
            }
        }
    }
    #endif

    // MARK: - Input (iOS)

    #if os(iOS)
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let loc = touch.location(in: self)
        switch phase {
        case .title:
            if nodes(at: loc).contains(where: { $0.name == "helpBtn" }) {
                showHelpScreen(); return
            }
            beginGame(); return
        case .help:
            childNode(withName: "helpPanel")?.run(.sequence([.fadeOut(withDuration: 0.15), .removeFromParent()]))
            phase = .title; return
        case .scoreboard: restart(); return
        default: break
        }
        input.position = loc
        input.active   = true
        input.repels   = touches.count > 1   // two fingers = repel
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        input.position = touch.location(in: self)
        input.repels   = touches.count > 1
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if touches.count <= 1 { input.active = false; input.repels = false }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        input.active = false; input.repels = false
    }
    #endif

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

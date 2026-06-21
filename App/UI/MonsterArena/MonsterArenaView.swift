import SwiftUI

// MARK: - Arena Engine (60fps game loop)

private let PIXEL: CGFloat = 3       // points per "pixel"
private let SPRITE_W: CGFloat = 12 * PIXEL
private let SPRITE_H: CGFloat = 16 * PIXEL
private let GRAVITY:  CGFloat = 0.45
private let FLOOR:    CGFloat = 0    // y=0 is the floor in game units (top=positive)
private let MAX_MONSTERS = 10

final class ArenaEngine: ObservableObject {
    @Published var monsters: [MonsterState] = []

    private var timer: Timer?
    var arenaW: CGFloat = 520
    var arenaH: CGFloat = 180

    func start() {
        // Spawn 2 to start the party
        spawnMonster(); spawnMonster()
        let t = Timer(timeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() { timer?.invalidate(); timer = nil }

    func spawnMonster() {
        guard monsters.count < MAX_MONSTERS else { return }
        let x = CGFloat.random(in: SPRITE_W...(arenaW - SPRITE_W))
        var m = MonsterState.spawn(at: x, dna: .random())
        m.y = 0
        // give new monster a little entrance jump
        m.vy = CGFloat.random(in: 3...5)
        monsters.append(m)
    }

    private func tick() {
        let dt: CGFloat = 1.0/60.0
        for i in monsters.indices {
            updateMonster(&monsters[i], dt: dt)
        }
        resolveCollisions()
    }

    private func updateMonster(_ m: inout MonsterState, dt: CGFloat) {
        // Physics
        m.vy -= GRAVITY
        m.x  += m.vx
        m.y  += m.vy

        // Floor
        if m.y <= 0 {
            m.y = 0
            if m.vy < 0 { m.vy = 0 }
            if m.action == .jump { m.action = .walk; m.actionTimer = Double.random(in: 0.8...2.0) }
        }

        // Walls
        if m.x < SPRITE_W / 2 {
            m.x = SPRITE_W / 2; m.vx = abs(m.vx)
            m.facingRight = true
        } else if m.x > arenaW - SPRITE_W / 2 {
            m.x = arenaW - SPRITE_W / 2; m.vx = -abs(m.vx)
            m.facingRight = false
        }

        // Action timer
        m.actionTimer -= dt
        if m.actionTimer <= 0 { nextAction(&m) }

        // Walk animation
        m.frameTimer -= dt
        if m.frameTimer <= 0 {
            m.animFrame = 1 - m.animFrame
            m.frameTimer = 0.15
        }

        // Attack swings: a quick x-velocity burst
        if m.action == .attack {
            m.vx = m.facingRight ? 2.5 : -2.5
        }
    }

    private func nextAction(_ m: inout MonsterState) {
        let roll = Int.random(in: 0...4)
        switch roll {
        case 0:  // jump
            if m.y == 0 { m.vy = CGFloat.random(in: 5...8); m.action = .jump }
            m.actionTimer = 1.0
        case 1:  // turn
            m.facingRight.toggle()
            m.vx = m.facingRight ? 0.8 : -0.8
            m.action = .walk
            m.actionTimer = Double.random(in: 0.6...2.0)
        case 2:  // idle
            m.vx = 0
            m.action = .idle
            m.actionTimer = Double.random(in: 0.4...1.2)
        case 3:  // attack lunge
            m.action = .attack
            m.actionTimer = 0.35
        default: // walk
            m.vx = m.facingRight ? CGFloat.random(in: 0.5...1.2) : -CGFloat.random(in: 0.5...1.2)
            m.action = .walk
            m.actionTimer = Double.random(in: 1.0...2.5)
        }
    }

    private func resolveCollisions() {
        for i in monsters.indices {
            for j in monsters.indices where j > i {
                let dx = abs(monsters[i].x - monsters[j].x)
                let dy = abs(monsters[i].y - monsters[j].y)
                if dx < SPRITE_W * 0.8 && dy < SPRITE_H * 0.6 {
                    // Bounce apart
                    let dir: CGFloat = monsters[i].x < monsters[j].x ? -1 : 1
                    monsters[i].vx += dir * 2
                    monsters[j].vx -= dir * 2
                    // Both jump
                    if monsters[i].y == 0 { monsters[i].vy = CGFloat.random(in: 3...6) }
                    if monsters[j].y == 0 { monsters[j].vy = CGFloat.random(in: 3...6) }
                    // Victory pose for the "attacker"
                    if monsters[i].action == .attack { monsters[i].action = .victory; monsters[i].actionTimer = 0.5 }
                    if monsters[j].action == .attack { monsters[j].action = .victory; monsters[j].actionTimer = 0.5 }
                }
            }
        }
    }
}

// MARK: - Canvas Sprite Renderer

private func drawMonster(_ m: MonsterState, in ctx: GraphicsContext, floorY: CGFloat) {
    let grid = MonsterSprites.grid(class_: m.dna.class_, frame: m.animFrame)
    let px = PIXEL * m.dna.scale

    // Bob offset when walking/attacking
    let bobY: CGFloat = (m.action == .walk || m.action == .attack) && m.y == 0
        ? (m.animFrame == 0 ? -1 : 0) : 0

    // Screen coordinates: origin at bottom-left of arena, y flipped
    let screenX = m.x - (SPRITE_W * m.dna.scale) / 2
    let screenY = floorY - SPRITE_H * m.dna.scale - m.y * PIXEL + bobY

    // Victory bounce
    let victoryY: CGFloat = m.action == .victory ? -3 : 0

    for (row, rowData) in grid.enumerated() {
        for (col, role) in rowData.enumerated() {
            guard role != 0, let color = m.dna.color(role: role) else { continue }
            var drawCol = col
            if !m.facingRight {
                drawCol = (grid[row].count - 1) - col
            }
            let rect = CGRect(
                x: screenX + CGFloat(drawCol) * px,
                y: screenY + CGFloat(row) * px + victoryY,
                width: px, height: px
            )
            ctx.fill(Path(rect), with: .color(color))
        }
    }

    // Class badge (tiny text above head)
    var text = Text(m.dna.class_.rawValue)
        .font(.system(size: 7, weight: .semibold, design: .monospaced))
    var resolved = ctx.resolve(text.foregroundStyle(Color(white: 0.4)))
    ctx.draw(resolved, at: CGPoint(x: m.x, y: screenY - 3), anchor: .bottom)
}

// MARK: - Arena View

struct MonsterArenaView: View {
    @StateObject private var engine = ArenaEngine()
    @State private var arenaSize: CGSize = .zero

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Arena canvas
            Canvas { ctx, size in
                let floorY = size.height - 14  // 14pt floor gutter

                // Floor line
                let floorPath = Path { p in
                    p.move(to: .init(x: 0, y: floorY))
                    p.addLine(to: .init(x: size.width, y: floorY))
                }
                ctx.stroke(floorPath, with: .color(.init(white: 0.80)), lineWidth: 0.5)

                // Ground grass texture (alternating dark/light dashes)
                for x in stride(from: 0, to: size.width, by: 6) {
                    let h = CGFloat.random(in: 2...5)  // deterministic via seed? Use x as seed
                    let grassH = (sin(x * 0.37) + 1) * 2.5 + 1
                    ctx.fill(
                        Path(CGRect(x: x, y: floorY, width: 2, height: grassH)),
                        with: .color(Color(hue: 0.33, saturation: 0.45, brightness: 0.62).opacity(0.5))
                    )
                }

                // Draw each monster
                for monster in engine.monsters {
                    drawMonster(monster, in: ctx, floorY: floorY)
                }
            }
            .background(
                ZStack {
                    // Sky gradient (faint)
                    LinearGradient(
                        colors: [
                            Color(hue: 0.61, saturation: 0.08, brightness: 0.99),
                            Color(hue: 0.61, saturation: 0.04, brightness: 0.97),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                    // Subtle pixel-art clouds (static decoration)
                    pixelClouds
                }
            )
            .contentShape(Rectangle())
            .onTapGesture { engine.spawnMonster() }
            .onAppear {
                engine.arenaW = 520; engine.arenaH = 180
                engine.start()
            }
            .onDisappear { engine.stop() }
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Spawn hint
            if engine.monsters.isEmpty {
                Text("tap to summon monsters")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(8)
            } else {
                Text("tap to spawn · \(engine.monsters.count)/\(MAX_MONSTERS)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color(white: 0.55))
                    .padding(6)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 196)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(white: 0.82), lineWidth: 0.5)
        )
    }

    // MARK: - Static pixel clouds
    private var pixelClouds: some View {
        Canvas { ctx, size in
            let clouds: [(CGFloat, CGFloat, CGFloat)] = [
                (80, 24, 1.0), (230, 18, 0.8), (380, 30, 1.2), (480, 20, 0.9)
            ]
            for (cx, cy, scale) in clouds {
                let w = 20 * scale * PIXEL; let h = 8 * PIXEL * scale
                ctx.fill(
                    Path(roundedRect: CGRect(x: cx - w/2, y: cy, width: w, height: h), cornerRadius: 4),
                    with: .color(.white.opacity(0.7))
                )
            }
        }
    }
}

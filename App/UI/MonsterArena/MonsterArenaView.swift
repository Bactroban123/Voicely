import SwiftUI

// MARK: - Constants
private let PIXEL: CGFloat = 3
private let SPRITE_W: CGFloat = 12 * PIXEL
private let SPRITE_H: CGFloat = 16 * PIXEL
private let GRAVITY:  CGFloat = 0.55
private let MAX_MONSTERS = 10
private let AGGRO_RANGE: CGFloat = 260
private let ATTACK_RANGE: CGFloat = SPRITE_W * 1.3
private let KO_DURATION: Double = 3.5
private let HP_MAX = 3

// MARK: - Blood Particle
private struct BloodParticle: Identifiable {
    let id = UUID()
    var x, y, vx, vy: CGFloat
    var life: CGFloat        // remaining seconds
    let maxLife: CGFloat
    let color: Color
    let size: CGFloat
    var bounced = false
}

// MARK: - Impact Flash
private struct ImpactFlash: Identifiable {
    let id = UUID()
    var x, y: CGFloat
    var life: CGFloat        // 0→1 fades out
}

// MARK: - Blood colours
private let bloodColors: [Color] = [
    Color(red: 0.82, green: 0.02, blue: 0.06),
    Color(red: 0.68, green: 0.01, blue: 0.04),
    Color(red: 0.50, green: 0.00, blue: 0.02),
    Color(red: 0.38, green: 0.00, blue: 0.01),
]

// MARK: - Arena Engine

fileprivate final class ArenaEngine: ObservableObject {
    @Published var monsters: [MonsterState] = []
    @Published var blood:    [BloodParticle] = []
    @Published var impacts:  [ImpactFlash]   = []

    var arenaW: CGFloat = 520
    var arenaH: CGFloat = 200
    private var timer: Timer?

    // MARK: Lifecycle
    func start() {
        spawnMonster(); spawnMonster(); spawnMonster()
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
        monsters.append(.spawn(at: x, dna: .random()))
    }

    // MARK: Tick
    private func tick() {
        let dt = 1.0 / 60.0
        updateMonsters(dt)
        updateBlood(dt: dt)
        updateImpacts(dt: dt)
        checkHits()
        // Prune dead blood
        blood.removeAll { $0.life <= 0 }
        impacts.removeAll { $0.life <= 0 }
        // Respawn KO'd monsters
        for i in monsters.indices where monsters[i].action == .ko {
            if monsters[i].koTimer >= KO_DURATION {
                respawn(&monsters[i])
            }
        }
    }

    // MARK: Monster update
    private func updateMonsters(_ dt: Double) {
        for i in monsters.indices {
            var m = monsters[i]

            // Cooldowns
            if m.hitCooldown > 0 { m.hitCooldown -= dt }
            if m.actionTimer  > 0 { m.actionTimer  -= dt }

            // KO state: lie flat, spin out
            if m.action == .ko {
                m.koTimer += dt
                m.koRotation += m.vx * 1.5  // spin proportional to velocity
                m.vx *= 0.92                 // friction
                m.vy -= GRAVITY
                m.x  += m.vx
                m.y  += m.vy
                if m.y <= 0 { m.y = 0; m.vy = 0 }
                m.x = max(SPRITE_W/2, min(arenaW - SPRITE_W/2, m.x))
                monsters[i] = m
                continue
            }

            // AI: find target
            let nearestId = nearestEnemy(to: m)
            m.targetId = nearestId

            // Decide action
            if m.action != .hurt {
                if let tid = nearestId, m.action != .attack {
                    let tx = monsters.first(where: { $0.id == tid })?.x ?? m.x
                    let dist = abs(m.x - tx)
                    if dist < ATTACK_RANGE {
                        if m.action != .attack {
                            enterAttack(&m)
                        }
                    } else if dist < AGGRO_RANGE {
                        enterSeek(&m, toward: tx)
                    }
                }
                if m.actionTimer <= 0 && m.action != .seek && m.action != .attack {
                    nextIdleAction(&m)
                }
            } else {
                // hurt: recover
                if m.actionTimer <= 0 {
                    m.action = .walk
                    m.vx = m.facingRight ? 0.7 : -0.7
                    m.actionTimer = 0.8
                }
            }

            // Physics
            m.vy -= GRAVITY
            m.x  += m.vx
            m.y  += m.vy

            // Floor
            if m.y <= 0 {
                m.y = 0
                if m.vy < -1 { m.vy = 0 }
                else { m.vy = 0 }
                if m.action == .jump { m.action = .walk; m.actionTimer = 1 }
            }

            // Walls
            if m.x < SPRITE_W / 2 {
                m.x = SPRITE_W / 2; m.vx = abs(m.vx)
                m.facingRight = true
                if m.action == .seek { m.action = .walk; m.actionTimer = 0.5 }
            } else if m.x > arenaW - SPRITE_W / 2 {
                m.x = arenaW - SPRITE_W / 2; m.vx = -abs(m.vx)
                m.facingRight = false
                if m.action == .seek { m.action = .walk; m.actionTimer = 0.5 }
            }

            // Walk animation frame
            m.frameTimer -= dt
            if m.frameTimer <= 0 {
                m.animFrame = 1 - m.animFrame
                m.frameTimer = m.action == .seek || m.action == .attack ? 0.08 : 0.15
            }

            monsters[i] = m
        }
    }

    private func enterSeek(_ m: inout MonsterState, toward tx: CGFloat) {
        m.action = .seek
        let dir: CGFloat = tx > m.x ? 1 : -1
        m.vx = dir * 1.8
        m.facingRight = dir > 0
        m.actionTimer = 0.4
    }

    private func enterAttack(_ m: inout MonsterState) {
        m.action = .attack
        m.vx = m.facingRight ? 3.5 : -3.5
        m.actionTimer = 0.3
        if m.y == 0 { m.vy = 2.5 }  // tiny hop during lunge
    }

    private func nextIdleAction(_ m: inout MonsterState) {
        switch Int.random(in: 0...3) {
        case 0:
            if m.y == 0 { m.vy = CGFloat.random(in: 5...9); m.action = .jump }
            m.actionTimer = 1.2
        case 1:
            m.facingRight.toggle()
            m.vx = m.facingRight ? 0.7 : -0.7
            m.action = .walk; m.actionTimer = Double.random(in: 0.6...1.8)
        case 2:
            m.vx = 0; m.action = .idle; m.actionTimer = Double.random(in: 0.3...1.0)
        default:
            m.vx = m.facingRight ? CGFloat.random(in: 0.5...1.2) : -CGFloat.random(in: 0.5...1.2)
            m.action = .walk; m.actionTimer = Double.random(in: 0.8...2.0)
        }
    }

    // MARK: Hit detection
    private func checkHits() {
        for i in monsters.indices where monsters[i].action == .attack {
            let attacker = monsters[i]
            // Weapon zone: 1.5×SPRITE_W ahead of attacker
            let weaponX = attacker.facingRight
                ? attacker.x + SPRITE_W * 0.5
                : attacker.x - SPRITE_W * 0.5

            for j in monsters.indices where j != i {
                var defender = monsters[j]
                guard defender.action != .ko,
                      defender.hitCooldown <= 0 else { continue }

                let dist = abs(weaponX - defender.x)
                let dyOk = abs(attacker.y - defender.y) < SPRITE_H * 0.8

                if dist < SPRITE_W * 0.9 && dyOk {
                    // LAND A HIT
                    let hitX = (attacker.x + defender.x) / 2
                    let hitY = max(attacker.y, defender.y) + SPRITE_H * 0.4

                    spawnBlood(at: hitX, screenY: hitY)
                    impacts.append(ImpactFlash(x: hitX, y: hitY, life: 1.0))

                    // Knockback
                    let kbDir: CGFloat = attacker.facingRight ? 1 : -1
                    defender.vx = kbDir * CGFloat.random(in: 4...7)
                    defender.vy = CGFloat.random(in: 2...5)
                    defender.hitCooldown = 0.6
                    defender.hp -= 1

                    if defender.hp <= 0 {
                        // KO
                        defender.action = .ko
                        defender.koTimer = 0
                        defender.vx = kbDir * 8
                        defender.vy = 6
                        // Victory for attacker
                        monsters[i].action = .victory
                        monsters[i].actionTimer = 1.2
                        monsters[i].vx = 0
                        // Extra blood on KO
                        for _ in 0..<6 { spawnBlood(at: hitX, screenY: hitY) }
                    } else {
                        defender.action = .hurt
                        defender.actionTimer = 0.45
                    }
                    monsters[j] = defender
                }
            }
        }
    }

    // MARK: Blood
    private func spawnBlood(at x: CGFloat, screenY: CGFloat) {
        let count = Int.random(in: 7...14)
        for _ in 0..<count {
            let angle = CGFloat.random(in: -.pi ... 0)  // spray upward
            let speed = CGFloat.random(in: 1.5...6.0)
            blood.append(BloodParticle(
                x: x + CGFloat.random(in: -4...4),
                y: screenY,
                vx: cos(angle) * speed,
                vy: sin(angle) * speed,
                life: CGFloat.random(in: 2.0...4.5),
                maxLife: 4.5,
                color: bloodColors.randomElement()!,
                size: CGFloat.random(in: PIXEL * 0.5 ... PIXEL * 1.5)
            ))
        }
    }

    private func updateBlood(dt: Double) {
        let floorY = arenaH - 14  // floor in screen coords
        for i in blood.indices {
            blood[i].x  += blood[i].vx
            blood[i].vy -= 0.35          // gravity
            blood[i].y  += blood[i].vy
            blood[i].vx *= 0.97          // friction

            // Bounce off floor once
            let screenY = floorY - blood[i].y
            if screenY >= floorY && !blood[i].bounced {
                blood[i].y  = 0
                blood[i].vy = abs(blood[i].vy) * 0.3
                blood[i].vx *= 0.6
                blood[i].bounced = true
            }
            blood[i].life -= CGFloat(dt)
        }
    }

    private func updateImpacts(dt: Double) {
        for i in impacts.indices {
            impacts[i].life -= CGFloat(dt) * 6   // fast fade
        }
    }

    // MARK: Respawn
    private func respawn(_ m: inout MonsterState) {
        m.hp = HP_MAX
        m.action = .walk
        m.koTimer = 0
        m.koRotation = 0
        m.hitCooldown = 0.5
        m.vx = Bool.random() ? 0.8 : -0.8
        m.vy = 5
        m.facingRight = Bool.random()
        m.x = CGFloat.random(in: SPRITE_W...(arenaW - SPRITE_W))
        m.y = 0
        m.actionTimer = 1.0
    }

    // MARK: Helpers
    private func nearestEnemy(to m: MonsterState) -> UUID? {
        monsters
            .filter { $0.id != m.id && $0.action != .ko }
            .min(by: { abs($0.x - m.x) < abs($1.x - m.x) })?
            .id
    }
}

// MARK: - Canvas Drawing

private func drawMonster(_ m: MonsterState, in ctx: GraphicsContext, floorY: CGFloat) {
    guard m.action != .ko || m.koTimer < KO_DURATION else { return }
    var ctx = ctx  // mutable copy so we can set opacity

    let grid = MonsterSprites.grid(class_: m.dna.class_, frame: m.animFrame)
    let px = PIXEL * m.dna.scale

    let bobY: CGFloat = (m.action == .walk || m.action == .seek) && m.y == 0
        ? (m.animFrame == 0 ? -1 : 0) : 0
    let screenX = m.x - (SPRITE_W * m.dna.scale) / 2
    let screenY = floorY - SPRITE_H * m.dna.scale - m.y * (PIXEL * 0.5) + bobY

    // Hurt flash: tint white
    let hurtTint = m.action == .hurt ? 0.55 : 0.0
    // KO fade out
    let koAlpha = m.action == .ko ? max(0, 1.0 - m.koTimer / KO_DURATION) : 1.0
    // Hit blink
    let blink = m.hitCooldown > 0 && Int(m.hitCooldown * 10) % 2 == 0

    if blink && m.action == .hurt { return }  // blink effect

    ctx.opacity = koAlpha

    // KO: draw upside-down (rows reversed)
    let drawGrid = m.action == .ko ? grid.reversed() : grid

    for (row, rowData) in drawGrid.enumerated() {
        for (col, role) in rowData.enumerated() {
            guard role != 0 else { continue }
            var drawCol = col
            if !m.facingRight { drawCol = (rowData.count - 1) - col }

            let baseColor = m.dna.color(role: role) ?? .clear
            let finalColor = hurtTint > 0
                ? Color(red: 1 - (1-0.96)*hurtTint, green: 0.15*hurtTint, blue: 0.15*hurtTint).opacity(0.99)
                : baseColor

            ctx.fill(
                Path(CGRect(
                    x: screenX + CGFloat(drawCol) * px,
                    y: screenY + CGFloat(row) * px,
                    width: px, height: px
                )),
                with: .color(finalColor)
            )
        }
    }

    // HP bar (3 squares above head)
    if m.action != .ko {
        let barW: CGFloat = 5; let barH: CGFloat = 4; let gap: CGFloat = 2
        let totalW = CGFloat(HP_MAX) * (barW + gap) - gap
        let barX = m.x - totalW / 2
        let barY = screenY - 8

        for pip in 0..<HP_MAX {
            let filled = pip < m.hp
            let c = filled ? Color(red: 0.85, green: 0.0, blue: 0.05) : Color(white: 0.75)
            ctx.fill(
                Path(CGRect(x: barX + CGFloat(pip) * (barW + gap), y: barY, width: barW, height: barH)),
                with: .color(c)
            )
        }
    }

    // Daze stars when hurt
    if m.action == .hurt {
        let t = m.actionTimer
        for s in 0..<3 {
            let angle = Double(s) * 2.094 + t * 8  // 120° apart, rotating
            let r: CGFloat = 8
            let sx = m.x + cos(angle) * r
            let sy = screenY - 10 + sin(angle) * r * 0.5
            ctx.fill(
                Path(CGRect(x: sx - 2, y: sy - 2, width: 4, height: 4)),
                with: .color(Color(red: 1, green: 0.85, blue: 0))
            )
        }
    }

    // "!" exclamation when first spotting a target and seeking
    if m.action == .seek && m.actionTimer > 0.25 {
        let text = Text("!").font(.system(size: 10, weight: .black))
        let resolved = ctx.resolve(text.foregroundStyle(Color(red: 1, green: 0.25, blue: 0.05)))
        ctx.draw(resolved, at: CGPoint(x: m.x + (m.facingRight ? 10 : -10), y: screenY - 2), anchor: .bottom)
    }

    ctx.opacity = 1.0
}

private func drawBlood(_ b: BloodParticle, in ctx: GraphicsContext, floorY: CGFloat) {
    let alpha = min(1.0, b.life / b.maxLife * 1.4)
    let screenY = floorY - b.y
    ctx.fill(
        Path(CGRect(x: b.x - b.size/2, y: screenY - b.size/2, width: b.size, height: b.size)),
        with: .color(b.color.opacity(alpha))
    )
}

private func drawImpact(_ f: ImpactFlash, in ctx: GraphicsContext, floorY: CGFloat) {
    let a = max(0, f.life)
    let screenY = floorY - 20   // impacts happen above floor
    let r = (1 - f.life) * 20 + 4   // grows outward
    // Star burst: 6 rays
    for k in 0..<6 {
        let angle = Double(k) * .pi / 3
        let ex = f.x + cos(angle) * r
        let ey = screenY + sin(angle) * r * 0.5  // squash vertically
        var p = Path()
        p.move(to: CGPoint(x: f.x, y: screenY))
        p.addLine(to: CGPoint(x: ex, y: ey))
        ctx.stroke(p, with: .color(Color(red: 1, green: 0.85, blue: 0.0).opacity(a)), lineWidth: 2)
    }
    // Center flash
    ctx.fill(
        Path(ellipseIn: CGRect(x: f.x - r*0.4, y: screenY - r*0.2, width: r*0.8, height: r*0.4)),
        with: .color(Color.white.opacity(a))
    )
}

// MARK: - Arena View

struct MonsterArenaView: View {
    @StateObject private var engine = ArenaEngine()

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Canvas { ctx, size in
                let floorY = size.height - 14

                // Sky
                ctx.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(red: 0.92, green: 0.96, blue: 0.99),
                            Color(red: 0.98, green: 0.99, blue: 1.00),
                        ]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: 0, y: size.height)
                    )
                )

                // Pixel clouds
                for (cx, cy, w) in [(CGFloat(80), CGFloat(22), CGFloat(54)),
                                    (220, 14, 46), (370, 26, 60), (490, 18, 40)] {
                    ctx.fill(
                        Path(roundedRect: CGRect(x: cx - w/2, y: cy, width: w, height: 14), cornerRadius: 5),
                        with: .color(.white.opacity(0.75))
                    )
                }

                // Blood splatters (behind everything)
                for b in engine.blood { drawBlood(b, in: ctx, floorY: floorY) }

                // Floor
                ctx.fill(
                    Path(CGRect(x: 0, y: floorY, width: size.width, height: size.height - floorY)),
                    with: .color(Color(red: 0.56, green: 0.42, blue: 0.28))   // dirt
                )
                // Grass strip
                ctx.fill(
                    Path(CGRect(x: 0, y: floorY, width: size.width, height: 4)),
                    with: .color(Color(hue: 0.33, saturation: 0.55, brightness: 0.52))
                )
                // Floor hairline
                ctx.stroke(
                    Path { p in p.move(to: .init(x:0,y:floorY)); p.addLine(to: .init(x:size.width,y:floorY)) },
                    with: .color(Color(white: 0.65)), lineWidth: 0.5
                )

                // Monsters
                for m in engine.monsters {
                    drawMonster(m, in: ctx, floorY: floorY)
                }

                // Impact flashes (on top)
                for f in engine.impacts {
                    drawImpact(f, in: ctx, floorY: floorY)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { engine.spawnMonster() }
            .onAppear {
                engine.arenaW = 520
                engine.arenaH = 200
                engine.start()
            }
            .onDisappear { engine.stop() }
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Counter
            Text(engine.monsters.count < MAX_MONSTERS
                 ? "tap to spawn · \(engine.monsters.count)/\(MAX_MONSTERS)"
                 : "arena full · \(MAX_MONSTERS)/\(MAX_MONSTERS)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Color(white: 0.45))
                .padding(6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 210)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(red: 0.055, green: 0.102, blue: 0.141).opacity(0.12),
                              lineWidth: 0.5)
        )
    }
}

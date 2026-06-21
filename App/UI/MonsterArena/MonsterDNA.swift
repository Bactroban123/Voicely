import SwiftUI

// MARK: - Monster Classes
enum MonsterClass: String, CaseIterable {
    case knight    = "Knight"
    case ninja     = "Ninja"
    case samurai   = "Samurai"
    case dragon    = "Dragon"
    case dinosaur  = "Dino"
    case sifu      = "Sifu"
    case judoka    = "Judoka"
    case anime     = "Anime"
}

// MARK: - Monster DNA
struct MonsterDNA: Identifiable {
    let id: UUID
    let class_: MonsterClass
    let primaryHue: Double
    let accentHue: Double
    let specialHue: Double
    let scale: CGFloat

    static func random() -> MonsterDNA {
        let hue = Double.random(in: 0...1)
        let accent = (hue + Double.random(in: 0.35...0.55)).truncatingRemainder(dividingBy: 1)
        let special = (hue + Double.random(in: 0.15...0.30)).truncatingRemainder(dividingBy: 1)
        return MonsterDNA(
            id: UUID(),
            class_: MonsterClass.allCases.randomElement()!,
            primaryHue: hue,
            accentHue: accent,
            specialHue: special,
            scale: CGFloat.random(in: 0.85...1.15)
        )
    }

    // 1=head  2=body  3=dark  4=white  5=accent  6=weapon(gold)  7=special
    func color(role: Int) -> Color? {
        switch role {
        case 1: return Color(hue: primaryHue, saturation: 0.60, brightness: 0.95)
        case 2: return Color(hue: primaryHue, saturation: 0.72, brightness: 0.78)
        case 3: return Color(hue: primaryHue, saturation: 0.25, brightness: 0.20)
        case 4: return Color(white: 0.96)
        case 5: return Color(hue: accentHue,  saturation: 0.85, brightness: 0.90)
        case 6: return Color(hue: 0.13,       saturation: 0.75, brightness: 0.90)
        case 7: return Color(hue: specialHue, saturation: 0.95, brightness: 1.00)
        default: return nil
        }
    }
}

// MARK: - Monster Action
enum MonsterAction {
    case idle, walk, jump, seek, attack, hurt, ko, victory
}

// MARK: - Monster State
struct MonsterState: Identifiable {
    let id: UUID
    let dna: MonsterDNA
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var facingRight: Bool
    var action: MonsterAction
    var actionTimer: Double
    var animFrame: Int
    var frameTimer: Double

    // Combat
    var hp: Int = 3
    var hitCooldown: Double = 0   // immune window after taking a hit
    var koTimer: Double = 0       // counts up during KO; respawn when > KO_DURATION
    var targetId: UUID? = nil     // who we're hunting
    var koRotation: CGFloat = 0   // visual spin angle during KO

    static func spawn(at x: CGFloat, dna: MonsterDNA) -> MonsterState {
        MonsterState(
            id: UUID(),
            dna: dna,
            x: x,
            y: 0,
            vx: Bool.random() ? 0.8 : -0.8,
            vy: CGFloat.random(in: 3...6),   // entrance jump
            facingRight: Bool.random(),
            action: .walk,
            actionTimer: Double.random(in: 1...2),
            animFrame: 0,
            frameTimer: 0,
            hp: 3
        )
    }
}

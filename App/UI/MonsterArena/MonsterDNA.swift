import SwiftUI

// MARK: - Monster Classes
enum MonsterClass: String, CaseIterable {
    case knight       = "Knight"
    case ninja        = "Ninja"
    case samurai      = "Samurai"
    case dragon       = "Dragon"
    case dinosaur     = "Dino"
    case sifu         = "Sifu"
    case judoka       = "Judoka"
    case anime        = "Anime"
}

// MARK: - Monster DNA (fully deterministic from seed)
struct MonsterDNA: Identifiable {
    let id: UUID
    let class_: MonsterClass
    let primaryHue: Double   // 0–1
    let accentHue: Double
    let specialHue: Double   // fire / magic / aura color
    let scale: CGFloat       // 0.85–1.15

    static func random() -> MonsterDNA {
        let hue = Double.random(in: 0...1)
        // accent is 0.35–0.55 away (split-complementary feel)
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

    // Color roles: 1=head, 2=body, 3=dark, 4=white, 5=accent, 6=weapon, 7=special
    func color(role: Int) -> Color? {
        switch role {
        case 1: return Color(hue: primaryHue, saturation: 0.60, brightness: 0.95)
        case 2: return Color(hue: primaryHue, saturation: 0.72, brightness: 0.78)
        case 3: return Color(hue: primaryHue, saturation: 0.25, brightness: 0.20)
        case 4: return Color(white: 0.96)
        case 5: return Color(hue: accentHue,  saturation: 0.85, brightness: 0.90)
        case 6: return Color(hue: 0.13,       saturation: 0.75, brightness: 0.90)  // weapon gold/silver
        case 7: return Color(hue: specialHue, saturation: 0.95, brightness: 1.00)
        default: return nil
        }
    }
}

// MARK: - Monster Physics State
enum MonsterAction {
    case idle, walk, jump, attack, hit, victory
}

struct MonsterState: Identifiable {
    let id: UUID
    let dna: MonsterDNA
    var x: CGFloat
    var y: CGFloat          // y=0 is the floor
    var vx: CGFloat
    var vy: CGFloat
    var facingRight: Bool
    var action: MonsterAction
    var actionTimer: Double  // seconds remaining in current action
    var animFrame: Int       // 0 or 1 (walk cycle)
    var frameTimer: Double

    static func spawn(at x: CGFloat, dna: MonsterDNA) -> MonsterState {
        MonsterState(
            id: UUID(),
            dna: dna,
            x: x,
            y: 0,
            vx: Bool.random() ? 0.8 : -0.8,
            vy: 0,
            facingRight: Bool.random(),
            action: .walk,
            actionTimer: Double.random(in: 1...3),
            animFrame: 0,
            frameTimer: 0
        )
    }
}

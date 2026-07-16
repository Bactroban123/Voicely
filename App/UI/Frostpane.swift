import SwiftUI

// Frostpane design primitives shared across Settings pages (and future
// windows). Extracted from SettingsView so new surfaces reuse the exact same
// tokens instead of redeclaring them. Values must match DESIGN.md.

// MARK: - Colour tokens
extension Color {
    static let fpBg       = Color(red: 0.980, green: 0.988, blue: 0.996)
    static let fpSurface  = Color(red: 0.953, green: 0.969, blue: 0.980)
    static let fpSurface2 = Color(red: 0.910, green: 0.937, blue: 0.957)
    static let fpText     = Color(red: 0.055, green: 0.102, blue: 0.141)
    static let fpMuted    = Color(red: 0.352, green: 0.420, blue: 0.471)
    static let fpAccent   = Color(red: 0.227, green: 0.659, blue: 0.788)
    static let fpHairline = Color(red: 0.055, green: 0.102, blue: 0.141).opacity(0.10)
    static let fpLive     = Color(red: 0.133, green: 0.827, blue: 0.933)
}

/// Page container: icon + title header over a hairline rule.
struct PageShell<Content: View>: View {
    let title: String; let icon: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(Color.fpAccent)
                Text(title)
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.fpText)
            }
            .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 14)

            Rectangle().fill(Color.fpHairline).frame(height: 0.5).padding(.horizontal, 20)

            content()
        }
    }
}

/// Clean opaque card with hairline border
struct FPCard<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(spacing: 0) { content() }
            .background(Color.fpSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.fpHairline, lineWidth: 0.5))
            .padding(.bottom, 10)
    }
}

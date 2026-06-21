import SwiftUI

/// State for the floating recording HUD.
final class HUDModel: ObservableObject {
    enum Phase { case recording, processing }
    @Published var phase: Phase = .recording
    @Published var level: Float = 0
    @Published var label: String = "Listening"
}

/// The Frostpane HUD: a single frosted-glass capsule (the only glass surface in
/// the app), with the breathing live-cyan orb and waveform. Reads over any app,
/// light or dark. See DESIGN.md.
struct HUDView: View {
    @ObservedObject var model: HUDModel
    @State private var breathe = false

    private let live = Color(red: 0.133, green: 0.827, blue: 0.933)    // #22D3EE electric cyan
    private let glacier = Color(red: 0.227, green: 0.659, blue: 0.788) // #3AA8C9

    private var accent: Color { model.phase == .recording ? live : glacier }

    var body: some View {
        capsule
            .fixedSize()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var capsule: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(accent)
                .frame(width: 9, height: 9)
                .shadow(color: live.opacity(model.phase == .recording ? 0.7 : 0), radius: 5)
                .scaleEffect(model.phase == .recording && breathe ? 1.0 : 0.82)
            WaveformView(level: model.level, color: accent)
                .frame(width: 96, height: 22)
            Text(model.label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.14), radius: 14, y: 4)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }
}

/// Cheap bar waveform scaled by the current RMS level (transform-only redraw).
struct WaveformView: View {
    var level: Float
    var color: Color
    private let bars = 13

    var body: some View {
        Canvas { context, size in
            let barWidth: CGFloat = 3
            let gap = (size.width - CGFloat(bars) * barWidth) / CGFloat(bars - 1)
            let amplitude = CGFloat(min(max(level * 6, 0.06), 1))
            for i in 0..<bars {
                let t = CGFloat(i) / CGFloat(bars - 1)
                let shape = 0.35 + 0.65 * sin(t * .pi)
                let height = max(3, size.height * amplitude * shape)
                let x = CGFloat(i) * (barWidth + gap)
                let rect = CGRect(x: x, y: (size.height - height) / 2, width: barWidth, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(color))
            }
        }
    }
}

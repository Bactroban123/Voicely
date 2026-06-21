import SwiftUI

/// State for the floating recording HUD.
final class HUDModel: ObservableObject {
    enum Phase { case recording, processing }
    @Published var phase: Phase = .recording
    @Published var level: Float = 0
    @Published var label: String = "Listening"
}

/// The capsule itself: a self-contained dark surface (legible over any app), with
/// the amber state dot, live waveform, and label. See DESIGN.md.
struct HUDView: View {
    @ObservedObject var model: HUDModel
    private let amber = Color(red: 0.937, green: 0.624, blue: 0.153)
    private let surface = Color(red: 0.172, green: 0.172, blue: 0.157)

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(amber)
                .frame(width: 8, height: 8)
                .opacity(model.phase == .recording ? 1 : 0.5)
            WaveformView(level: model.level, color: amber)
                .frame(width: 96, height: 22)
            Text(model.label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(white: 0.95))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(surface)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5))
        .fixedSize()
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

import SwiftUI

// MARK: - Palette
// 0=transparent  1=glacier(#3AA8C9)  2=cyan(#22D3EE)
// 3=dark navy    4=white             5=coral(mouth)  6=gold(antenna)
private let palette: [Int: Color] = [
    1: Color(red: 0.227, green: 0.659, blue: 0.788),
    2: Color(red: 0.133, green: 0.827, blue: 0.933),
    3: Color(red: 0.090, green: 0.133, blue: 0.196),
    4: .white,
    5: Color(red: 1.0,   green: 0.42,  blue: 0.42 ),
    6: Color(red: 1.0,   green: 0.843, blue: 0.0  ),
]

// MARK: - Pixel Grids (12 × 18)
enum Mascot {
    static let normal: [[Int]] = [
        [0,0,0,0,6,0,0,0,0,0,0,0],  //  0 antenna star
        [0,0,0,0,3,0,0,0,0,0,0,0],  //  1 antenna
        [0,0,1,1,1,1,1,0,0,0,0,0],  //  2 head top
        [0,1,1,1,1,1,1,1,0,0,0,0],  //  3
        [1,1,1,1,1,1,1,1,1,0,0,0],  //  4
        [1,1,3,3,1,1,3,3,1,0,0,0],  //  5 eyes
        [1,1,3,4,1,1,3,4,1,0,0,0],  //  6 eye shine
        [1,1,1,1,5,5,1,1,1,0,0,0],  //  7 mouth
        [1,1,1,1,1,1,1,1,1,0,0,0],  //  8
        [0,1,1,1,1,1,1,1,0,0,0,0],  //  9
        [0,0,1,1,1,1,1,0,0,0,0,0],  // 10 head bottom
        [0,2,0,2,0,2,0,2,0,2,0,0],  // 11 waveform
        [2,2,2,0,2,2,2,0,2,2,0,0],  // 12
        [2,2,2,2,2,2,2,2,2,2,2,0],  // 13 peak
        [2,2,2,0,2,2,2,0,2,2,0,0],  // 14
        [0,2,0,2,0,2,0,2,0,2,0,0],  // 15
        [0,0,3,0,0,0,0,3,0,0,0,0],  // 16 legs
        [0,0,3,3,0,0,3,3,0,0,0,0],  // 17 feet
    ]

    static let blink: [[Int]] = {
        var g = normal
        g[5] = [1,1,3,3,3,3,3,3,1,0,0,0]  // closed eyes
        g[6] = [1,1,1,1,1,1,1,1,1,0,0,0]
        return g
    }()

    static let excited: [[Int]] = {
        var g = normal
        // wide open eyes + O-mouth
        g[5] = [1,3,3,3,1,1,3,3,3,0,0,0]
        g[6] = [1,3,4,3,1,1,3,4,3,0,0,0]
        g[7] = [1,1,1,5,5,5,1,1,1,0,0,0]
        g[8] = [1,1,1,1,5,1,1,1,1,0,0,0]
        return g
    }()
}

// MARK: - Raw Sprite Renderer
struct PixelSpriteView: View {
    let grid: [[Int]]
    let pixelSize: CGFloat

    private var cols: Int { grid.first?.count ?? 0 }
    private var rows: Int { grid.count }

    var body: some View {
        Canvas { ctx, _ in
            for (r, rowData) in grid.enumerated() {
                for (c, idx) in rowData.enumerated() {
                    guard idx != 0, let color = palette[idx] else { continue }
                    ctx.fill(
                        Path(CGRect(
                            x: CGFloat(c) * pixelSize,
                            y: CGFloat(r) * pixelSize,
                            width: pixelSize, height: pixelSize
                        )),
                        with: .color(color)
                    )
                }
            }
        }
        .frame(width: CGFloat(cols) * pixelSize, height: CGFloat(rows) * pixelSize)
    }
}

// MARK: - Animated Mascot
struct MascotView: View {
    var pixelSize: CGFloat = 8
    var mood: Mood = .idle

    enum Mood { case idle, excited }

    @State private var appeared = false
    @State private var floatY: CGFloat = 0
    @State private var blinking = false

    private var currentGrid: [[Int]] {
        switch mood {
        case .excited: return Mascot.excited
        case .idle:    return blinking ? Mascot.blink : Mascot.normal
        }
    }

    var body: some View {
        PixelSpriteView(grid: currentGrid, pixelSize: pixelSize)
            .scaleEffect(appeared ? 1.0 : 0.01)
            .offset(y: floatY)
            .onAppear {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.5)) {
                    appeared = true
                }
                withAnimation(
                    .easeInOut(duration: 2.2)
                    .repeatForever(autoreverses: true)
                    .delay(0.6)
                ) {
                    floatY = -7
                }
            }
            .task { await blinkLoop() }
    }

    private func blinkLoop() async {
        while !Task.isCancelled {
            let nanos = UInt64.random(in: 3_000_000_000...8_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { break }
            blinking = true
            try? await Task.sleep(nanoseconds: 130_000_000)
            blinking = false
        }
    }
}

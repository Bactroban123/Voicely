import AppKit
import SwiftUI

/// Non-activating floating panel for the HUD. Critically it never becomes key or
/// activates the app, so the user's focused text field stays focused and
/// insertion lands correctly (research §4).
final class HUDPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 380, height: 64),
                   styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class HUDController {
    let model = HUDModel()
    private lazy var panel: HUDPanel = {
        let panel = HUDPanel()
        panel.contentView = NSHostingView(rootView: HUDView(model: model))
        return panel
    }()

    func show(phase: HUDModel.Phase, label: String) {
        model.phase = phase
        model.label = label
        reposition()
        panel.orderFrontRegardless()
    }

    func update(level: Float) { model.level = level }

    func hide() { panel.orderOut(nil) }

    private func reposition() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                                     y: visible.minY + 120))
    }
}

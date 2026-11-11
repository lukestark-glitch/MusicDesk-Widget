import AppKit
import SwiftUI

/// Transparent AppKit view placed over the title: a mouse-down starts a
/// native window drag (unless the position is locked).
@MainActor
struct WindowDragArea: NSViewRepresentable {
    var isEnabled: Bool

    func makeNSView(context: Context) -> DragHandleView {
        let view = DragHandleView()
        view.isDragEnabled = isEnabled
        return view
    }

    func updateNSView(_ nsView: DragHandleView, context: Context) {
        nsView.isDragEnabled = isEnabled
    }
}

final class DragHandleView: NSView {
    var isDragEnabled = true

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // We start the drag ourselves; AppKit must not do it implicitly.
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        guard isDragEnabled, let window = window else { return }
        window.performDrag(with: event)
    }
}

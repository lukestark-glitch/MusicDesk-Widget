import SwiftUI

/// Borderless button style for the transport glyphs.
///
/// - Pressed: label dims to 50 % and shrinks slightly (like a native
///   borderless toolbar glyph).
/// - Hovered: label grows very slightly (≈ 6 %) – a subtle affordance on a
///   background-less widget where no highlight plate is possible.
/// - Both states animate with short, well-damped springs. With
///   "Bewegung reduzieren" only the opacity change remains.
struct PressDimButtonStyle: ButtonStyle {
    /// Hover state is tracked by the button itself (`onHover`) and passed in,
    /// because `ButtonStyleConfiguration` knows nothing about hovering.
    var isHovered: Bool = false
    /// Anchor for the scale effect. Use `.trailing` for a glyph that must stay
    /// flush with a trailing edge (the "next" button at the end of the bar).
    var scaleAnchor: UnitPoint = .center

    func makeBody(configuration: Configuration) -> some View {
        PressDimLabel(
            label: configuration.label,
            isPressed: configuration.isPressed,
            isHovered: isHovered,
            scaleAnchor: scaleAnchor
        )
    }
}

/// Separate view so the environment (Reduce Motion) can be read reliably.
private struct PressDimLabel: View {
    let label: ButtonStyleConfiguration.Label
    let isPressed: Bool
    let isHovered: Bool
    let scaleAnchor: UnitPoint

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let pressedOpacity: Double = 0.5
    static let pressedScale: CGFloat = 0.92
    static let hoverScale: CGFloat = 1.06

    private var scale: CGFloat {
        if reduceMotion { return 1 }
        if isPressed { return Self.pressedScale }
        return isHovered ? Self.hoverScale : 1
    }

    var body: some View {
        label
            .opacity(isPressed ? Self.pressedOpacity : 1)
            .scaleEffect(scale, anchor: scaleAnchor)
            // Press reacts quickly, release/hover settle a bit softer.
            .animation(.spring(response: 0.2, dampingFraction: 0.75), value: isPressed)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isHovered)
    }
}

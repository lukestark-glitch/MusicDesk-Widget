import SwiftUI

/// 5 pt capsule spanning the full width with a 9×23 pt knob at the current
/// progress. Click or drag anywhere in the 30 pt tall hit zone to seek.
@MainActor
struct ProgressBar: View {
    let state: PlaybackState
    let color: Color
    /// Called with the target position in seconds when a scrub ends.
    let onSeek: (Double) -> Void

    /// Local progress (0...1) while the user is dragging; nil otherwise.
    @State private var scrubFraction: Double? = nil

    init(state: PlaybackState, color: Color, onSeek: @escaping (Double) -> Void) {
        self.state = state
        self.color = color
        self.onSeek = onSeek
    }

    private static let barHeight: CGFloat = 5
    private static let knobWidth: CGFloat = 9
    private static let knobHeight: CGFloat = 23
    private static let knobCornerRadius: CGFloat = 4.5

    var body: some View {
        GeometryReader { geometry in
            content(size: geometry.size)
                .contentShape(Rectangle())
                .gesture(scrubGesture(width: geometry.size.width))
        }
        .background(Color.black.opacity(WidgetLayout.hitTestOpacity))
    }

    /// While playing, a TimelineView redraws at up to 30 fps with the
    /// extrapolated position; otherwise a static bar is shown (no CPU use).
    @ViewBuilder
    private func content(size: CGSize) -> some View {
        if let scrub = scrubFraction {
            bar(size: size, fraction: scrub)
        } else if state.isPlaying && state.duration > 0 {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                bar(size: size, fraction: state.progress(at: context.date))
            }
        } else {
            bar(size: size, fraction: state.progress(at: Date()))
        }
    }

    private func bar(size: CGSize, fraction: Double) -> some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(color)
                .frame(width: size.width, height: Self.barHeight)
            RoundedRectangle(cornerRadius: Self.knobCornerRadius, style: .continuous)
                .fill(color)
                .frame(width: Self.knobWidth, height: Self.knobHeight)
                .offset(x: knobOffset(width: size.width, fraction: fraction))
        }
        .frame(width: size.width, height: size.height)
    }

    /// Leading x of the knob; the knob stays inside the bar at 0 % and 100 %.
    private func knobOffset(width: CGFloat, fraction: Double) -> CGFloat {
        let travel = max(width - Self.knobWidth, 0)
        return travel * CGFloat(min(max(fraction, 0), 1))
    }

    /// Inverse of `knobOffset`: maps a pointer x to a 0...1 fraction.
    private func fraction(forX x: CGFloat, width: CGFloat) -> Double {
        let travel = width - Self.knobWidth
        guard travel > 0 else { return 0 }
        let value = Double((x - Self.knobWidth / 2) / travel)
        return min(max(value, 0), 1)
    }

    private func scrubGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard state.duration > 0 else { return }
                scrubFraction = fraction(forX: value.location.x, width: width)
            }
            .onEnded { value in
                defer { scrubFraction = nil }
                guard state.duration > 0 else { return }
                let target = fraction(forX: value.location.x, width: width)
                // The controller updates its state optimistically, so the
                // knob does not jump back when the scrub value is cleared.
                onSeek(target * state.duration)
            }
    }
}

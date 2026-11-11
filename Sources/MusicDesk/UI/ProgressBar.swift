import SwiftUI

/// Progress bar of the widget: a 5 pt capsule spanning the full width with a
/// 9×23 pt knob at the current position. Click or drag anywhere in the hit
/// zone (the frame given by the parent, 496 × WidgetLayout.barAreaHeight) to
/// seek. The bar is centered vertically in that frame.
///
/// Appearance comes straight from UserDefaults via `@AppStorage`:
/// opacity, Liquid Glass / material track, played-part highlight and knob
/// visibility. While scrubbing, elapsed and remaining time are shown just
/// below the bar (overflowing the frame; the parent does not clip).
@MainActor
struct ProgressBar: View {
    let state: NowPlaying
    let color: Color
    /// false in the settings preview: hover effects work, seeking does not.
    let isInteractive: Bool
    /// Called with the target position in seconds when a click/scrub ends.
    let onSeek: (Double) -> Void

    @AppStorage(SettingsKey.barOpacity) private var barOpacity = SettingsDefault.barOpacity
    @AppStorage(SettingsKey.barGlass) private var barGlass = SettingsDefault.barGlass
    @AppStorage(SettingsKey.highlightPlayed) private var highlightPlayed = SettingsDefault.highlightPlayed
    @AppStorage(SettingsKey.knobVisibility) private var knobVisibilityRaw = SettingsDefault.knobVisibility

    /// Local progress (0...1) while the user is dragging; nil otherwise.
    @State private var scrubFraction: Double? = nil
    @State private var isHovering = false
    /// Time labels below the bar (visible while scrubbing, fade out after).
    @State private var showTimeLabels = false
    /// Fraction the time labels show after the drag ended (during fade-out).
    @State private var labelFraction: Double = 0
    /// Bumped on every drag change so a pending fade-out is discarded.
    @State private var labelGeneration = 0

    init(state: NowPlaying, color: Color, isInteractive: Bool, onSeek: @escaping (Double) -> Void) {
        self.state = state
        self.color = color
        self.isInteractive = isInteractive
        self.onSeek = onSeek
    }

    // MARK: - Metrics

    private static let barHeight: CGFloat = 5
    private static let expandedBarHeight: CGFloat = 7
    private static let knobWidth: CGFloat = 9
    private static let knobHeight: CGFloat = 23
    private static let knobCornerRadius: CGFloat = 4.5
    private static let labelFontSize: CGFloat = 11
    /// Opacity of the unplayed part (and of the live bar).
    private static let dimmedOpacity: Double = 0.3
    private static let hoverAnimation = Animation.spring(response: 0.3, dampingFraction: 0.8)
    private static let labelHoldNanoseconds: UInt64 = 800_000_000

    // MARK: - Derived state

    private var knobVisibility: KnobVisibility {
        KnobVisibility(rawValue: knobVisibilityRaw) ?? .always
    }

    /// Whole-bar opacity, clamped to the allowed range.
    private var effectiveBarOpacity: Double {
        let range = SettingsDefault.barOpacityRange
        guard barOpacity.isFinite else { return range.upperBound }
        return min(max(barOpacity, range.lowerBound), range.upperBound)
    }

    /// Something plays but without a known duration (livestream etc.).
    private var isLive: Bool { state.hasTrack && !state.hasDuration }

    private var canSeek: Bool { isInteractive && state.hasDuration }

    private var isScrubbing: Bool { scrubFraction != nil }

    /// Hovered or dragging: bar grows 5 → 7 pt.
    private var isExpanded: Bool { isHovering || isScrubbing }

    private var isKnobVisible: Bool {
        guard !isLive else { return false }
        switch knobVisibility {
        case .always: return true
        case .hover: return isExpanded
        case .never: return false
        }
    }

    private var currentBarHeight: CGFloat {
        isExpanded ? Self.expandedBarHeight : Self.barHeight
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            content(size: geometry.size)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .overlay(alignment: .top) {
                    timeLabels(size: geometry.size)
                }
                .contentShape(Rectangle())
                .gesture(scrubGesture(width: geometry.size.width))
        }
        .background(Color.black.opacity(WidgetLayout.hitTestOpacity))
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .animation(Self.hoverAnimation, value: isExpanded)
        .animation(.easeInOut(duration: 0.2), value: isKnobVisible)
        .accessibilityElement()
        .accessibilityLabel(Text("Wiedergabeposition"))
        .accessibilityValue(Text(accessibilityValueText))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: adjust(by: 10)
            case .decrement: adjust(by: -10)
            default: break
            }
        }
    }

    /// While playing, a TimelineView redraws at up to 30 fps with the
    /// extrapolated position; otherwise a static bar is shown (no CPU use).
    @ViewBuilder
    private func content(size: CGSize) -> some View {
        if isLive {
            liveBar(size: size)
        } else if let scrub = scrubFraction {
            bar(size: size, fraction: scrub)
        } else if state.isPlaying && state.hasDuration {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                bar(size: size, fraction: state.progress(at: context.date))
            }
        } else {
            bar(size: size, fraction: state.progress(at: Date()))
        }
    }

    // MARK: - Bar

    private func bar(size: CGSize, fraction: Double) -> some View {
        let clamped = Self.clamp(fraction)
        let knobX = knobOffset(width: size.width, fraction: clamped)
        // The played part ends at the knob's centre (matches the seek mapping).
        let playedWidth = min(max(knobX + Self.knobWidth / 2, 0), size.width)
        let height = currentBarHeight

        return ZStack(alignment: .leading) {
            ZStack(alignment: .leading) {
                track(width: size.width, height: height)
                if highlightPlayed || !barGlass {
                    // highlight on: full color over a dimmed/glass track.
                    // highlight off without glass: same color both sides (1.0 look).
                    Capsule()
                        .fill(color)
                        .frame(width: playedWidth, height: height)
                }
                // highlight off with glass: uniform glass, the knob shows progress.
            }
            .frame(width: size.width, height: height)

            RoundedRectangle(cornerRadius: Self.knobCornerRadius, style: .continuous)
                .fill(color)
                .frame(width: Self.knobWidth, height: Self.knobHeight)
                .offset(x: knobX)
                .opacity(isKnobVisible ? 1 : 0)
        }
        .frame(width: size.width, height: size.height)
        .opacity(effectiveBarOpacity)
    }

    /// Livestream: thin dimmed bar, no knob, "Live" at the trailing end.
    private func liveBar(size: CGSize) -> some View {
        HStack(spacing: 8) {
            GeometryReader { inner in
                track(width: inner.size.width, height: currentBarHeight, forceDimmed: true)
                    .frame(width: inner.size.width, height: inner.size.height)
            }
            Text("Live")
                .font(.system(size: Self.labelFontSize, weight: .semibold))
                .foregroundColor(color)
                .fixedSize()
        }
        .frame(width: size.width, height: size.height)
        .opacity(effectiveBarOpacity)
    }

    /// Unplayed part / background of the bar.
    @ViewBuilder
    private func track(width: CGFloat, height: CGFloat, forceDimmed: Bool = false) -> some View {
        if barGlass {
            glassTrack(width: width, height: height)
        } else if highlightPlayed || forceDimmed {
            Capsule()
                .fill(color.opacity(Self.dimmedOpacity))
                .frame(width: width, height: height)
        } else {
            Capsule()
                .fill(color)
                .frame(width: width, height: height)
        }
    }

    /// Liquid Glass on macOS 26 (only when built with the macOS 26 SDK),
    /// otherwise a material-filled capsule tinted with the widget color.
    @ViewBuilder
    private func glassTrack(width: CGFloat, height: CGFloat) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            Capsule()
                .fill(color.opacity(0.12))
                .frame(width: width, height: height)
                .glassEffect(.regular.tint(color.opacity(0.35)), in: Capsule())
        } else {
            materialTrack(width: width, height: height)
        }
        #else
        materialTrack(width: width, height: height)
        #endif
    }

    private func materialTrack(width: CGFloat, height: CGFloat) -> some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay { Capsule().fill(color.opacity(Self.dimmedOpacity)) }
            .overlay { Capsule().strokeBorder(color.opacity(0.15), lineWidth: 0.5) }
            .frame(width: width, height: height)
    }

    // MARK: - Time labels

    @ViewBuilder
    private func timeLabels(size: CGSize) -> some View {
        if state.hasDuration {
            let fraction = scrubFraction ?? labelFraction
            let elapsed = Self.clamp(fraction) * state.duration
            let remaining = max(state.duration - elapsed, 0)
            HStack(spacing: 8) {
                Text(Self.formatTime(elapsed))
                Spacer(minLength: 8)
                Text("-" + Self.formatTime(remaining))
            }
            .font(.system(size: Self.labelFontSize, weight: .semibold).monospacedDigit())
            .foregroundColor(color)
            .lineLimit(1)
            .frame(width: size.width)
            // Just below the knob; overflows the frame downwards.
            .offset(y: size.height / 2 + Self.knobHeight / 2 + 2)
            .opacity(showTimeLabels ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    // MARK: - Seeking

    /// Leading x of the knob; the knob stays inside the bar at 0 % and 100 %.
    private func knobOffset(width: CGFloat, fraction: Double) -> CGFloat {
        let travel = max(width - Self.knobWidth, 0)
        return travel * CGFloat(Self.clamp(fraction))
    }

    /// Inverse of `knobOffset`: maps a pointer x to a 0...1 fraction.
    private func fraction(forX x: CGFloat, width: CGFloat) -> Double {
        let travel = width - Self.knobWidth
        guard travel > 0 else { return 0 }
        return Self.clamp(Double((x - Self.knobWidth / 2) / travel))
    }

    private func scrubGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard canSeek else { return }
                scrubFraction = fraction(forX: value.location.x, width: width)
                labelGeneration &+= 1
                if !showTimeLabels {
                    withAnimation(.easeOut(duration: 0.15)) { showTimeLabels = true }
                }
            }
            .onEnded { value in
                guard canSeek else {
                    scrubFraction = nil
                    return
                }
                let target = fraction(forX: value.location.x, width: width)
                labelFraction = target
                scrubFraction = nil
                // The manager updates its state optimistically, so the knob
                // does not jump back when the scrub value is cleared.
                onSeek(target * state.duration)
                scheduleLabelFadeOut()
            }
    }

    private func scheduleLabelFadeOut() {
        labelGeneration &+= 1
        let generation = labelGeneration
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.labelHoldNanoseconds)
            guard generation == labelGeneration, scrubFraction == nil else { return }
            withAnimation(.easeOut(duration: 0.3)) { showTimeLabels = false }
        }
    }

    // MARK: - Accessibility

    private var accessibilityValueText: String {
        if isLive { return "Live" }
        guard state.hasDuration else { return "Keine Wiedergabe" }
        let position = state.position(at: Date())
        return "\(Self.formatTime(position)) von \(Self.formatTime(state.duration))"
    }

    private func adjust(by seconds: Double) {
        guard canSeek else { return }
        let target = min(max(state.position(at: Date()) + seconds, 0), state.duration)
        onSeek(target)
    }

    // MARK: - Helpers

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    /// "1:23" / "1:02:03".
    private static func formatTime(_ seconds: Double) -> String {
        let total = seconds.isFinite ? max(Int(seconds.rounded(.down)), 0) : 0
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}

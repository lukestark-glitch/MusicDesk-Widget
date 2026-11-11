import AppKit
import SwiftUI

/// Single-line text that truncates with "…" or – when enabled and the text
/// is wider than the available width – scrolls to the left in a seamless loop:
/// 2 s pause, then ~30 pt/s until the second copy (after a 40 pt gap) sits
/// exactly where the first one started, repeat. Edges fade out over 12 pt
/// (the leading fade only while the text is scrolled away from its start).
///
/// Fills the frame it is given; text is leading aligned and vertically
/// centred. Honours "Bewegung reduzieren" (falls back to truncation).
/// Give it `.id(text)` from the outside to restart on content changes.
@MainActor
struct MarqueeText: View {
    /// Fully styled text (font, colours).
    let text: Text
    /// Plain string of `text`, measured with `font` to decide about overflow.
    let measureString: String
    let font: NSFont
    /// false = always truncate.
    let isEnabled: Bool
    var gap: CGFloat = 40
    var speed: CGFloat = 30            // points per second
    var pause: TimeInterval = 2        // seconds at the start of every loop
    var fadeWidth: CGFloat = 12

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        text: Text,
        measureString: String,
        font: NSFont,
        isEnabled: Bool,
        gap: CGFloat = 40,
        speed: CGFloat = 30,
        pause: TimeInterval = 2,
        fadeWidth: CGFloat = 12
    ) {
        self.text = text
        self.measureString = measureString
        self.font = font
        self.isEnabled = isEnabled
        self.gap = gap
        self.speed = speed
        self.pause = pause
        self.fadeWidth = fadeWidth
    }

    var body: some View {
        GeometryReader { geo in
            content(size: geo.size)
        }
    }

    @ViewBuilder
    private func content(size: CGSize) -> some View {
        let width = (isEnabled && !reduceMotion) ? measuredWidth : 0
        if width > 0 && size.width > 2 * fadeWidth && width > size.width + 0.5 && speed > 0 {
            // Only exists while overflowing → TimelineView stops otherwise,
            // and its start date is fresh every time scrolling begins.
            MarqueeScroller(
                text: text,
                textWidth: width,
                size: size,
                gap: gap,
                speed: speed,
                pause: pause,
                fadeWidth: fadeWidth
            )
        } else {
            text
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: size.width, height: size.height, alignment: .leading)
        }
    }

    /// Width of the text on one line (same font as the rendered Text).
    private var measuredWidth: CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let width = (measureString as NSString).size(withAttributes: attributes).width
        return width.isFinite ? ceil(width) : 0
    }
}

/// The scrolling part of `MarqueeText`. Offset is a pure function of the time
/// since this view appeared, driven by `TimelineView(.animation)`.
@MainActor
private struct MarqueeScroller: View {
    let text: Text
    let textWidth: CGFloat
    let size: CGSize
    let gap: CGFloat
    let speed: CGFloat
    let pause: TimeInterval
    let fadeWidth: CGFloat

    @State private var startDate = Date()

    /// Distance of one loop: text + gap (then copy 2 is where copy 1 began).
    private var distance: CGFloat { textWidth + gap }

    var body: some View {
        TimelineView(.animation) { context in
            let offset = scrollOffset(at: context.date)
            HStack(spacing: gap) {
                copy
                copy.accessibilityHidden(true)
            }
            .fixedSize()
            .offset(x: -offset)
            .frame(width: size.width, height: size.height, alignment: .leading)
            .mask {
                edgeMask(offset: offset)
            }
        }
        .accessibilityElement(children: .ignore)
    }

    /// Each copy occupies exactly the measured width, so the loop seam is exact.
    private var copy: some View {
        text
            .lineLimit(1)
            .fixedSize()
            .frame(width: textWidth, alignment: .leading)
    }

    private func scrollOffset(at date: Date) -> CGFloat {
        let scrollDuration = Double(distance / speed)
        let cycle = pause + scrollDuration
        guard cycle > 0, scrollDuration.isFinite else { return 0 }
        var elapsed = date.timeIntervalSince(startDate)
        if !elapsed.isFinite || elapsed < 0 { elapsed = 0 }
        let t = elapsed.truncatingRemainder(dividingBy: cycle)
        guard t > pause else { return 0 }
        return min(CGFloat(t - pause) * speed, distance)
    }

    private func edgeMask(offset: CGFloat) -> some View {
        let fade = min(fadeWidth, size.width / 2)
        let location = size.width > 0 ? fade / size.width : 0
        // Leading fade ramps in as the text leaves its start position and
        // out again as the second copy arrives there.
        var leading: CGFloat = 0
        if fade > 0 {
            leading = min(1, offset / fade, (distance - offset) / fade)
            leading = max(0, leading)
        }
        return LinearGradient(
            stops: [
                Gradient.Stop(color: Color.black.opacity(Double(1 - leading)), location: 0),
                Gradient.Stop(color: Color.black, location: location),
                Gradient.Stop(color: Color.black, location: 1 - location),
                Gradient.Stop(color: Color.black.opacity(0), location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

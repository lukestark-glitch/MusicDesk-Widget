import AppKit
import SwiftUI

/// Row of color dots like the accent color picker in System Settings.
/// Binds directly to the raw values stored via `@AppStorage`.
@MainActor
struct ColorDotPicker: View {
    @Binding var colorMode: String
    @Binding var customHex: String
    @Environment(\.colorScheme) private var colorScheme

    init(colorMode: Binding<String>, customHex: Binding<String>) {
        _colorMode = colorMode
        _customHex = customHex
    }

    private var selectedMode: WidgetColorMode {
        WidgetColorMode(rawValue: colorMode) ?? .black
    }

    var body: some View {
        // Presets plus a last dot that re-selects the custom color.
        HStack(spacing: 4) {
            ForEach(WidgetColorMode.presets + [WidgetColorMode.custom], id: \.self) { mode in
                ColorDot(
                    mode: mode,
                    color: mode.color(colorScheme: colorScheme, customHex: customHex),
                    isSelected: mode == selectedMode
                ) {
                    colorMode = mode.rawValue
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Farbe"))
    }
}

/// One 20 pt dot with a selection ring.
@MainActor
private struct ColorDot: View {
    let mode: WidgetColorMode
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    private static let dotSize: CGFloat = 20
    private static let ringSize: CGFloat = 26

    var body: some View {
        Button(action: action) {
            ZStack {
                dot
                    .frame(width: Self.dotSize, height: Self.dotSize)
                    // Hairline so white/black dots stay visible on any background.
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5))
                Circle()
                    .strokeBorder(Color.primary.opacity(0.55), lineWidth: 2)
                    .frame(width: Self.ringSize, height: Self.ringSize)
                    .opacity(isSelected ? 1 : 0)
            }
            .frame(width: Self.ringSize, height: Self.ringSize)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(mode.title)
        .accessibilityLabel(Text(mode.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var dot: some View {
        switch mode {
        case .automatic:
            // Half black, half white.
            ZStack {
                Circle().fill(Color.black)
                Circle().trim(from: 0.25, to: 0.75).fill(Color.white)
            }
            .rotationEffect(.degrees(45))
        case .custom:
            // Rainbow ring around the custom color.
            ZStack {
                Circle().fill(AngularGradient(
                    gradient: Gradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red]),
                    center: .center
                ))
                Circle().fill(color).padding(4)
            }
        default:
            Circle().fill(color)
        }
    }
}

/// "Eigene Farbe": system color well plus a validated #RRGGBB text field.
/// Both stay in sync with `customHex`; using either selects `.custom`.
@MainActor
struct CustomColorControl: View {
    @Binding var colorMode: String
    @Binding var customHex: String
    @State private var draft: String

    init(colorMode: Binding<String>, customHex: Binding<String>) {
        _colorMode = colorMode
        _customHex = customHex
        let current = customHex.wrappedValue
        _draft = State(initialValue: Self.normalized(current) ?? current)
    }

    /// "#RRGGBB" uppercase, or nil when invalid.
    nonisolated static func normalized(_ hex: String) -> String? {
        HexColor.nsColor(from: hex).map { HexColor.hexString(from: $0) }
    }

    private var isDraftValid: Bool { HexColor.isValid(draft) }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { HexColor.color(from: customHex) ?? .black },
            set: { newValue in
                let hex = HexColor.hexString(from: NSColor(newValue))
                if hex != Self.normalized(customHex) {
                    customHex = hex
                }
                selectCustom()
            }
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            ColorPicker("Eigene Farbe", selection: colorBinding, supportsOpacity: false)
                .labelsHidden()
                .help("Farbe wählen")

            TextField("#RRGGBB", text: $draft)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(isDraftValid ? .primary : .red)
                .frame(width: 90)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.red.opacity(isDraftValid ? 0 : 0.85), lineWidth: 1)
                        .allowsHitTesting(false)
                )
                .onSubmit { commitOrRevert() }
                .onChange(of: draft) { newValue in
                    draftDidChange(newValue)
                }
                .onChange(of: customHex) { newValue in
                    syncDraft(with: newValue)
                }
                .help("Hex-Wert, z. B. #FF3B30")
                .accessibilityLabel(Text("Hex-Farbwert"))
        }
    }

    private func selectCustom() {
        if colorMode != WidgetColorMode.custom.rawValue {
            colorMode = WidgetColorMode.custom.rawValue
        }
    }

    /// Commits as soon as the typed text is a valid color. Programmatic
    /// syncs (color well, reset) produce an equal value and are ignored.
    private func draftDidChange(_ newValue: String) {
        guard let hex = Self.normalized(newValue), hex != Self.normalized(customHex) else { return }
        customHex = hex
        selectCustom()
    }

    /// Return key: normalize a valid value (and select it), revert an invalid one.
    private func commitOrRevert() {
        if let hex = Self.normalized(draft) {
            if draft != hex { draft = hex }
            if hex != Self.normalized(customHex) { customHex = hex }
            selectCustom()
        } else {
            draft = Self.normalized(customHex) ?? customHex
        }
    }

    private func syncDraft(with hex: String) {
        guard Self.normalized(draft) != Self.normalized(hex) else { return }
        draft = Self.normalized(hex) ?? hex
    }
}

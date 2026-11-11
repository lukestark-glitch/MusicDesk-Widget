import AppKit
import Combine
import SwiftUI

/// Content of the settings window: a grouped Form in the style of System
/// Settings with a live preview on top. Every option is an `@AppStorage`
/// value, so the desktop widget updates immediately.
@MainActor
struct SettingsView: View {
    @ObservedObject var media: MediaManager
    @ObservedObject var updates: UpdateController

    // Quelle
    @AppStorage(SettingsKey.sourcePreference) private var sourcePreference = SettingsDefault.sourcePreference
    @AppStorage(SettingsKey.showSourceIcon) private var showSourceIcon = SettingsDefault.showSourceIcon
    // Darstellung
    @AppStorage(SettingsKey.colorMode) private var colorMode = SettingsDefault.colorMode
    @AppStorage(SettingsKey.customColorHex) private var customColorHex = SettingsDefault.customColorHex
    @AppStorage(SettingsKey.readabilityShadow) private var readabilityShadow = SettingsDefault.readabilityShadow
    @AppStorage(SettingsKey.dimArtist) private var dimArtist = SettingsDefault.dimArtist
    // Fortschrittsleiste
    @AppStorage(SettingsKey.barOpacity) private var barOpacity = SettingsDefault.barOpacity
    @AppStorage(SettingsKey.barGlass) private var barGlass = SettingsDefault.barGlass
    @AppStorage(SettingsKey.highlightPlayed) private var highlightPlayed = SettingsDefault.highlightPlayed
    @AppStorage(SettingsKey.knobVisibility) private var knobVisibility = SettingsDefault.knobVisibility
    // Titel
    @AppStorage(SettingsKey.titleOverflow) private var titleOverflow = SettingsDefault.titleOverflow
    // Allgemein
    @AppStorage(SettingsKey.positionLocked) private var positionLocked = false
    // Updates
    @AppStorage(SettingsKey.autoCheckUpdates) private var autoCheckUpdates = SettingsDefault.autoCheckUpdates

    @State private var previewDark: Bool
    @State private var loginEnabled: Bool
    @State private var loginNeedsApproval: Bool
    @State private var showResetConfirmation = false

    init(media: MediaManager) {
        _media = ObservedObject(wrappedValue: media)
        _updates = ObservedObject(wrappedValue: UpdateController.shared)
        let appearance = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        _previewDark = State(initialValue: appearance == .darkAqua)
        _loginEnabled = State(initialValue: LoginItem.isEnabled)
        _loginNeedsApproval = State(initialValue: LoginItem.requiresApproval)
    }

    var body: some View {
        Form {
            previewSection
            sourceSection
            appearanceSection
            barSection
            titleSection
            generalSection
            updatesSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, idealWidth: 520, maxWidth: .infinity,
               minHeight: 420, idealHeight: 720, maxHeight: .infinity)
        .onAppear { refreshLoginStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // The user may have approved/removed the login item in System Settings.
            refreshLoginStatus()
        }
        .confirmationDialog(
            "Alle Einstellungen zurücksetzen?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Zurücksetzen", role: .destructive) { resetToDefaults() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Quelle, Darstellung, Fortschrittsleiste, Titel und Updates werden auf die Standardwerte gesetzt. Position, Sperre und Login bleiben erhalten.")
        }
    }

    // MARK: - Sections

    private var previewSection: some View {
        Section {
            VStack(spacing: 10) {
                WidgetPreview(dark: previewDark)
                Picker("Vorschau-Hintergrund", selection: $previewDark) {
                    Text("Hell").tag(false)
                    Text("Dunkel").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
    }

    private var sourceSection: some View {
        Section("Quelle") {
            Picker("Quelle", selection: sourceBinding) {
                ForEach(SourcePreference.allCases, id: \.self) { preference in
                    Text(preference.displayName).tag(preference)
                }
            }
            LabeledContent("Alles auf dem Mac") {
                systemStatus
            }
            LabeledContent("Aktiv") {
                Text(media.activeSource?.displayName ?? "Keine Wiedergabe")
                    .foregroundStyle(.secondary)
            }
            Toggle(isOn: $showSourceIcon) {
                captioned("Quelle anzeigen", "App-Symbol vor dem Titel")
            }
        }
    }

    @ViewBuilder
    private var systemStatus: some View {
        switch media.systemAvailability {
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Wird geprüft …").foregroundStyle(.secondary)
            }
        case .available:
            HStack(spacing: 6) {
                Circle().fill(Color.green).frame(width: 8, height: 8)
                Text("Verfügbar").foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        case .unavailable(let reason):
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 6) {
                    Circle().fill(Color.orange).frame(width: 8, height: 8)
                    Text("Nicht verfügbar").foregroundStyle(.secondary)
                }
                Text(verbatim: reason + " – Apple Music/Spotify werden direkt genutzt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var appearanceSection: some View {
        Section("Darstellung") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Farbe")
                ColorDotPicker(colorMode: $colorMode, customHex: $customColorHex)
            }
            .padding(.vertical, 2)
            LabeledContent("Eigene Farbe") {
                CustomColorControl(colorMode: $colorMode, customHex: $customColorHex)
            }
            Toggle(isOn: $readabilityShadow) {
                captioned("Lesbarkeits-Schatten", "Dezenter Schatten für unruhige Hintergründe")
            }
            Toggle(isOn: $dimArtist) {
                captioned("Künstler dezenter", "Künstler mit 60 % Deckkraft")
            }
        }
    }

    private var barSection: some View {
        Section("Fortschrittsleiste") {
            LabeledContent("Deckkraft") {
                HStack(spacing: 10) {
                    Slider(value: barOpacityBinding, in: SettingsDefault.barOpacityRange)
                        .labelsHidden()
                        .frame(minWidth: 140, maxWidth: 220)
                        .accessibilityLabel(Text("Deckkraft"))
                        .accessibilityValue(Text(verbatim: barOpacityText))
                    Text(verbatim: barOpacityText)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                        .accessibilityHidden(true)
                }
            }
            Toggle(isOn: $barGlass) {
                captioned("Glas-Effekt", "Liquid Glass ab macOS 26, sonst Milchglas")
            }
            Toggle(isOn: $highlightPlayed) {
                captioned("Abgespielten Teil hervorheben", "Restlicher Teil wird heller dargestellt")
            }
            Picker("Regler anzeigen", selection: knobBinding) {
                ForEach(KnobVisibility.allCases, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }
        }
    }

    private var titleSection: some View {
        Section("Titel") {
            Picker(selection: titleOverflowBinding) {
                ForEach(TitleOverflow.allCases, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            } label: {
                captioned("Langer Titel", "Laufschrift pausiert, wenn „Bewegung reduzieren“ aktiv ist")
            }
        }
    }

    private var generalSection: some View {
        Section("Allgemein") {
            Toggle(isOn: $positionLocked) {
                captioned("Position sperren", "Widget lässt sich nicht verschieben")
            }
            Toggle(isOn: loginBinding) {
                if loginNeedsApproval {
                    captioned("Beim Login starten", "Bitte in den Systemeinstellungen unter „Anmeldeobjekte“ erlauben")
                } else {
                    Text("Beim Login starten")
                }
            }
            HStack {
                Spacer()
                Button("Auf Standard zurücksetzen …") {
                    showResetConfirmation = true
                }
            }
        }
    }

    private var updatesSection: some View {
        Section("Updates") {
            LabeledContent("Version") {
                Text(verbatim: updates.currentVersion)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            LabeledContent("Status") {
                HStack(spacing: 6) {
                    if isUpdateBusy {
                        ProgressView().controlSize(.small)
                    }
                    Text(verbatim: updateStatusText)
                        .foregroundStyle(isUpdateFailed ? Color.red : Color.secondary)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Toggle("Automatisch nach Updates suchen", isOn: $autoCheckUpdates)
            HStack {
                Spacer()
                Button("Jetzt suchen") {
                    updates.checkNow()
                }
                .disabled(isUpdateBusy)
                if updates.isUpdateAvailable {
                    Button("Update installieren …") {
                        updates.installUpdate()
                    }
                    .disabled(isUpdateBusy)
                }
            }
        }
    }

    // MARK: - Helpers

    /// Label with a secondary caption below, like System Settings.
    private func captioned(_ title: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title)
            Text(verbatim: caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sourceBinding: Binding<SourcePreference> {
        Binding(
            get: { SourcePreference(rawValue: sourcePreference) ?? .automatic },
            set: { sourcePreference = $0.rawValue }
        )
    }

    private var knobBinding: Binding<KnobVisibility> {
        Binding(
            get: { KnobVisibility(rawValue: knobVisibility) ?? .always },
            set: { knobVisibility = $0.rawValue }
        )
    }

    private var titleOverflowBinding: Binding<TitleOverflow> {
        Binding(
            get: { TitleOverflow(rawValue: titleOverflow) ?? .truncate },
            set: { titleOverflow = $0.rawValue }
        )
    }

    private var barOpacityBinding: Binding<Double> {
        let range = SettingsDefault.barOpacityRange
        return Binding(
            get: {
                let value = barOpacity.isFinite ? barOpacity : SettingsDefault.barOpacity
                return min(max(value, range.lowerBound), range.upperBound)
            },
            set: { barOpacity = min(max($0, range.lowerBound), range.upperBound) }
        )
    }

    private var barOpacityText: String {
        let range = SettingsDefault.barOpacityRange
        let value = barOpacity.isFinite ? min(max(barOpacity, range.lowerBound), range.upperBound) : 1
        return "\(Int((value * 100).rounded())) %"
    }

    private var loginBinding: Binding<Bool> {
        Binding(
            get: { loginEnabled || loginNeedsApproval },
            set: { on in
                if on {
                    // Registers; opens System Settings if approval is needed.
                    if !LoginItem.isEnabled { LoginItem.toggle() }
                } else {
                    LoginItem.setEnabled(false)
                }
                refreshLoginStatus()
            }
        )
    }

    private func refreshLoginStatus() {
        loginEnabled = LoginItem.isEnabled
        loginNeedsApproval = LoginItem.requiresApproval
    }

    /// Removes the resettable keys; `@AppStorage` falls back to the defaults.
    private func resetToDefaults() {
        let defaults = UserDefaults.standard
        for key in SettingsKey.resettable {
            defaults.removeObject(forKey: key)
        }
    }

    private var isUpdateBusy: Bool {
        switch updates.status {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    private var isUpdateFailed: Bool {
        if case .failed = updates.status { return true }
        return false
    }

    private var updateStatusText: String {
        switch updates.status {
        case .idle:
            if let lastCheck = updates.lastCheck {
                return "Zuletzt gesucht: " + lastCheck.formatted(date: .abbreviated, time: .shortened)
            }
            return "Noch nicht gesucht"
        case .checking:
            return "Suche nach Updates …"
        case .upToDate:
            return "MusicDesk ist aktuell"
        case .available(let version):
            return "Version \(version) ist verfügbar"
        case .downloading(let progress):
            let fraction = progress.isFinite ? min(max(progress, 0), 1) : 0
            return "Wird geladen … \(Int((fraction * 100).rounded())) %"
        case .installing:
            return "Wird installiert …"
        case .failed(let message):
            return "Fehler: \(message)"
        }
    }
}

/// Scaled, non-interactive copy of the widget on a light or dark backdrop.
@MainActor
private struct WidgetPreview: View {
    let dark: Bool
    @State private var start = Date()

    private static let scale: CGFloat = 0.75

    init(dark: Bool) {
        self.dark = dark
    }

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 10)) { context in
            WidgetView(state: Self.state(at: context.date, start: start), actions: .noop, isPreview: true)
                .frame(width: WidgetLayout.width, height: WidgetLayout.height)
                .scaleEffect(Self.scale)
                .frame(width: WidgetLayout.width * Self.scale, height: WidgetLayout.height * Self.scale)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(backdrop)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        // Drives `.automatic` (and dynamic system colors) in the preview.
        .environment(\.colorScheme, dark ? .dark : .light)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Vorschau des Widgets"))
    }

    private var backdrop: LinearGradient {
        let colors: [Color] = dark
            ? [Color(red: 0.11, green: 0.12, blue: 0.17), Color(red: 0.24, green: 0.21, blue: 0.30)]
            : [Color(red: 0.84, green: 0.88, blue: 0.94), Color(red: 0.97, green: 0.95, blue: 0.92)]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The sample track, looping its position so the preview never runs out.
    nonisolated private static func state(at date: Date, start: Date) -> NowPlaying {
        var state = NowPlaying.sample
        let elapsed = max(0, date.timeIntervalSince(start))
        state.position = 40 + elapsed.truncatingRemainder(dividingBy: 140)
        state.updatedAt = date
        return state
    }
}

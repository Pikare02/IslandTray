import CoreLocation
import Foundation
import SwiftUI

struct SetupGuideView: View {
    @Environment(\.dismiss) private var dismiss
    let model: TrayModel

    @State private var showActivityWhenEmpty = TraySettings().showActivityWhenEmpty
    /// Held in state, not read straight from `DropDiagnostics` in the body:
    /// it is plain UserDefaults with nothing to observe, so clearing it left
    /// the old lines on screen until the sheet was closed and reopened.
    @State private var diagnostics = DropDiagnostics.lines
    @State private var removeOnExport = TraySettings().removeOnExport
    @State private var deleteOriginalOnExport = TraySettings().deleteOriginalOnExport
    @State private var checksForUpdates = TraySettings().checksForUpdates
    @State private var insistsOnImportantUpdates = TraySettings().insistsOnImportantUpdates
    /// nil until checked; "" when up to date; otherwise the newer version.
    @State private var newerVersion: String?
    @State private var isChecking = false
    @State private var checkFailed = false
    @AppStorage("language", store: TraySettings.store) private var language = ""
    @AppStorage("theme", store: TraySettings.store) private var theme = ""
    @AppStorage(AccentColor.key, store: TraySettings.store) private var accent = ""
    /// The system picker works in `Color`, the setting is stored as hex; this
    /// holds the picker's side of that between the two.
    @State private var customColor = Color.accentColor

    var body: some View {
        NavigationStack {
            List {
                CloudSettingsSection(model: model)

                Section {
                    LabeledContent(L.s("settings.update.current"), value: UpdateChecker.currentVersion)
                    Toggle(L.s("settings.update.auto"), isOn: $checksForUpdates)
                        .onChange(of: checksForUpdates) { _, newValue in
                            TraySettings().checksForUpdates = newValue
                        }
                    Toggle(L.s("settings.update.insist"), isOn: $insistsOnImportantUpdates)
                        .onChange(of: insistsOnImportantUpdates) { _, newValue in
                            TraySettings().insistsOnImportantUpdates = newValue
                        }
                        // Only the launch check shows the alert this changes.
                        .disabled(!checksForUpdates)
                    Button {
                        Task { await checkForUpdates() }
                    } label: {
                        HStack {
                            Text(L.s("settings.update.check"))
                            Spacer()
                            if isChecking {
                                ProgressView()
                            } else if checkFailed {
                                Text(L.s("settings.update.failed")).foregroundStyle(.secondary)
                            } else if newerVersion == "" {
                                Text(L.s("settings.update.latest")).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(isChecking)
                    if let version = newerVersion, !version.isEmpty {
                        Link(L.s("settings.update.install", version), destination: UpdateChecker.installPage)
                    }
                    // Always there, up to date or not: the way back to an
                    // older build, or to the notes of the one installed.
                    Link(L.s("settings.update.releases"), destination: UpdateChecker.releasesPage)
                } header: {
                    Text(L.s("settings.update.section"))
                } footer: {
                    Text(L.s("settings.update.footer"))
                }

                Section {
                    Toggle(L.s("settings.activity.showEmpty"), isOn: $showActivityWhenEmpty)
                        .onChange(of: showActivityWhenEmpty) { _, newValue in
                            TraySettings().showActivityWhenEmpty = newValue
                            Task { await model.syncActivity() }
                        }
                } header: {
                    Text(L.s("settings.behaviour.section"))
                } footer: {
                    Text(L.s("settings.activity.footer"))
                }

                Section {
                    Toggle(L.s("settings.export.remove"), isOn: $removeOnExport)
                        .onChange(of: removeOnExport) { _, newValue in
                            TraySettings().removeOnExport = newValue
                        }
                    Toggle(L.s("settings.export.deleteOriginal"), isOn: $deleteOriginalOnExport)
                        .onChange(of: deleteOriginalOnExport) { _, newValue in
                            TraySettings().deleteOriginalOnExport = newValue
                        }
                } footer: {
                    Text(L.s("settings.export.footer"))
                }

                Section {
                    Picker(L.s("settings.language"), selection: $language) {
                        Text(L.s("settings.language.system")).tag("")
                        // Each in its own language, the way iOS lists them.
                        Text("日本語").tag("ja")
                        Text("English").tag("en")
                    }
                    Picker(L.s("settings.theme"), selection: $theme) {
                        Text(L.s("theme.system")).tag("")
                        Text(L.s("theme.light")).tag("light")
                        Text(L.s("theme.dark")).tag("dark")
                    }
                    accentRow
                } header: {
                    Text(L.s("settings.appearance.section"))
                }

                Section {
                    LabeledContent(L.s("settings.status.container"), value: L.s(TrayContainer.isShared ? "common.on" : "common.off"))
                    if !TrayContainer.isShared {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L.s("settings.free.1"))
                            Text(L.s("settings.free.2"))
                            Text(L.s("settings.free.3"))
                        }
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(L.s("settings.status.header"))
                }

                Section {
                    Text(L.s("settings.shortcut.intro"))
                        .font(.callout)
                    ShortcutLink("ShareToTray", title: L.s("settings.shortcut.install.share"))
                    step(1, L.s("settings.shortcut.1"))
                    step(2, L.s("settings.shortcut.2"))
                    step(3, L.s("settings.shortcut.3"))
                    step(4, L.s("settings.shortcut.4"))
                } header: {
                    Text(L.s("settings.shortcut.header"))
                } footer: {
                    Text(L.s("settings.shortcut.install.note.share"))
                }

                Section {
                    ShortcutLink("ClipboardToTray", title: L.s("settings.shortcut.install.clip"))
                    step(1, L.s("settings.shortcut.clip.1"))
                    step(2, L.s("settings.shortcut.clip.2"))
                    step(3, L.s("settings.shortcut.clip.3"))
                } header: {
                    Text(L.s("settings.shortcut.clip.header"))
                } footer: {
                    Text(L.s("settings.shortcut.install.note.clip"))
                }

                // iOS 26 and earlier have no screenshot trigger at all, so
                // this section would only describe something that is not there.
                if #available(iOS 27, *) {
                    Section {
                        step(1, L.s("settings.shortcut.shot.1"))
                        step(2, L.s("settings.shortcut.shot.2"))
                        step(3, L.s("settings.shortcut.shot.3"))
                    } header: {
                        Text(L.s("settings.shortcut.shot.header"))
                    } footer: {
                        Text(L.s("settings.shortcut.shot.footer"))
                    }
                }

                Section {
                    // The rationale for the automation lives right above the
                    // steps it justifies, instead of in an orphan section.
                    Text(L.s("settings.why.body"))
                        .font(.callout)
                    step(1, L.s("settings.step1"))
                    step(2, L.s("settings.step2"))
                    step(3, L.s("settings.step3"))
                    step(4, L.s("settings.step4"))
                    step(
                        5,
                        // Interpolates the intent's own title rather than a
                        // second hard-typed copy, so this instruction and the
                        // action name Shortcuts actually shows cannot drift
                        // apart.
                        L.s("settings.step5", String(localized: RefreshTrayActivityIntent.title))
                    )
                    step(6, L.s("settings.step6"))
                } header: {
                    Text(L.s("settings.steps.header"))
                }

                Section {
                    Text(L.s("settings.reopen"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    NavigationLink {
                        LabsSettingsView()
                    } label: {
                        Label(L.s("settings.labs"), systemImage: "flask")
                    }
                }

                Section {
                    // Collapsed: this is a debug record, and left expanded it
                    // filled the first screen of the settings with a dozen
                    // lines before anything a person came here to change.
                    DisclosureGroup(L.s("settings.records")) {
                        if diagnostics.isEmpty {
                            Text(L.s("settings.records.empty"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(diagnostics.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(.caption2, design: .monospaced))
                            }
                            Button(L.s("settings.records.clear"), role: .destructive) {
                                DropDiagnostics.clear()
                                diagnostics = []
                            }
                        }
                    }
                } footer: {
                    Text(L.s("settings.records.footer"))
                }
            }
            .onAppear { diagnostics = DropDiagnostics.lines }
            .navigationTitle(L.s("settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.s("common.done")) { dismiss() }
                }
            }
        }
    }

    /// Swatches for choosing without thinking, and the system's own picker
    /// for everything else -- it already has the spectrum, the sliders and a
    /// hex field, all of which would otherwise be rebuilt worse here.
    private var accentRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.s("settings.accent"))

            swatches(AccentColor.common)
            if !AccentColor.recents.isEmpty {
                Text(L.s("settings.accent.recent"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                swatches(AccentColor.recents)
            }

            HStack {
                ColorPicker(L.s("settings.accent.custom"), selection: $customColor, supportsOpacity: false)
                    .onChange(of: customColor) { _, picked in
                        choose(AccentColor.hex(for: picked))
                    }
                if !accent.isEmpty {
                    Button(L.s("settings.accent.default")) { accent = "" }
                        .font(.footnote)
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            customColor = AccentColor.color(forHex: accent) ?? .accentColor
        }
    }

    private func swatches(_ hexes: [String]) -> some View {
        HStack(spacing: 10) {
            ForEach(hexes, id: \.self) { hex in
                Button {
                    choose(hex)
                } label: {
                    Circle()
                        .fill(AccentColor.color(forHex: hex) ?? .clear)
                        .frame(width: 28, height: 28)
                        .overlay {
                            // The current one is marked rather than merely
                            // bigger: on a row of circles, size alone is not
                            // a state anyone reads.
                            if hex.caseInsensitiveCompare(accent) == .orderedSame {
                                Image(systemName: "checkmark")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private func choose(_ hex: String) {
        accent = hex
        AccentColor.remember(hex)
        customColor = AccentColor.color(forHex: hex) ?? .accentColor
    }

    private func checkForUpdates() async {
        isChecking = true
        defer { isChecking = false }
        do {
            newerVersion = try await UpdateChecker.newerVersion()?.version ?? ""
            checkFailed = false
        } catch {
            checkFailed = true
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.caption.bold().monospacedDigit())
                .frame(width: 20, height: 20)
                .background(.tint.opacity(0.18), in: .circle)
            Text(text)
                .font(.callout)
        }
    }
}

/// Labs: features still being tried out, one level below the settings so
/// their switches do not crowd the ones everyone uses.
private struct LabsSettingsView: View {
    // Literal keys, matching the convention `DrawerEditorView` already uses
    // for these same App Group keys (`TraySettings.Keys` is private).
    @AppStorage("appDrawerEnabled", store: TraySettings.store) private var appDrawerEnabled = false
    @AppStorage("showAppNames", store: TraySettings.store) private var showAppNames = true
    @AppStorage("lockScreenShowsDrawer", store: TraySettings.store) private var lockScreenShowsDrawer = false
    @AppStorage("temperatureUnit", store: TraySettings.store) private var temperatureUnit = "c"
    @AppStorage("weatherLocationMode", store: TraySettings.store) private var weatherLocationMode = "auto"
    @AppStorage("weatherManualName", store: TraySettings.store) private var manualCityName = ""
    @AppStorage("drawerBackgroundHex", store: TraySettings.store) private var drawerBackgroundHex = "000000"
    /// The system picker's side of `drawerBackgroundHex`, same split as `customColor`/`accent`.
    @State private var drawerBgColor = Color.black
    @State private var geocodeFailed = false

    var body: some View {
        List {
            Section {
                Toggle(L.s("drawer.settings.enable"), isOn: $appDrawerEnabled)
                    .onChange(of: appDrawerEnabled) { _, _ in
                        Task { await TrayActivityController.shared.restart() }
                    }
                if appDrawerEnabled {
                    Toggle(L.s("drawer.showNames"), isOn: $showAppNames)
                        .onChange(of: showAppNames) { _, _ in
                            Task { await TrayActivityController.shared.syncFromStore() }
                        }
                    Toggle(L.s("drawer.settings.lockScreen"), isOn: $lockScreenShowsDrawer)
                        .onChange(of: lockScreenShowsDrawer) { _, _ in
                            Task { await TrayActivityController.shared.syncFromStore() }
                        }
                    Picker(L.s("drawer.settings.unit"), selection: $temperatureUnit) {
                        Text("°C").tag("c")
                        Text("°F").tag("f")
                    }
                    Picker(L.s("drawer.settings.location"), selection: $weatherLocationMode) {
                        Text(L.s("drawer.settings.auto")).tag("auto")
                        Text(L.s("drawer.settings.manual")).tag("manual")
                    }
                    if weatherLocationMode == "manual" {
                        TextField(L.s("drawer.settings.city"), text: $manualCityName)
                            .onSubmit { geocodeManualCity() }
                        if geocodeFailed {
                            Text(L.s("drawer.settings.cityFailed"))
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                    drawerBackgroundRow
                }
            } header: {
                Text(L.s("drawer.settings.title"))
            }
        }
        .navigationTitle(L.s("settings.labs"))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Same swatches-plus-system-picker shape as `accentRow`, over
    /// `drawerBackgroundHex` instead of `accent`. No recents list: that is
    /// specific to the app-wide accent, not this one background.
    private var drawerBackgroundRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.s("drawer.background"))
            HStack(spacing: 10) {
                ForEach(AccentColor.common, id: \.self) { hex in
                    Button {
                        chooseDrawerBackground(hex)
                    } label: {
                        Circle()
                            .fill(AccentColor.color(forHex: hex) ?? .clear)
                            .frame(width: 28, height: 28)
                            .overlay {
                                if hex.caseInsensitiveCompare(drawerBackgroundHex) == .orderedSame {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            ColorPicker(L.s("settings.accent.custom"), selection: $drawerBgColor, supportsOpacity: false)
                .onChange(of: drawerBgColor) { _, picked in
                    chooseDrawerBackground(AccentColor.hex(for: picked))
                }
        }
        .padding(.vertical, 4)
        .onAppear {
            drawerBgColor = AccentColor.color(forHex: drawerBackgroundHex) ?? .black
        }
    }

    private func chooseDrawerBackground(_ hex: String) {
        drawerBackgroundHex = hex
        drawerBgColor = AccentColor.color(forHex: hex) ?? .black
    }

    /// Resolves the typed city to coordinates and stores them for
    /// `WeatherProvider` to read; failure just leaves the previous pin (if
    /// any) in place, flagged by `geocodeFailed`.
    private func geocodeManualCity() {
        let name = manualCityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        CLGeocoder().geocodeAddressString(name) { placemarks, _ in
            DispatchQueue.main.async {
                guard let coordinate = placemarks?.first?.location?.coordinate else {
                    geocodeFailed = true
                    return
                }
                geocodeFailed = false
                TraySettings().weatherManualLat = coordinate.latitude
                TraySettings().weatherManualLon = coordinate.longitude
                TraySettings().weatherManualName = name
            }
        }
    }
}

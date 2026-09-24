import CoreLocation
import Foundation
import PhotosUI
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
            if !AccentColor.recents().isEmpty {
                Text(L.s("settings.accent.recent"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                swatches(AccentColor.recents())
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
/// their switches do not crowd the ones everyone uses. Also reached straight
/// from the app-drawer page's gear, so its drawer options live in one place.
struct LabsSettingsView: View {
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
    @State private var backgroundItem: PhotosPickerItem?
    @State private var hasBackgroundImage = DrawerStore.shared.backgroundImageURL != nil
    @State private var showingMapPicker = false
    /// The just-picked background image, awaiting crop; `nil` closes the cropper.
    @State private var backgroundCropImage: UIImage?

    /// The drawer background fills the screen (`scaledToFill`), so the crop
    /// window matches the screen's portrait ratio.
    private static var backgroundAspect: CGFloat {
        let s = UIScreen.main.bounds.size
        return min(s.width, s.height) / max(s.width, s.height)
    }

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
                    .onChange(of: temperatureUnit) { _, _ in
                        Task { await TrayActivityController.shared.syncFromStore() }
                    }
                    Picker(L.s("drawer.settings.location"), selection: $weatherLocationMode) {
                        Text(L.s("drawer.settings.auto")).tag("auto")
                        Text(L.s("drawer.settings.manual")).tag("manual")
                    }
                    .onChange(of: weatherLocationMode) { _, _ in
                        Task { await TrayActivityController.shared.syncFromStore() }
                    }
                    if weatherLocationMode == "manual" {
                        Button { showingMapPicker = true } label: {
                            HStack {
                                Label(L.s("drawer.settings.pickOnMap"), systemImage: "mappin.and.ellipse")
                                Spacer()
                                if !manualCityName.isEmpty {
                                    Text(manualCityName).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    drawerBackgroundRow
                    PhotosPicker(L.s("drawer.backgroundImage"), selection: $backgroundItem, matching: .images)
                    if hasBackgroundImage {
                        Button(role: .destructive) {
                            DrawerStore.shared.writeBackgroundImage(nil)
                            hasBackgroundImage = false
                        } label: {
                            Text(L.s("drawer.removeBackgroundImage"))
                        }
                    }
                }
            } header: {
                Text(L.s("drawer.settings.title"))
            }
        }
        .navigationTitle(L.s("settings.labs"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: backgroundItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self),
                   let ui = UIImage(data: data) {
                    backgroundCropImage = ui
                }
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { backgroundCropImage != nil },
            set: { if !$0 { backgroundCropImage = nil } })) {
            if let ui = backgroundCropImage {
                ImageCropView(image: ui, aspect: Self.backgroundAspect, outputMaxDimension: 1600) { cropped in
                    if let data = cropped.jpegData(compressionQuality: 0.85) {
                        DrawerStore.shared.writeBackgroundImage(data)
                        hasBackgroundImage = true
                    }
                }
            }
        }
        .sheet(isPresented: $showingMapPicker) {
            MapLocationPicker(initial: currentManualCoordinate) { name in
                manualCityName = name
                Task { await TrayActivityController.shared.syncFromStore() }
            }
        }
    }

    /// The pinned coordinate, if one is stored, for the map picker to open on.
    private var currentManualCoordinate: CLLocationCoordinate2D? {
        let s = TraySettings()
        guard let lat = s.weatherManualLat, let lon = s.weatherManualLon else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Same swatches-plus-system-picker shape as `accentRow`, over
    /// `drawerBackgroundHex` instead of `accent`, with its own recents list.
    private var drawerBackgroundRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.s("drawer.background"))
            bgSwatches(AccentColor.backgroundSwatches)
            if !AccentColor.recents(key: AccentColor.backgroundRecentsKey).isEmpty {
                Text(L.s("settings.accent.recent"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                bgSwatches(AccentColor.recents(key: AccentColor.backgroundRecentsKey))
            }
            HStack {
                ColorPicker(L.s("settings.accent.custom"), selection: $drawerBgColor, supportsOpacity: false)
                    .onChange(of: drawerBgColor) { _, picked in
                        // Ignore the programmatic sync in `onAppear`: only a
                        // real pick (a colour different from the stored one)
                        // should apply and clear the image.
                        let hex = AccentColor.hex(for: picked)
                        if hex.caseInsensitiveCompare(drawerBackgroundHex) != .orderedSame {
                            chooseDrawerBackground(hex)
                        }
                    }
                // Shown whenever the background is not the default black (a
                // colour or an image); resets both back to black.
                if drawerBackgroundHex.caseInsensitiveCompare("000000") != .orderedSame || hasBackgroundImage {
                    Button(L.s("settings.accent.default")) { resetDrawerBackground() }
                        .font(.footnote)
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            drawerBgColor = AccentColor.color(forHex: drawerBackgroundHex) ?? .black
        }
    }

    /// Back to the default: drops any background image and sets black.
    private func resetDrawerBackground() {
        DrawerStore.shared.writeBackgroundImage(nil)
        hasBackgroundImage = false
        drawerBackgroundHex = "000000"
        drawerBgColor = .black
    }

    private func bgSwatches(_ hexes: [String]) -> some View {
        HStack(spacing: 10) {
            ForEach(hexes, id: \.self) { hex in
                Button {
                    chooseDrawerBackground(hex)
                } label: {
                    Circle()
                        .fill(AccentColor.color(forHex: hex) ?? .clear)
                        .frame(width: 28, height: 28)
                        // A stroke so black reads as a swatch, not a hole in
                        // the dark settings background.
                        .overlay { Circle().stroke(.white.opacity(0.15), lineWidth: 1) }
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
    }

    private func chooseDrawerBackground(_ hex: String) {
        // A colour replaces any background image; otherwise the image (which
        // wins over the colour in the drawer) would keep showing.
        if hasBackgroundImage {
            DrawerStore.shared.writeBackgroundImage(nil)
            hasBackgroundImage = false
        }
        drawerBackgroundHex = hex
        AccentColor.remember(hex, key: AccentColor.backgroundRecentsKey)
        drawerBgColor = AccentColor.color(forHex: hex) ?? .black
    }
}

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
                    LabeledContent(L.s("settings.update.current"), value: UpdateChecker.currentVersion)
                    Toggle(L.s("settings.update.auto"), isOn: $checksForUpdates)
                        .onChange(of: checksForUpdates) { _, newValue in
                            TraySettings().checksForUpdates = newValue
                        }
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
                } header: {
                    Text(L.s("settings.update.section"))
                } footer: {
                    Text(L.s("settings.update.footer"))
                }

                Section {
                    ShortcutLink("ClipboardToTray", title: L.s("settings.shortcut.install.clip"))
                    ShortcutLink("ShareToTray", title: L.s("settings.shortcut.install.share"))
                } header: {
                    Text(L.s("settings.setup.section"))
                } footer: {
                    Text(L.s("settings.shortcut.install.note"))
                }

                Section {
                    Text(L.s("settings.shortcut.intro"))
                        .font(.callout)
                    step(1, L.s("settings.shortcut.1"))
                    step(2, L.s("settings.shortcut.2"))
                    step(3, L.s("settings.shortcut.3"))
                    step(4, L.s("settings.shortcut.4"))
                } header: {
                    Text(L.s("settings.shortcut.header"))
                }

                Section {
                    step(1, L.s("settings.shortcut.clip.1"))
                    step(2, L.s("settings.shortcut.clip.2"))
                    step(3, L.s("settings.shortcut.clip.3"))
                } header: {
                    Text(L.s("settings.shortcut.clip.header"))
                }

                Section {
                    Text(L.s("settings.why.body"))
                        .font(.callout)
                } header: {
                    Text(L.s("settings.why.header"))
                }

                Section {
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
            newerVersion = try await UpdateChecker.newerVersion() ?? ""
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

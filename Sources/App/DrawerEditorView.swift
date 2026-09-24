import PhotosUI
import SwiftUI

/// The app drawer tab: a scrolling 6-column grid of shortcuts, its
/// background colour/image, and the name-label toggle. A tap runs the
/// shortcut; long-press to edit. The first six (by order) are what the
/// island shows.
struct DrawerEditorView: View {
    @State private var shortcuts: [DrawerShortcut] = DrawerStore.shared.load()
    @State private var adding = false
    @State private var editing: DrawerShortcut?
    @State private var showingBackgroundSettings = false
    // Literal keys, matching the codebase convention (`@AppStorage("theme"…)`,
    // `@AppStorage(AccentColor.key…)`); `TraySettings.Keys` is private.
    @AppStorage("showAppNames", store: TraySettings.store) private var showNames = true
    @AppStorage("drawerBackgroundHex", store: TraySettings.store) private var bgHex = "000000"
    @Environment(\.openURL) private var openURL

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 6)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(shortcuts) { s in
                        Button { run(s) } label: { cell(s) }
                            .contextMenu { contextMenu(for: s) }
                    }
                    Button { adding = true } label: {
                        Image(systemName: "plus")
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                    }
                }
                .padding()
            }
            .background(background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingBackgroundSettings = true } label: { Label(L.s("drawer.background"), systemImage: "gearshape") }
                }
            }
            .navigationTitle(L.s("drawer.title"))
        }
        // The grid is always drawn on a dark background, so its bar text must be light.
        .environment(\.colorScheme, .dark)
        .sheet(isPresented: $adding) {
            DrawerAddSheet { new in add(new) }
        }
        .sheet(item: $editing) { s in
            DrawerAddSheet(existing: s) { updated in update(updated) }
        }
        .sheet(isPresented: $showingBackgroundSettings) {
            DrawerBackgroundSettingsSheet(showNames: $showNames, bgHex: $bgHex)
        }
    }

    @ViewBuilder private func contextMenu(for s: DrawerShortcut) -> some View {
        Button { editing = s } label: { Label(L.s("drawer.edit"), systemImage: "pencil") }
        if let index = shortcuts.firstIndex(where: { $0.id == s.id }) {
            if index > 0 {
                Button { move(index, to: index - 1) } label: { Label(L.s("drawer.moveUp"), systemImage: "arrow.left") }
            }
            if index < shortcuts.count - 1 {
                Button { move(index, to: index + 1) } label: { Label(L.s("drawer.moveDown"), systemImage: "arrow.right") }
            }
        }
        Button(role: .destructive) { delete(s) } label: { Label(L.s("common.delete"), systemImage: "trash") }
    }

    @ViewBuilder private func cell(_ s: DrawerShortcut) -> some View {
        VStack(spacing: 4) {
            icon(s).frame(width: 52, height: 52)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            if showNames { Text(s.displayName).font(.caption2).lineLimit(1).foregroundStyle(.white) }
        }
    }

    @ViewBuilder private func icon(_ s: DrawerShortcut) -> some View {
        if let url = DrawerStore.shared.iconURL(for: s),
           let data = try? Data(contentsOf: url), let ui = UIImage(data: data) {
            Image(uiImage: ui).resizable().scaledToFill().clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            Image(systemName: s.symbolName).font(.title2).foregroundStyle(.white)
        }
    }

    private var background: some View {
        Group {
            if let url = DrawerStore.shared.backgroundImageURL,
               let data = try? Data(contentsOf: url), let ui = UIImage(data: data) {
                Image(uiImage: ui).resizable().scaledToFill()
            } else {
                AccentColor.color(forHex: bgHex) ?? Color.black
            }
        }
    }

    /// Installed apps go through the private launcher; everything else is a URL.
    private func run(_ s: DrawerShortcut) {
        if case .installedApp = s.kind {
            LaunchRouter.performLaunch(s.id)
        } else if let url = s.launchURL {
            openURL(url)
        }
    }

    private func add(_ s: DrawerShortcut) {
        var next = s; next.order = shortcuts.count
        shortcuts.append(next); persist()
    }
    private func update(_ s: DrawerShortcut) {
        if let i = shortcuts.firstIndex(where: { $0.id == s.id }) { shortcuts[i] = s }
        persist()
    }
    private func delete(_ s: DrawerShortcut) {
        DrawerStore.shared.removeIcon(for: s)
        shortcuts.removeAll { $0.id == s.id }
        persist()
    }
    private func move(_ from: Int, to: Int) {
        shortcuts.swapAt(from, to)
        persist()
    }
    /// Renumbers to match array order, saves, then pushes the change to the
    /// island (the widget reads whatever `DrawerStore` last had on disk).
    private func persist() {
        for i in shortcuts.indices { shortcuts[i].order = i }
        DrawerStore.shared.save(shortcuts)
        Task { await TrayActivityController.shared.syncFromStore() }
    }
}

/// Background colour/image and the name-label toggle, reached from the
/// drawer's gear icon. Kept as one small sheet rather than folded into the
/// main grid screen, which is busy enough already.
private struct DrawerBackgroundSettingsSheet: View {
    @Binding var showNames: Bool
    @Binding var bgHex: String
    @State private var customColor = Color.black
    @State private var backgroundItem: PhotosPickerItem?
    @State private var hasBackgroundImage = DrawerStore.shared.backgroundImageURL != nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(L.s("drawer.showNames"), isOn: $showNames)
                }
                Section {
                    swatches
                    ColorPicker(L.s("settings.accent.custom"), selection: $customColor, supportsOpacity: false)
                        .onChange(of: customColor) { _, picked in bgHex = AccentColor.hex(for: picked) }
                } header: {
                    Text(L.s("drawer.background"))
                }
                Section {
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
            }
            .navigationTitle(L.s("drawer.background"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L.s("common.done")) { dismiss() } }
            }
            .onAppear { customColor = AccentColor.color(forHex: bgHex) ?? .black }
            .onChange(of: backgroundItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) {
                        DrawerStore.shared.writeBackgroundImage(data)
                        hasBackgroundImage = true
                    }
                }
            }
        }
    }

    private var swatches: some View {
        HStack {
            ForEach(AccentColor.common, id: \.self) { hex in
                Button {
                    bgHex = hex
                    customColor = AccentColor.color(forHex: hex) ?? .black
                } label: {
                    Circle()
                        .fill(AccentColor.color(forHex: hex) ?? .clear)
                        .frame(width: 28, height: 28)
                        .overlay {
                            if hex.caseInsensitiveCompare(bgHex) == .orderedSame {
                                Circle().strokeBorder(.primary, lineWidth: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

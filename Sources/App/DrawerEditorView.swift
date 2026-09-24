import SwiftUI

/// The app drawer tab: a scrolling 6-column grid of shortcuts, its
/// background colour/image, and the name-label toggle. A tap runs the
/// shortcut; long-press for the edit menu, or long-press and drag to move
/// it. The first six (by order) are what the island shows.
struct DrawerEditorView: View {
    @State private var shortcuts: [DrawerShortcut] = DrawerStore.shared.load()
    @State private var adding = false
    @State private var editing: DrawerShortcut?
    @State private var showingSettings = false
    /// The shortcut being dragged; the grid rearranges live as it passes
    /// over other cells, and saves once it is dropped.
    @State private var dragging: DrawerShortcut?
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
                            .opacity(dragging?.id == s.id ? 0.4 : 1)
                            .onDrag {
                                dragging = s
                                return NSItemProvider(object: s.id.uuidString as NSString)
                            }
                            .onDrop(of: [.text], delegate: ReorderDrop(target: s, items: $shortcuts,
                                                                       dragging: $dragging, onDrop: persist))
                    }
                    Button { adding = true } label: {
                        Image(systemName: "plus")
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                    }
                }
                .padding()
                // Let go between cells: keep the arrangement reached so far.
                .onDrop(of: [.text], isTargeted: nil) { _ in
                    dragging = nil
                    persist()
                    return true
                }
            }
            .background(background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(DrawerShortcut.Sort.allCases, id: \.self) { sort in
                            Button(L.s("drawer.sort.\(sort.rawValue)")) {
                                withAnimation { shortcuts = DrawerShortcut.sorted(shortcuts, by: sort) }
                                persist()
                            }
                        }
                    } label: {
                        Label(L.s("drawer.sort"), systemImage: "arrow.up.arrow.down")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: { Label(L.s("settings.labs"), systemImage: "gearshape") }
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
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                LabsSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(L.s("common.done")) { showingSettings = false }
                        }
                    }
            }
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
        var next = s; next.order = shortcuts.count; next.addedAt = Date()
        shortcuts.append(next); persist()
    }
    private func update(_ s: DrawerShortcut) {
        if let i = shortcuts.firstIndex(where: { $0.id == s.id }) {
            var updated = s
            updated.addedAt = shortcuts[i].addedAt   // the edit sheet does not carry it
            shortcuts[i] = updated
        }
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

/// Moves the dragged shortcut into each cell it passes over, like the Home
/// Screen, and saves when it is let go.
private struct ReorderDrop: DropDelegate {
    let target: DrawerShortcut
    @Binding var items: [DrawerShortcut]
    @Binding var dragging: DrawerShortcut?
    let onDrop: () -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging.id != target.id,
              let from = items.firstIndex(where: { $0.id == dragging.id }),
              let to = items.firstIndex(where: { $0.id == target.id }) else { return }
        withAnimation(.snappy) {
            items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        onDrop()
        return true
    }
}

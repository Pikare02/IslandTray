import SwiftUI
import UniformTypeIdentifiers

struct TrayView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = TrayModel()
    @State private var isTargeted = false
    @State private var showsSetupGuide = false
    @State private var isSelecting = false
    @State private var selection: Set<UUID> = []
    @State private var previewing: TrayItem?

    var body: some View {
        NavigationStack {
            ZStack {
                if model.visible.isEmpty {
                    emptyState
                } else {
                    grid
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(dropHighlight)
            .navigationTitle("トレイ")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !model.visible.isEmpty {
                        Button(isSelecting ? "完了" : "選択") {
                            isSelecting.toggle()
                            if !isSelecting { selection = [] }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsSetupGuide = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { if isSelecting { selectionBar } }
            .sheet(isPresented: $showsSetupGuide) { SetupGuideView(model: model) }
            .fullScreenCover(item: $previewing) { item in
                QuickLookView(url: item.fileURL, name: item.name) { previewing = nil }
                    .ignoresSafeArea()
            }
            // The setter ignores dismissal: an alert can only go away through
            // one of its buttons, and each of those clears the list itself.
            // Clearing it from here too would discard the files the user just
            // asked to keep.
            .alert(
                "同じファイルがすでにトレイにあります",
                isPresented: Binding(get: { !model.pendingDuplicates.isEmpty }, set: { _ in })
            ) {
                Button("追加しない", role: .cancel) { Task { await model.discardPendingDuplicates() } }
                Button("追加する") { Task { await model.addPendingDuplicates() } }
            } message: {
                Text(model.duplicatePrompt)
            }
            .safeAreaInset(edge: .bottom) {
                if let banner = model.banner {
                    Text(banner)
                        .font(.footnote)
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(.red.opacity(0.15))
                }
            }
        }
        .onDrop(of: [UTType.item], isTargeted: $isTargeted) { providers in
            // Cleared by hand as well as by the binding: a drag that ends in
            // certain ways -- cancelled over the app, or handed off while the
            // app is going to the background -- leaves `isTargeted` stuck
            // true, and the highlight then sits there with no drag in sight.
            isTargeted = false
            Task { await model.ingest(providers) }
            return true
        }
        .task {
            // Migrate, reload, and -- only when the migration actually moved
            // something -- resync the island that scenePhase's `restart()`
            // already built from the pre-migration container. The ordering
            // and the condition are `start()`'s, where a test can reach them.
            await model.start()
        }
        .onChange(of: scenePhase) { _, phase in
            // Items another app took while we were in the background leave the
            // tray now: the receiving app has finished copying by the time the
            // user is back here. Deleting at the handoff instead would race
            // that copy, and the tray can hold the only copy.
            if phase == .active {
                // Same reason as in the drop handler: a drag that left with
                // the app can leave the highlight behind it.
                isTargeted = false
                Task {
                    await model.flushExported()
                    // Whatever the user sent here through another app's
                    // "ファイルに保存" while we were away.
                    await model.importFromFilesFolder()
                }
            }
        }
    }

    private var grid: some View {
        TrayGridView(
            items: model.visible,
            isSelecting: isSelecting,
            selection: $selection,
            model: model,
            onDelete: { item in Task { await model.remove(item) } },
            onOpen: { previewing = $0 }
        )
        // Items can leave the tray while the sheet of checkmarks is open --
        // handed to another app, deleted from a context menu -- and a
        // selection holding ids that no longer exist would share or delete
        // nothing while claiming a count.
        .onChange(of: model.visible.map(\.id)) { _, ids in
            selection.formIntersection(ids)
        }
    }

    /// What the selection can be done with: the two ways an item leaves.
    private var selectionBar: some View {
        HStack {
            // A custom Transferable needs its own preview, one per item:
            // ShareLink only defaults that for URL and String.
            ShareLink(
                items: selectedItems.map(SharedTrayFile.init(item:)),
                preview: { SharePreview($0.item.name) }
            ) {
                Label("共有", systemImage: "square.and.arrow.up")
            }
            .disabled(selection.isEmpty)

            Spacer()

            Text(selection.isEmpty ? "項目を選択" : "\(selection.count) 件")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()

            Button(role: .destructive) {
                let doomed = selectedItems
                selection = []
                Task { for item in doomed { await model.remove(item) } }
            } label: {
                Label("削除", systemImage: "trash")
            }
            .disabled(selection.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var selectedItems: [TrayItem] {
        model.visible.filter { selection.contains($0.id) }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("トレイは空です", systemImage: "tray")
        } description: {
            Text("ファイルや写真をドラッグしてここに落とすと預かります。")
        }
    }

    private var dropHighlight: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(Color.accentColor, lineWidth: isTargeted ? 4 : 0)
            .background(isTargeted ? Color.accentColor.opacity(0.10) : Color.clear)
            .padding(8)
            .animation(.snappy(duration: 0.15), value: isTargeted)
            .ignoresSafeArea()
    }
}

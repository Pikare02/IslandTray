import SwiftUI
import UniformTypeIdentifiers

struct TrayView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = TrayModel()
    @State private var isTargeted = false
    @State private var showsSetupGuide = false

    var body: some View {
        NavigationStack {
            ZStack {
                if model.visible.isEmpty {
                    emptyState
                } else {
                    strip
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(dropHighlight)
            .navigationTitle("トレイ")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsSetupGuide = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showsSetupGuide) { SetupGuideView(model: model) }
            // The setter ignores dismissal: an alert can only go away through
            // one of its buttons, and each of those clears the list itself.
            // Clearing it from here too would discard the files the user just
            // asked to keep.
            .alert(
                "同じファイルがすでにトレイにあります",
                isPresented: Binding(get: { !model.pendingDuplicates.isEmpty }, set: { _ in })
            ) {
                Button("追加しない", role: .cancel) { model.discardPendingDuplicates() }
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
                Task {
                    await model.flushExported()
                    // Whatever the user sent here through another app's
                    // "ファイルに保存" while we were away.
                    await model.importFromFilesFolder()
                }
            }
        }
    }

    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 16) {
                ForEach(model.visible) { item in
                    TrayCardView(item: item, model: model) {
                        Task { await model.remove(item) }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .scrollClipDisabled()
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

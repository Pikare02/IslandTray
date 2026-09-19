import SwiftUI
import UniformTypeIdentifiers

struct TrayView: View {
    @State private var model = TrayModel()
    @State private var isTargeted = false
    @State private var showsSetupGuide = false

    var body: some View {
        NavigationStack {
            ZStack {
                if model.items.isEmpty {
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
            .sheet(isPresented: $showsSetupGuide) { SetupGuideView() }
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
    }

    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 16) {
                ForEach(model.items) { item in
                    TrayCardView(item: item) {
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

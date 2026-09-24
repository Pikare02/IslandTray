import SwiftUI
import UniformTypeIdentifiers

/// The two boards, and everything that belongs to the app rather than to one
/// of them: the drop target, the first-run work, and the questions only the
/// model can answer.
struct TrayView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = TrayModel()
    @State private var isTargeted = false
    @AppStorage(AccentColor.key, store: TraySettings.store) private var accent = ""
    @Environment(\.openURL) private var openURL
    /// A newer release found on launch, offered once per launch.
    @State private var availableUpdate: UpdateChecker.Update?
    /// Which tab is up; the island's "more" link switches to the drawer.
    @State private var tab = "tray"
    /// Labs: the drawer tab only exists while the feature is on.
    @AppStorage("appDrawerEnabled", store: TraySettings.store) private var appDrawerEnabled = false
    /// A tray item the island asked to preview, until the tray board opens it.
    @State private var openRequest: UUID?

    var body: some View {
        TabView(selection: $tab) {
            if appDrawerEnabled {
                DrawerEditorView()
                    .tabItem { Label(L.s("drawer.title"), systemImage: "square.grid.3x3") }
                    .tag("drawer")
            }
            BoardView(board: .tray, model: model, openRequest: $openRequest)
                .tabItem { Label(L.s("tray.title"), systemImage: "tray") }
                .tag("tray")
            BoardView(board: .clipboard, model: model)
                .tabItem { Label(L.s("clipboard.title"), systemImage: "list.clipboard") }
                .tag("clipboard")
            BoardView(board: nil, model: model)
                .tabItem { Label(L.s("search.title"), systemImage: "magnifyingglass") }
                .tag("search")
        }
        // One tint for the whole app, applied where everything inherits it.
        .tint(AccentColor.color(forHex: accent))
        .background(dropHighlight)
        // The drop target is the whole app, not one board: something dropped
        // on the app goes to the tray wherever the user happens to be.
        .onDrop(of: [UTType.item], isTargeted: $isTargeted) { providers in
            // Cleared by hand as well as by the binding: a drag that ends in
            // certain ways -- cancelled over the app, or handed off while the
            // app is going to the background -- leaves `isTargeted` stuck
            // true, and the highlight then sits there with no drag in sight.
            isTargeted = false
            Task { await model.ingest(providers) }
            return true
        }
        // The setter ignores dismissal: an alert can only go away through one
        // of its buttons, and each of those clears the list itself. Clearing
        // it from here too would discard the files the user just asked to keep.
        .alert(
            L.s("dup.title"),
            isPresented: Binding(get: { !model.pendingDuplicates.isEmpty }, set: { _ in })
        ) {
            Button(L.s("dup.keep"), role: .cancel) { Task { await model.discardPendingDuplicates() } }
            Button(L.s("dup.add")) { Task { await model.addPendingDuplicates() } }
        } message: {
            Text(model.duplicatePrompt)
        }
        .alert(
            L.s(availableUpdate?.isImportant == true ? "update.title.important" : "update.title"),
            isPresented: Binding(get: { availableUpdate != nil }, set: { if !$0 { availableUpdate = nil } })
        ) {
            Button(L.s("update.open")) { openURL(UpdateChecker.installPage) }
            // No "don't show again" for an important one while insisting is
            // on: it is shown every launch until the app is actually updated.
            if let update = availableUpdate,
               UpdateChecker.isSkippable(update, insisting: TraySettings().insistsOnImportantUpdates) {
                Button(L.s("update.skip")) { TraySettings().skippedUpdateVersion = availableUpdate?.version }
            }
            Button(L.s("update.later"), role: .cancel) {}
        } message: {
            Text(L.s(
                availableUpdate?.isImportant == true ? "update.message.important" : "update.message",
                availableUpdate?.version ?? "", UpdateChecker.currentVersion
            ))
        }
        .task {
            // Quietly: a failed check on launch is not worth interrupting for.
            let settings = TraySettings()
            if settings.checksForUpdates,
               let update = try? await UpdateChecker.newerVersion(),
               UpdateChecker.shouldOffer(
                   update, skipped: settings.skippedUpdateVersion,
                   insisting: settings.insistsOnImportantUpdates
               ) {
                availableUpdate = update
                await UpdateNotifier.notifyIfNeeded(update)
            }
        }
        .task {
            // Migrate, reload, and -- only when the migration actually moved
            // something -- resync the island that scenePhase's `restart()`
            // already built from the pre-migration container. The ordering
            // and the condition are `start()`'s, where a test can reach them.
            await model.start()
        }
        // A shortcut run while this screen is up -- the Action button, a back
        // tap -- never takes the app out of the foreground, so the scene-phase
        // reload below would not see its item until the next visit.
        // Every change on this device goes up, and while the app is in front
        // the folder is looked at again for other devices'. Normally every 15
        // seconds; but a pass that just asked iCloud for a file cannot read it
        // until the next one, so while something is still settling it looks
        // again in a few seconds rather than leaving the change stuck behind a
        // whole idle interval.
        // ponytail: fixed 4s while settling; a download iCloud never completes
        // (offline) keeps it at 4s until foreground ends -- add a retry cap if
        // that ever shows up as battery drain.
        .task(id: model.items.map(\.id)) { await model.syncCloud() }
        .task(id: scenePhase) {
            while scenePhase == .active, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(model.cloud.settling ? 4 : 15))
                await model.syncCloud()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: TrayStore.didChangeFromIntentNotification)) { _ in
            model.reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openDrawer)) { _ in
            if appDrawerEnabled { tab = "drawer" }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openTrayItem)) { note in
            guard let id = note.object as? UUID else { return }
            tab = "tray"
            openRequest = id
        }
        .onChange(of: appDrawerEnabled) { _, on in if !on && tab == "drawer" { tab = "tray" } }
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
                    // First: everything below works from `items`, and an
                    // intent may have changed what is on disk since this view
                    // last read it.
                    await model.refresh()
                    await model.flushExported()
                    // Whatever the user sent here through another app's
                    // "ファイルに保存" while we were away.
                    await model.importFromFilesFolder()
                }
            }
        }
    }

    private var dropHighlight: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(Color.accentColor, lineWidth: isTargeted ? 4 : 0)
            .background(isTargeted ? Color.accentColor.opacity(0.10) : Color.clear)
            .padding(8)
            .animation(.snappy(duration: 0.15), value: isTargeted)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

/// One board. The tray and the clipboard differ in what they hold and how
/// they are filled, not in what can be done with what is in them, so this is
/// written once and told which board it is.
struct BoardView: View {
    /// The board this shows, or `nil` for the search screen, which shows
    /// whatever the query and the scope pick out of both.
    let board: TrayBoard?
    let model: TrayModel
    /// Set by the island's thumbnail links; the tray board previews it.
    @Binding var openRequest: UUID?

    @State private var showsSetupGuide = false
    @State private var filter = TrayFilter()
    /// Search only: which board to look in, `nil` for both.
    @State private var scope: TrayBoard?
    @State private var isSelecting = false
    @State private var selection: Set<UUID> = []
    @State private var previewing: TrayItem?
    /// Watched rather than read once: these live in UserDefaults, which a
    /// SwiftUI view is not told about, and the menu writes them.
    @AppStorage("orderingKey", store: TraySettings.store) private var orderingKey = TrayOrdering.Key.addedAt.rawValue
    @AppStorage("orderingAscending", store: TraySettings.store) private var orderingAscending = false
    @AppStorage("groupsByKind", store: TraySettings.store) private var groupsByKind = false
    /// Per board, with its own key and its own default: a tray of files reads
    /// as a grid of thumbnails, while a clipboard reads as a timeline.
    @AppStorage private var layoutRaw: String

    init(board: TrayBoard?, model: TrayModel, openRequest: Binding<UUID?> = .constant(nil)) {
        self.board = board
        self.model = model
        _openRequest = openRequest
        _layoutRaw = AppStorage(
            wrappedValue: board == .tray ? TrayLayout.grid.rawValue : TrayLayout.list.rawValue,
            "layout.\(board?.rawValue ?? "search")",
            store: TraySettings.store
        )
    }

    private var isSearch: Bool { board == nil }

    /// What this screen is looking at before the filter, which for search is
    /// the scope and for a board is the board.
    private var source: [TrayItem] {
        model.listed(on: isSearch ? scope : board)
    }

    private var items: [TrayItem] {
        guard isSearch else { return filter.apply(to: source) }
        return filter.apply(to: source, content: ContentIndex.shared.text(for:))
    }

    /// Search shows nothing until it is asked something: a screen that opens
    /// on every file you own is a worse answer than an empty one.
    private var showsResults: Bool {
        !isSearch || filter.isActive
    }
    private var layout: TrayLayout { TrayLayout(rawValue: layoutRaw) ?? .grid }

    private var ordering: TrayOrdering {
        TrayOrdering(
            key: TrayOrdering.Key(rawValue: orderingKey) ?? .addedAt,
            ascending: orderingAscending,
            groupsByKind: groupsByKind
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if !showsResults {
                    startSearching
                } else if items.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(L.s(titleKey))
            .modifier(SearchField(
                active: isSearch, text: $filter.text, scope: $scope,
                prompt: L.s("search.prompt.\(filter.mode.rawValue)")
            ))
            .task(id: model.items) {
                if isSearch { await ContentIndex.shared.update(model.items) }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if isSearch {
                        searchModeMenu
                    } else if !items.isEmpty {
                        Button(isSelecting ? L.s("common.done") : L.s("common.select")) {
                            isSelecting.toggle()
                            if !isSelecting { selection = [] }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !isSelecting { FilterMenu(filter: $filter) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !isSelecting && !items.isEmpty { layoutToggle }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !isSelecting && !items.isEmpty { arrangeMenu }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSelecting {
                        Button(allSelected ? L.s("common.deselectAll") : L.s("common.selectAll")) {
                            selection = allSelected ? [] : Set(items.map(\.id))
                        }
                    } else {
                        Button { showsSetupGuide = true } label: {
                            Label(L.s("settings.title"), systemImage: "gearshape")
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { if isSelecting { selectionBar } }
            .safeAreaInset(edge: .bottom) { CloudStatusBar(cloud: model.cloud) }
            .safeAreaInset(edge: .bottom) {
                if let banner = model.banner {
                    Text(banner)
                        .font(.footnote)
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(.red.opacity(0.15))
                }
            }
            .sheet(isPresented: $showsSetupGuide) { SetupGuideView(model: model) }
            // Re-tried when the items change: on a cold launch the link
            // arrives before the tray has been read off disk.
            .onChange(of: openRequest) { _, _ in openRequested() }
            .onChange(of: model.items) { _, _ in openRequested() }
            .onAppear { openRequested() }
            .fullScreenCover(item: $previewing) { item in
                QuickLookView(url: item.fileURL, name: item.name) { previewing = nil }
                    .ignoresSafeArea()
            }
        }
    }

    private var list: some View {
        TrayGridView(
            items: items,
            ordering: ordering,
            layout: layout,
            isSelecting: isSelecting,
            selection: $selection,
            cloud: cloudStates,
            model: model,
            onDelete: { item in Task { await model.remove(item) } },
            onOpen: { item in
                // An item from another device opens by coming down first.
                if model.cloud.isCloudOnly(item.id) {
                    Task { await model.download(item) }
                } else {
                    previewing = item
                }
            }
        )
        // Items can leave while the sheet of checkmarks is open -- handed to
        // another app, deleted from a context menu -- and a selection holding
        // ids that no longer exist would share or delete nothing while
        // claiming a count.
        .onChange(of: items.map(\.id)) { _, ids in
            selection.formIntersection(ids)
        }
    }

    private func openRequested() {
        guard let id = openRequest, let item = model.items.first(where: { $0.id == id }) else { return }
        openRequest = nil
        showsSetupGuide = false
        if model.cloud.isCloudOnly(item.id) {
            Task { await model.download(item) }
        } else {
            previewing = item
        }
    }

    private var cloudStates: [UUID: TrayItemView.Cloud] {
        Dictionary(uniqueKeysWithValues: model.cloud.cloudOnly.map {
            ($0.id, model.cloud.downloading.contains($0.id) ? .downloading : .remote)
        })
    }

    /// What the selection can be done with: the two ways an item leaves.
    private var selectionBar: some View {
        HStack {
            // A custom Transferable needs its own preview, one per item:
            // ShareLink only defaults that for URL and String.
            ShareLink(
                items: selectedItems.filter { !model.cloud.isCloudOnly($0.id) }.map(SharedTrayFile.init(item:)),
                preview: { SharePreview($0.item.name) }
            ) {
                Label(L.s("common.share"), systemImage: "square.and.arrow.up")
            }
            .disabled(selection.isEmpty)

            Spacer()

            Text(selection.isEmpty ? L.s("select.none") : L.s("select.count", selection.count))
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()

            Button(role: .destructive) {
                let doomed = selectedItems
                selection = []
                Task { for item in doomed { await model.remove(item) } }
            } label: {
                Label(L.s("common.delete"), systemImage: "trash")
            }
            .disabled(selection.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }

    /// On the screen it rearranges, not in the settings sheet: this is reached
    /// while looking at what it changes, unlike the things you set once.
    private var arrangeMenu: some View {
        Menu {
            Picker(L.s("settings.sort.order"), selection: $orderingKey) {
                Text(L.s("settings.sort.name")).tag(TrayOrdering.Key.name.rawValue)
                Text(L.s("settings.sort.added")).tag(TrayOrdering.Key.addedAt.rawValue)
                Text(L.s("settings.sort.size")).tag(TrayOrdering.Key.size.rawValue)
            }
            Picker(L.s("settings.sort.direction"), selection: $orderingAscending) {
                Text(L.s("settings.sort.descending")).tag(false)
                Text(L.s("settings.sort.ascending")).tag(true)
            }
            Toggle(L.s("settings.group"), isOn: $groupsByKind)
        } label: {
            Label(L.s("settings.sort.section"), systemImage: "arrow.up.arrow.down")
        }
    }

    /// A button of its own rather than a row in the sort menu, where it was
    /// out of sight. The icon is the layout a tap switches to.
    private var layoutToggle: some View {
        Button {
            layoutRaw = (layout == .grid ? TrayLayout.list : .grid).rawValue
        } label: {
            Label(L.s(layout == .grid ? "layout.list" : "layout.grid"),
                  systemImage: layout == .grid ? "list.bullet" : "square.grid.2x2")
        }
    }

    private var selectedItems: [TrayItem] {
        items.filter { selection.contains($0.id) }
    }

    private var allSelected: Bool {
        !items.isEmpty && items.allSatisfy { selection.contains($0.id) }
    }

    private var titleKey: String {
        switch board {
        case .tray: return "tray.title"
        case .clipboard: return "clipboard.title"
        case nil: return "search.title"
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(L.s(emptyTitleKey), systemImage: emptyIcon)
        } description: {
            Text(L.s(emptyBodyKey))
        }
    }

    /// What the typed text is matched against: names, contents, or both.
    private var searchModeMenu: some View {
        Menu {
            Picker(L.s("search.mode"), selection: $filter.mode) {
                ForEach(TrayFilter.Mode.allCases, id: \.self) { mode in
                    Text(L.s("search.mode.\(mode.rawValue)")).tag(mode)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(L.s("search.mode.\(filter.mode.rawValue)"))
                if ContentIndex.shared.isIndexing && filter.mode != .name {
                    ProgressView().controlSize(.small)
                }
            }
        }
    }

    private var startSearching: some View {
        ContentUnavailableView {
            Label(L.s("search.start.title"), systemImage: "magnifyingglass")
        } description: {
            Text(L.s("search.start.body"))
        }
    }

    private var emptyTitleKey: String {
        switch board {
        case .tray: return "tray.empty.title"
        case .clipboard: return "clipboard.empty.title"
        case nil: return "search.empty.title"
        }
    }

    private var emptyBodyKey: String {
        switch board {
        case .tray: return "tray.empty.body"
        case .clipboard: return "clipboard.empty.body"
        case nil: return "search.empty.body"
        }
    }

    private var emptyIcon: String {
        switch board {
        case .tray: return "tray"
        case .clipboard: return "list.clipboard"
        case nil: return "magnifyingglass"
        }
    }
}

/// `.searchable` on the search screen and nothing on a board.
///
/// A modifier rather than an `if` in the body: applying `.searchable`
/// conditionally changes the view's type from one render to the next, and
/// SwiftUI answers that by rebuilding the whole screen and dropping the
/// selection with it.
private struct SearchField: ViewModifier {
    let active: Bool
    @Binding var text: String
    @Binding var scope: TrayBoard?
    let prompt: String

    func body(content: Content) -> some View {
        if active {
            content
                .searchable(text: $text, prompt: prompt)
                .searchScopes($scope) {
                    Text(L.s("search.scope.all")).tag(TrayBoard?.none)
                    Text(L.s("tray.title")).tag(TrayBoard?.some(.tray))
                    Text(L.s("clipboard.title")).tag(TrayBoard?.some(.clipboard))
                }
        } else {
            content
        }
    }
}

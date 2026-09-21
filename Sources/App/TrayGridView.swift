import SwiftUI
import UIKit

/// The tray, as a grid of cards.
///
/// A `UICollectionView` rather than a `LazyVGrid`, for one reason that SwiftUI
/// has no answer to: adding a second item to a drag that is already in flight.
/// `.onDrag` offers exactly one provider per view and hears nothing more, so
/// picking up a card and then tapping others with a second finger -- the way
/// Photos and Files behave -- needs `collectionView(_:itemsForAddingTo:at:point:)`.
/// Having come this far for the drag, the selection and the layout live here
/// too rather than being solved twice.
struct TrayGridView: UIViewRepresentable {
    let items: [TrayItem]
    let ordering: TrayOrdering
    let layout: TrayLayout
    let isSelecting: Bool
    @Binding var selection: Set<UUID>
    let model: TrayModel
    let onDelete: (TrayItem) -> Void
    let onOpen: (TrayItem) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UICollectionView {
        let view = UICollectionView(
            frame: .zero,
            collectionViewLayout: Self.collectionLayout(
                headers: ordering.groupsByKind, layout: layout, swipe: context.coordinator.swipeActions, copySwipe: context.coordinator.copyActions
            )
        )
        view.backgroundColor = .clear
        view.alwaysBounceVertical = true
        // Off by default on iPhone -- without this the grid cannot be dragged
        // out of at all, which is most of what this app is for.
        view.dragInteractionEnabled = true
        view.delegate = context.coordinator
        view.dragDelegate = context.coordinator
        context.coordinator.attach(to: view)
        return view
    }

    /// Take the width SwiftUI offers rather than letting it ask the collection
    /// view: asked, a collection view answers with its own content size, and
    /// the grid came out one narrow column wide.
    func sizeThatFits(
        _ proposal: ProposedViewSize, uiView: UICollectionView, context: Context
    ) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }

    func updateUIView(_ view: UICollectionView, context: Context) {
        context.coordinator.parent = self
        // The layout carries both the headers and the shape of a row, so it
        // has to be swapped when either changes rather than only re-sectioned.
        if context.coordinator.headers != ordering.groupsByKind || context.coordinator.layout != layout {
            context.coordinator.headers = ordering.groupsByKind
            context.coordinator.layout = layout
            view.setCollectionViewLayout(
                Self.collectionLayout(
                    headers: ordering.groupsByKind, layout: layout, swipe: context.coordinator.swipeActions, copySwipe: context.coordinator.copyActions
                ),
                animated: false
            )
        }
        context.coordinator.apply(ordering.arrange(items))
    }

    /// As many square tiles per row as fit at roughly 110pt, never fewer than
    /// two, with room under each for one line of filename.
    private static func collectionLayout(
        headers: Bool,
        layout: TrayLayout,
        swipe: @escaping UICollectionLayoutListConfiguration.SwipeActionsConfigurationProvider,
        copySwipe: @escaping UICollectionLayoutListConfiguration.SwipeActionsConfigurationProvider
    ) -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { _, environment in
            if layout == .list {
                // The system's own list section, so rows, separators and
                // insets match everything else on iOS rather than being
                // approximated here.
                var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
                configuration.headerMode = headers ? .supplementary : .none
                configuration.backgroundColor = .clear
                // Swipe left for Delete; keep going and the system fills the
                // row red, taps the haptic and deletes -- a full swipe performs
                // the first action by default.
                configuration.trailingSwipeActionsConfigurationProvider = swipe
                // Swipe right for Copy, the same way round.
                configuration.leadingSwipeActionsConfigurationProvider = copySwipe
                return NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
            }
            let spacing: CGFloat = 12
            let inset: CGFloat = 16
            let available = environment.container.effectiveContentSize.width - inset * 2
            let columns = max(2, Int((available + spacing) / (110 + spacing)))
            let tile = (available - spacing * CGFloat(columns - 1)) / CGFloat(columns)

            // The tile width is absolute, not fractional: `repeatingSubitem`
            // lays the subitem out at its own size rather than dividing the
            // group by `count`, so a fractional 1 gave one full-width column.
            let item = NSCollectionLayoutItem(layoutSize: .init(
                widthDimension: .absolute(tile), heightDimension: .fractionalHeight(1)
            ))
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: .init(
                    widthDimension: .fractionalWidth(1),
                    // The tile is square; the rest is the name under it.
                    heightDimension: .absolute(tile + 26)
                ),
                repeatingSubitem: item,
                count: columns
            )
            group.interItemSpacing = .fixed(spacing)

            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = spacing
            section.contentInsets = .init(top: inset, leading: inset, bottom: inset, trailing: inset)
            if headers {
                section.boundarySupplementaryItems = [NSCollectionLayoutBoundarySupplementaryItem(
                    layoutSize: .init(
                        widthDimension: .fractionalWidth(1), heightDimension: .estimated(28)
                    ),
                    elementKind: UICollectionView.elementKindSectionHeader,
                    alignment: .top
                )]
            }
            return section
        }
    }

    @MainActor
    final class Coordinator: NSObject, UICollectionViewDelegate, UICollectionViewDragDelegate {
        var parent: TrayGridView
        /// Mirrors `ordering.groupsByKind`, so `updateUIView` can tell when
        /// the layout itself has to be replaced.
        var headers = false
        /// Mirrors the board's layout, for the same reason as `headers`.
        var layout: TrayLayout = .grid
        private var dataSource: UICollectionViewDiffableDataSource<String, UUID>!
        /// Section titles by section id, for the headers.
        private var titles: [String: String] = [:]
        /// The items behind the ids the data source carries. Identity is the
        /// id alone, so a changed item reconfigures its cell instead of
        /// replacing it and interrupting a drag.
        private var shown: [UUID: TrayItem] = [:]

        init(_ parent: TrayGridView) {
            self.parent = parent
        }

        /// Built once, in `attach(to:)`, and never inside the cell provider:
        /// UIKit traps a registration first created in there, because one made
        /// per dequeue defeats reuse and strands every cell it makes.
        private var registration: UICollectionView.CellRegistration<UICollectionViewListCell, UUID>!

        func attach(to view: UICollectionView) {
            registration = UICollectionView
                // A list cell, because only a list cell can be swiped. Its
                // default background is cleared so the cards and rows look as
                // they did as plain cells.
                .CellRegistration<UICollectionViewListCell, UUID> { [unowned self] cell, _, id in
                    guard let item = shown[id] else { return }
                    cell.backgroundConfiguration = .clear()
                    cell.contentConfiguration = UIHostingConfiguration {
                        TrayItemView(
                            item: item,
                            style: parent.layout == .list ? .row : .card,
                            isSelecting: parent.isSelecting,
                            isSelected: parent.selection.contains(id),
                            onDelete: { [parent] in parent.onDelete(item) }
                        )
                    }
                    .margins(.all, parent.layout == .list ? 8 : 0)
                }
            let header = UICollectionView.SupplementaryRegistration<UICollectionViewCell>(
                elementKind: UICollectionView.elementKindSectionHeader
            ) { [unowned self] cell, _, indexPath in
                let id = dataSource.snapshot().sectionIdentifiers[indexPath.section]
                let ids = dataSource.snapshot().itemIdentifiers(inSection: id)
                let allSelected = !ids.isEmpty && ids.allSatisfy(parent.selection.contains)
                cell.contentConfiguration = UIHostingConfiguration {
                    HStack {
                        Text(titles[id] ?? "")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if parent.isSelecting {
                            Button(allSelected ? L.s("common.deselectAll") : L.s("common.selectAll")) {
                                [unowned self] in toggleSection(ids, allSelected: allSelected)
                            }
                            .font(.footnote)
                        }
                    }
                }
                .margins(.horizontal, 16)
                .margins(.vertical, 2)
            }
            dataSource = UICollectionViewDiffableDataSource(collectionView: view) {
                [unowned self] view, indexPath, id in
                view.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: id)
            }
            dataSource.supplementaryViewProvider = { view, _, indexPath in
                view.dequeueConfiguredReusableSupplementary(using: header, for: indexPath)
            }
        }

        func apply(_ sections: [TrayOrdering.Section]) {
            let items = sections.flatMap(\.items)
            shown = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            titles = Dictionary(
                sections.compactMap { section in
                    section.kind.map { (Self.sectionID(for: $0), Self.title(for: $0)) }
                },
                uniquingKeysWith: { first, _ in first }
            )

            var snapshot = NSDiffableDataSourceSnapshot<String, UUID>()
            for section in sections {
                let id = section.kind.map(Self.sectionID(for:)) ?? ""
                snapshot.appendSections([id])
                snapshot.appendItems(section.items.map(\.id), toSection: id)
            }
            // Everything that survives the update is reconfigured, because
            // selection and edit mode are read inside the cell's content and
            // the diff alone would not notice them changing.
            let carried = Set(dataSource.snapshot().itemIdentifiers)
            snapshot.reconfigureItems(items.map(\.id).filter(carried.contains))
            dataSource.apply(snapshot, animatingDifferences: true)
        }

        private static func sectionID(for kind: TrayItemKind) -> String { kind.rawValue }

        private static func title(for kind: TrayItemKind) -> String {
            switch kind {
            case .image: return L.s("kind.image")
            case .video: return L.s("kind.video")
            case .audio: return L.s("kind.audio")
            case .document: return L.s("kind.document")
            case .archive: return L.s("kind.archive")
            case .folder: return L.s("kind.folder")
            case .other: return L.s("kind.other")
            }
        }

        // MARK: - Swipe to delete

        /// Nil while selecting: a swipe there would fight the checkmarks.
        func swipeActions(at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
            guard !parent.isSelecting,
                  let id = dataSource.itemIdentifier(for: indexPath),
                  let item = shown[id] else { return nil }
            let delete = UIContextualAction(style: .destructive, title: L.s("common.delete")) {
                [unowned self] _, _, done in
                parent.onDelete(item)
                done(true)
            }
            delete.image = UIImage(systemName: "trash")
            return UISwipeActionsConfiguration(actions: [delete])
        }

        /// Clipboard items only: copying a tray file back out is what the
        /// drag and the share sheet are for.
        func copyActions(at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
            guard !parent.isSelecting,
                  let id = dataSource.itemIdentifier(for: indexPath),
                  let item = shown[id], item.boardOrTray == .clipboard else { return nil }
            let copy = UIContextualAction(style: .normal, title: L.s("common.copy")) { _, _, done in
                done(RichText.copy(item))
            }
            copy.image = UIImage(systemName: "doc.on.doc")
            copy.backgroundColor = .systemBlue
            return UISwipeActionsConfiguration(actions: [copy])
        }

        // MARK: - Selection

        /// Selection is ours, not the collection view's.
        ///
        /// UIKit's own selected state is deliberately left switched off and
        /// every cell is deselected as soon as it is tapped: selecting a whole
        /// section, or everything, from outside changes only our set, and the
        /// two would drift apart -- a cell UIKit thought was unselected would
        /// then need two taps to clear.
        func collectionView(_ view: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            view.deselectItem(at: indexPath, animated: false)
            guard let id = dataSource.itemIdentifier(for: indexPath) else { return }
            guard parent.isSelecting else {
                if let item = shown[id] { parent.onOpen(item) }
                return
            }
            if parent.selection.contains(id) {
                parent.selection.remove(id)
            } else {
                parent.selection.insert(id)
            }
            reconfigure(id)
        }

        private func toggleSection(_ ids: [UUID], allSelected: Bool) {
            if allSelected {
                parent.selection.subtract(ids)
            } else {
                parent.selection.formUnion(ids)
            }
            var snapshot = dataSource.snapshot()
            snapshot.reconfigureItems(ids)
            dataSource.apply(snapshot, animatingDifferences: false)
        }

        private func reconfigure(_ id: UUID) {
            var snapshot = dataSource.snapshot()
            guard snapshot.itemIdentifiers.contains(id) else { return }
            snapshot.reconfigureItems([id])
            dataSource.apply(snapshot, animatingDifferences: false)
        }

        // MARK: - Dragging out

        /// A drag that starts on a selected card carries the whole selection;
        /// one that starts anywhere else carries just that card.
        func collectionView(
            _ view: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath
        ) -> [UIDragItem] {
            guard let id = dataSource.itemIdentifier(for: indexPath) else { return [] }
            let ids = parent.selection.contains(id)
                ? dataSource.snapshot().itemIdentifiers.filter(parent.selection.contains)
                : [id]
            return ids.compactMap { shown[$0] }.map(dragItem(for:))
        }

        /// The second finger: a card tapped while a drag is already in flight
        /// joins it.
        func collectionView(
            _ view: UICollectionView,
            itemsForAddingTo session: UIDragSession,
            at indexPath: IndexPath,
            point: CGPoint
        ) -> [UIDragItem] {
            guard let id = dataSource.itemIdentifier(for: indexPath), let item = shown[id] else { return [] }
            // Tapping a card that is already travelling must not hand the same
            // file over twice.
            guard !session.items.contains(where: { $0.localObject as? UUID == id }) else { return [] }
            return [dragItem(for: item)]
        }

        /// Always a copy: offered a move, Files shows no "+" and treats the
        /// tray's file as something it may take away.
        func collectionView(_ view: UICollectionView, dragSessionAllowsMoveOperation session: UIDragSession) -> Bool {
            false
        }

        private func dragItem(for item: TrayItem) -> UIDragItem {
            let drag = UIDragItem(itemProvider: TrayDragProvider.provider(for: item, model: parent.model))
            // Identifies the item to `itemsForAddingTo` above; never read as
            // anything but a de-duplication key.
            drag.localObject = item.id
            return drag
        }
    }
}

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
    let isSelecting: Bool
    @Binding var selection: Set<UUID>
    let model: TrayModel
    let onDelete: (TrayItem) -> Void
    let onOpen: (TrayItem) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UICollectionView {
        let view = UICollectionView(frame: .zero, collectionViewLayout: Self.layout())
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
        view.allowsMultipleSelection = isSelecting
        context.coordinator.apply(items)
    }

    /// As many square tiles per row as fit at roughly 110pt, never fewer than
    /// two, with room under each for one line of filename.
    private static func layout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { _, environment in
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
            return section
        }
    }

    @MainActor
    final class Coordinator: NSObject, UICollectionViewDelegate, UICollectionViewDragDelegate {
        var parent: TrayGridView
        private var dataSource: UICollectionViewDiffableDataSource<Int, UUID>!
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
        private var registration: UICollectionView.CellRegistration<UICollectionViewCell, UUID>!

        func attach(to view: UICollectionView) {
            registration = UICollectionView
                .CellRegistration<UICollectionViewCell, UUID> { [unowned self] cell, _, id in
                    guard let item = shown[id] else { return }
                    cell.contentConfiguration = UIHostingConfiguration {
                        TrayCardView(
                            item: item,
                            isSelecting: parent.isSelecting,
                            isSelected: parent.selection.contains(id),
                            onDelete: { [parent] in parent.onDelete(item) }
                        )
                    }
                    .margins(.all, 0)
                }
            dataSource = UICollectionViewDiffableDataSource(collectionView: view) {
                [unowned self] view, indexPath, id in
                view.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: id)
            }
        }

        func apply(_ items: [TrayItem]) {
            shown = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            var snapshot = NSDiffableDataSourceSnapshot<Int, UUID>()
            snapshot.appendSections([0])
            snapshot.appendItems(items.map(\.id))
            // Everything that survives the update is reconfigured, because
            // selection and edit mode are read inside the cell's content and
            // the diff alone would not notice them changing.
            let carried = Set(dataSource.snapshot().itemIdentifiers)
            snapshot.reconfigureItems(items.map(\.id).filter(carried.contains))
            dataSource.apply(snapshot, animatingDifferences: true)
        }

        // MARK: - Selection

        func collectionView(_ view: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            guard let id = dataSource.itemIdentifier(for: indexPath) else { return }
            guard parent.isSelecting else {
                // Outside selection mode a tap opens the item. The cell must
                // not stay selected behind the preview.
                view.deselectItem(at: indexPath, animated: false)
                if let item = shown[id] { parent.onOpen(item) }
                return
            }
            parent.selection.insert(id)
            reconfigure(id)
        }

        func collectionView(_ view: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
            guard let id = dataSource.itemIdentifier(for: indexPath) else { return }
            parent.selection.remove(id)
            reconfigure(id)
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
                ? parent.items.map(\.id).filter(parent.selection.contains)
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

        private func dragItem(for item: TrayItem) -> UIDragItem {
            let drag = UIDragItem(itemProvider: TrayDragProvider.provider(for: item, model: parent.model))
            // Identifies the item to `itemsForAddingTo` above; never read as
            // anything but a de-duplication key.
            drag.localObject = item.id
            return drag
        }
    }
}

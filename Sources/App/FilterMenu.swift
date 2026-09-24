import SwiftUI

/// The funnel: which kinds, and how recent.
///
/// One view for the boards and the search screen, because a filter that
/// behaves differently depending on where it is would be worse than no filter
/// at all.
struct FilterMenu: View {
    @Binding var filter: TrayFilter

    var body: some View {
        Menu {
            Section(L.s("filter.kind")) {
                ForEach(TrayItemKind.allCases, id: \.self) { kind in
                    Button {
                        if filter.kinds.contains(kind) {
                            filter.kinds.remove(kind)
                        } else {
                            filter.kinds.insert(kind)
                        }
                    } label: {
                        Label(
                            L.s("kind.\(kind.rawValue)"),
                            systemImage: filter.kinds.contains(kind) ? "checkmark" : ""
                        )
                    }
                }
            }
            Section(L.s("filter.added")) {
                Picker(L.s("filter.added"), selection: $filter.window) {
                    Text(L.s("filter.any")).tag(TrayFilter.Window?.none)
                    Text(L.s("filter.day")).tag(TrayFilter.Window?.some(.day))
                    Text(L.s("filter.week")).tag(TrayFilter.Window?.some(.week))
                    Text(L.s("filter.month")).tag(TrayFilter.Window?.some(.month))
                }
            }
            if filter.isActive {
                Section {
                    Button(role: .destructive) {
                        // The text is the search field's, not the funnel's;
                        // clearing it from here would empty a field the user
                        // is still typing in.
                        filter.kinds = []
                        filter.window = nil
                    } label: {
                        Label(L.s("filter.clear"), systemImage: "xmark.circle")
                    }
                }
            }
        } label: {
            // The same colour as the buttons beside it; a filter in effect
            // shows as a circle around the funnel. Only for what this menu
            // itself sets: typing in the search field is visible in the field.
            // A Label, not a bare Image: when the bar is too narrow (iPad
            // Slide Over) this item collapses into the overflow menu, which
            // lists it by its title.
            Label(L.s("filter.title"), systemImage: hasFunnelFilters ? "line.3.horizontal.decrease.circle"
                                                                     : "line.3.horizontal.decrease")
        }
    }

    private var hasFunnelFilters: Bool { !filter.kinds.isEmpty || filter.window != nil }
}

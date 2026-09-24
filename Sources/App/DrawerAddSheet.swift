import PhotosUI
import SwiftUI

/// Adds or edits one shortcut: pick a kind, fill its detail, optionally attach
/// a square custom icon. Installed-app picking only exists on TrollStore.
struct DrawerAddSheet: View {
    enum Kind: String, CaseIterable {
        case installedApp, shortcut, urlScheme, webURL
    }

    @Environment(\.dismiss) private var dismiss
    @State private var kind: Kind = .webURL
    @State private var name = ""
    @State private var value = ""             // scheme / url / shortcut name
    @State private var bundleID = ""          // installed app
    @State private var iconItem: PhotosPickerItem?
    @State private var iconData: Data?
    /// The picked photo, waiting for the square crop before it becomes `iconData`.
    @State private var cropping: UIImage?
    private let existingID: UUID?
    /// The icon already on disk when editing, kept unless the picker above
    /// replaces it -- without this, saving an edit without touching the icon
    /// field would drop the custom icon back to the kind's default.
    private let existingIconName: String?
    private let onSave: (DrawerShortcut) -> Void

    init(existing: DrawerShortcut? = nil, onSave: @escaping (DrawerShortcut) -> Void) {
        self.existingID = existing?.id
        self.existingIconName = existing?.customIconName
        self.onSave = onSave
        if let e = existing {
            _name = State(initialValue: e.displayName)
            switch e.kind {
            case .installedApp(let b): _kind = State(initialValue: .installedApp); _bundleID = State(initialValue: b)
            case .shortcut(let n): _kind = State(initialValue: .shortcut); _value = State(initialValue: n)
            case .urlScheme(let s): _kind = State(initialValue: .urlScheme); _value = State(initialValue: s)
            case .webURL(let s): _kind = State(initialValue: .webURL); _value = State(initialValue: s)
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker(L.s("drawer.kind"), selection: $kind) {
                    #if TROLLSTORE
                    Text(L.s("drawer.kind.app")).tag(Kind.installedApp)
                    #endif
                    Text(L.s("drawer.kind.shortcut")).tag(Kind.shortcut)
                    Text(L.s("drawer.kind.scheme")).tag(Kind.urlScheme)
                    Text(L.s("drawer.kind.web")).tag(Kind.webURL)
                }
                detail
                TextField(L.s("drawer.name"), text: $name)
                PhotosPicker(selection: $iconItem, matching: .images) {
                    HStack {
                        Text(L.s("drawer.customIcon"))
                        Spacer()
                        if let preview = iconPreview {
                            Image(uiImage: preview).resizable().frame(width: 36, height: 36)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            .navigationTitle(L.s("drawer.add"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L.s("common.save"), action: save).disabled(!valid) }
                ToolbarItem(placement: .cancellationAction) { Button(L.s("common.cancel")) { dismiss() } }
            }
            .onChange(of: iconItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        cropping = UIImage(data: data)
                    }
                    // Cleared so picking the same photo again still fires.
                    iconItem = nil
                }
            }
            .fullScreenCover(isPresented: Binding(get: { cropping != nil }, set: { if !$0 { cropping = nil } })) {
                if let image = cropping {
                    ImageCropView(image: image) { iconData = $0.jpegData(compressionQuality: 0.85) }
                }
            }
        }
    }

    @ViewBuilder private var detail: some View {
        switch kind {
        case .installedApp:
            #if TROLLSTORE
            NavigationLink(bundleID.isEmpty ? L.s("drawer.pickApp") : bundleID) {
                InstalledAppPicker { app in bundleID = app.bundleID; if name.isEmpty { name = app.name } }
            }
            #else
            EmptyView()
            #endif
        case .shortcut: TextField(L.s("drawer.shortcutName"), text: $value)
        case .urlScheme: TextField("myapp://", text: $value).autocapitalization(.none)
        case .webURL: TextField("https://…", text: $value).autocapitalization(.none)
        }
    }

    private var iconPreview: UIImage? {
        if let iconData { return UIImage(data: iconData) }
        guard let name = existingIconName,
              let data = try? Data(contentsOf: DrawerStore.shared.dir.appendingPathComponent(name))
        else { return nil }
        return UIImage(data: data)
    }

    /// `value` is trimmed before being judged non-empty: a field with only
    /// whitespace would otherwise pass and leave the widget an unusable
    /// launch string once it's trimmed again on save.
    private var valid: Bool {
        switch kind {
        case .installedApp: return !bundleID.isEmpty
        default: return !value.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func save() {
        let id = existingID ?? UUID()
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        let k: DrawerKind = {
            switch kind {
            case .installedApp: return .installedApp(bundleID: bundleID)
            case .shortcut: return .shortcut(name: trimmed)
            case .urlScheme: return .urlScheme(trimmed)
            case .webURL: return .webURL(trimmed)
            }
        }()
        let iconName: String? = iconData.map { DrawerStore.shared.writeIcon($0, for: id) } ?? existingIconName
        onSave(DrawerShortcut(id: id, kind: k,
                              displayName: name.isEmpty ? defaultName(k) : name,
                              customIconName: iconName, order: 0))
        dismiss()
    }

    private func defaultName(_ k: DrawerKind) -> String {
        switch k {
        case .installedApp(let b): return b
        case .shortcut(let n): return n
        case .urlScheme(let s), .webURL(let s): return s
        }
    }
}

#if TROLLSTORE
struct InstalledAppPicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apps: [InstalledApp] = []
    let onPick: (InstalledApp) -> Void
    var body: some View {
        List(apps, id: \.bundleID) { app in
            Button { onPick(app); dismiss() } label: {
                HStack {
                    if let icon = app.icon { Image(uiImage: icon).resizable().frame(width: 32, height: 32).clipShape(RoundedRectangle(cornerRadius: 7)) }
                    Text(app.name)
                }
            }
        }
        .task { apps = InstalledApps.all() }
        .navigationTitle(L.s("drawer.pickApp"))
    }
}
#endif

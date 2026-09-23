import SwiftUI

/// A strip under a board while a pass or a download is running, and after
/// one failed. Tapping it opens the details.
struct CloudStatusBar: View {
    let cloud: CloudSync
    @State private var showsDetails = false

    var body: some View {
        if cloud.isEnabled, cloud.total > 0 || !cloud.downloading.isEmpty || cloud.lastError != nil {
            Button { showsDetails = true } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: cloud.lastError == nil ? "icloud" : "exclamationmark.icloud")
                        Text(summary).lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption2)
                    }
                    .font(.footnote)
                    if cloud.isSyncing, cloud.total > 0 {
                        ProgressView(value: Double(cloud.done), total: Double(cloud.total))
                    } else if !cloud.downloading.isEmpty {
                        // iCloud reports no byte counts for a folder outside
                        // the app's own container, so only that it is running.
                        ProgressView().progressViewStyle(.linear)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.bar)
            }
            .buttonStyle(.plain)
            .foregroundStyle(cloud.lastError == nil ? Color.primary : Color.red)
            .sheet(isPresented: $showsDetails) {
                NavigationStack {
                    CloudSyncView(cloud: cloud)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button(L.s("common.done")) { showsDetails = false }
                            }
                        }
                }
            }
        }
    }

    private var summary: String {
        if !cloud.downloading.isEmpty { return L.s("cloud.status.downloading", cloud.downloading.count) }
        if cloud.isSyncing, cloud.total > 0 { return L.s("cloud.status.syncing", cloud.done, cloud.total) }
        return cloud.lastError ?? ""
    }
}

/// Where the tray syncs to, how it is going, and what it last did.
struct CloudSyncView: View {
    let cloud: CloudSync

    var body: some View {
        List {
            Section {
                LabeledContent(L.s("cloud.folder"), value: cloud.folderName ?? "—")
                LabeledContent(
                    L.s("cloud.last"),
                    value: cloud.lastSync?.formatted(date: .abbreviated, time: .standard) ?? L.s("cloud.never")
                )
                if cloud.isSyncing, cloud.total > 0 {
                    ProgressView(value: Double(cloud.done), total: Double(cloud.total)) {
                        Text(L.s("cloud.status.syncing", cloud.done, cloud.total)).font(.footnote)
                    }
                }
                LabeledContent(L.s("cloud.pendingUploads"), value: "\(cloud.pendingUploads)")
                LabeledContent(L.s("cloud.cloudOnly"), value: "\(cloud.cloudOnly.count)")
                if let error = cloud.lastError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
            if !cloud.downloading.isEmpty {
                Section(L.s("cloud.status.downloading", cloud.downloading.count)) {
                    ForEach(cloud.cloudOnly.filter { cloud.downloading.contains($0.id) }) { item in
                        HStack {
                            Text(item.name).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            ProgressView()
                        }
                    }
                }
            }
            Section(L.s("cloud.log")) {
                if cloud.log.isEmpty {
                    Text(L.s("cloud.log.empty")).foregroundStyle(.secondary)
                }
                ForEach(Array(cloud.log.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.system(.caption, design: .monospaced))
                }
            }
        }
        .navigationTitle(L.s("cloud.details"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The sync switch, and under it the folder while the switch is on.
struct CloudSettingsSection: View {
    let model: TrayModel
    @State private var picking = false

    var body: some View {
        @Bindable var cloud = model.cloud
        Section {
            Toggle(L.s("cloud.toggle"), isOn: $cloud.isOn)
                .onChange(of: cloud.isOn) { _, on in
                    if on { Task { await model.syncCloud() } }
                }
            if cloud.isOn {
                if cloud.folderName != nil {
                    LabeledContent(L.s("cloud.folder"), value: cloud.folderName ?? "")
                    NavigationLink(L.s("cloud.details")) { CloudSyncView(cloud: cloud) }
                    Button(L.s("cloud.syncNow")) { Task { await model.syncCloud() } }
                        .disabled(cloud.isSyncing)
                    Button(L.s("cloud.change")) { picking = true }
                    Button(L.s("cloud.off"), role: .destructive) { cloud.turnOff() }
                } else {
                    Button(L.s("cloud.choose")) { picking = true }
                }
            }
        } header: {
            Text(L.s("cloud.section"))
        } footer: {
            Text(L.s(!cloud.isOn ? "cloud.footer.disabled" : cloud.folderName != nil ? "cloud.footer.on" : "cloud.footer.off"))
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            model.cloud.choose(url)
            Task { await model.syncCloud() }
        }
    }
}

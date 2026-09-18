import SwiftUI
import UniformTypeIdentifiers

struct TrayView: View {
    @State private var isTargeted = false
    @State private var dropCount = 0

    var body: some View {
        VStack(spacing: 12) {
            Text("IslandTray")
                .font(.largeTitle.bold())
            Text("dropped: \(dropCount)")
                .font(.title2.monospacedDigit())
            Text(isTargeted ? "release to drop" : "drag something here")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isTargeted ? Color.accentColor.opacity(0.15) : Color.clear)
        .onDrop(of: [UTType.item], isTargeted: $isTargeted) { providers in
            dropCount += providers.count
            return true
        }
    }
}

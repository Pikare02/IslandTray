import SwiftUI
import UIKit

/// Shared by the expanded Dynamic Island and the Lock Screen presentation.
///
/// Reads thumbnail files straight from the container. Without the App Group
/// entitlement that container is unreachable from this process, so each preview
/// falls back to the SF Symbol carried in the content state.
struct TrayPreviewStrip: View {
    let previews: [TrayContentState.Preview]
    var side: CGFloat = 36

    var body: some View {
        HStack(spacing: 6) {
            ForEach(previews, id: \.id) { preview in
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(.white.opacity(0.14))
                    if let image = thumbnail(for: preview) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    } else {
                        Image(systemName: preview.symbol)
                            .font(.system(size: side * 0.42))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .frame(width: side, height: side)
            }
        }
    }

    private func thumbnail(for preview: TrayContentState.Preview) -> UIImage? {
        guard TrayContainer.isShared else { return nil }
        let url = TrayContainer.thumbsDirectory.appendingPathComponent("\(preview.id).png")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}

import SwiftUI
import UIKit

/// Pan/pinch a photo under a fixed crop window and hand back that crop. The
/// image always covers the window (aspect fill at scale 1, offsets clamped),
/// so the crop never contains empty space.
///
/// `aspect` (width / height) shapes the window: 1 for a square drawer icon,
/// the screen's portrait ratio for a drawer background. `outputMaxDimension`
/// is the longer edge of the rendered result.
struct ImageCropView: View {
    let image: UIImage
    var aspect: CGFloat = 1
    var outputMaxDimension: CGFloat = 256
    let onDone: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var win: CGSize = CGSize(width: 1, height: 1)

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let win = window(in: geo.size)
                let base = baseSize(win)
                // Overlays on a screen-sized base, not a ZStack: the zoomed
                // image is wider than the screen and would grow a ZStack,
                // shifting the dimming mask off the crop window.
                Color.black
                    .overlay {
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: base.width * scale, height: base.height * scale)
                            .offset(offset)
                    }
                    .overlay {
                        // Dim everything outside the crop window.
                        Path { p in
                            p.addRect(CGRect(origin: .zero, size: geo.size))
                            p.addRect(CGRect(x: (geo.size.width - win.width) / 2,
                                             y: (geo.size.height - win.height) / 2,
                                             width: win.width, height: win.height))
                        }
                        .fill(.black.opacity(0.6), style: FillStyle(eoFill: true))
                    }
                    .overlay {
                        Rectangle().strokeBorder(.white, lineWidth: 1)
                            .frame(width: win.width, height: win.height)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { v in
                            offset = clamp(CGSize(width: lastOffset.width + v.translation.width,
                                                  height: lastOffset.height + v.translation.height),
                                           base: base, win: win)
                        }
                        .onEnded { _ in lastOffset = offset }
                        .simultaneously(with: MagnifyGesture()
                            .onChanged { v in
                                scale = min(max(1, lastScale * v.magnification), 8)
                                offset = clamp(offset, base: base, win: win)
                            }
                            .onEnded { _ in lastScale = scale; lastOffset = offset })
                )
                .onAppear { self.win = win }
                .onChange(of: win) { _, w in self.win = w }
            }
            .ignoresSafeArea(edges: .bottom)
            .background(Color.black)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L.s("common.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.s("common.done")) { onDone(render()); dismiss() }
                }
            }
        }
    }

    /// Largest window of `aspect` that fits the area with a 16pt margin.
    private func window(in area: CGSize) -> CGSize {
        let maxW = max(1, area.width - 32)
        let maxH = max(1, area.height - 32)
        if maxW / maxH > aspect {
            return CGSize(width: maxH * aspect, height: maxH)
        }
        return CGSize(width: maxW, height: maxW / aspect)
    }

    /// The image's on-screen size at scale 1: aspect fill of the window.
    private func baseSize(_ win: CGSize) -> CGSize {
        let k = max(win.width / max(1, image.size.width), win.height / max(1, image.size.height))
        return CGSize(width: image.size.width * k, height: image.size.height * k)
    }

    private func clamp(_ o: CGSize, base: CGSize, win: CGSize) -> CGSize {
        let maxX = max(0, (base.width * scale - win.width) / 2)
        let maxY = max(0, (base.height * scale - win.height) / 2)
        return CGSize(width: min(max(o.width, -maxX), maxX), height: min(max(o.height, -maxY), maxY))
    }

    /// Maps the window back into image points and redraws just that region.
    private func render() -> UIImage {
        let shown = baseSize(win)
        let display = CGSize(width: shown.width * scale, height: shown.height * scale)
        let toImage = image.size.width / display.width
        let cropX = (display.width / 2 - offset.width - win.width / 2) * toImage
        let cropY = (display.height / 2 - offset.height - win.height / 2) * toImage
        let out = aspect >= 1
            ? CGSize(width: outputMaxDimension, height: outputMaxDimension / aspect)
            : CGSize(width: outputMaxDimension * aspect, height: outputMaxDimension)
        let f = out.width / (win.width * toImage)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: out, format: format).image { _ in
            image.draw(in: CGRect(x: -cropX * f, y: -cropY * f,
                                  width: image.size.width * f, height: image.size.height * f))
        }
    }
}

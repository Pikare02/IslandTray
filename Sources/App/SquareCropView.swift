import SwiftUI
import UIKit

/// Pan/pinch a photo under a fixed square window and hand back that square,
/// for a drawer icon. The image always covers the window (aspect fill at
/// scale 1, offsets clamped), so the crop never contains empty space.
struct SquareCropView: View {
    let image: UIImage
    let onDone: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var side: CGFloat = 1

    /// Output edge in pixels; the island tile is 64px, the drawer grid ~52pt.
    private static let outputSide: CGFloat = 256

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height) - 32
                let base = baseSize(side)
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
                        // Dim everything outside the square.
                        Path { p in
                            p.addRect(CGRect(origin: .zero, size: geo.size))
                            p.addRect(CGRect(x: (geo.size.width - side) / 2, y: (geo.size.height - side) / 2,
                                             width: side, height: side))
                        }
                        .fill(.black.opacity(0.6), style: FillStyle(eoFill: true))
                    }
                    .overlay { Rectangle().strokeBorder(.white, lineWidth: 1).frame(width: side, height: side) }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { v in
                            offset = clamp(CGSize(width: lastOffset.width + v.translation.width,
                                                  height: lastOffset.height + v.translation.height),
                                           base: base, side: side)
                        }
                        .onEnded { _ in lastOffset = offset }
                        .simultaneously(with: MagnifyGesture()
                            .onChanged { v in
                                scale = min(max(1, lastScale * v.magnification), 8)
                                offset = clamp(offset, base: base, side: side)
                            }
                            .onEnded { _ in lastScale = scale; lastOffset = offset })
                )
                .onAppear { self.side = side }
                .onChange(of: side) { _, s in self.side = s }
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

    /// The image's on-screen size at scale 1: aspect fill of the square.
    private func baseSize(_ side: CGFloat) -> CGSize {
        let k = side / max(1, min(image.size.width, image.size.height))
        return CGSize(width: image.size.width * k, height: image.size.height * k)
    }

    private func clamp(_ o: CGSize, base: CGSize, side: CGFloat) -> CGSize {
        let maxX = max(0, (base.width * scale - side) / 2)
        let maxY = max(0, (base.height * scale - side) / 2)
        return CGSize(width: min(max(o.width, -maxX), maxX), height: min(max(o.height, -maxY), maxY))
    }

    /// Maps the window back into image points and redraws just that square.
    private func render() -> UIImage {
        let shown = baseSize(side)
        let display = CGSize(width: shown.width * scale, height: shown.height * scale)
        let toImage = image.size.width / display.width
        let cropX = (display.width / 2 - offset.width - side / 2) * toImage
        let cropY = (display.height / 2 - offset.height - side / 2) * toImage
        let f = Self.outputSide / (side * toImage)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: Self.outputSide, height: Self.outputSide), format: format)
            .image { _ in
                image.draw(in: CGRect(x: -cropX * f, y: -cropY * f,
                                      width: image.size.width * f, height: image.size.height * f))
            }
    }
}

import SwiftUI
import UIKit

struct Lightbox: View {
    let image: UIImage
    let onDismiss: () -> Void

    @State private var drag: CGSize = .zero
    @State private var zoom: CGFloat = 1.0
    @State private var lastZoom: CGFloat = 1.0
    @State private var pan: CGSize = .zero
    @State private var lastPan: CGSize = .zero
    @GestureState private var isPressed = false

    var body: some View {
        let dismissDrag = DragGesture(minimumDistance: 3)
            .onChanged { value in
                guard zoom <= 1.01 else { return }
                drag = value.translation
            }
            .onEnded { value in
                guard zoom <= 1.01 else { return }
                if value.translation.height > 120 { onDismiss() }
                else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { drag = .zero }
                }
            }

        let magnify = MagnificationGesture()
            .onChanged { value in
                var next = lastZoom * value
                next = max(1.0, min(next, 4.0))
                zoom = next
                if zoom <= 1.01 { pan = .zero; lastPan = .zero }
            }
            .onEnded { _ in
                lastZoom = max(1.0, min(zoom, 4.0))
                if lastZoom <= 1.01 { pan = .zero; lastPan = .zero }
            }

        func clampedPan(_ proposed: CGSize, in geo: GeometryProxy) -> CGSize {
            guard zoom > 1.01 else { return .zero }
            let padding: CGFloat = 32
            let availW = max(1, geo.size.width - padding)
            let availH = max(1, geo.size.height - padding)
            let imgW = max(1, image.size.width)
            let imgH = max(1, image.size.height)
            let availAspect = availW / availH
            let imgAspect = imgW / imgH
            let baseW: CGFloat
            let baseH: CGFloat
            if imgAspect > availAspect {
                baseW = availW
                baseH = baseW / imgAspect
            } else {
                baseH = availH
                baseW = baseH * imgAspect
            }
            let scaledW = baseW * zoom
            let scaledH = baseH * zoom
            let xLimit = max(0, (scaledW - availW) / 2)
            let yLimit = max(0, (scaledH - availH) / 2)
            let cx = min(max(proposed.width, -xLimit), xLimit)
            let cy = min(max(proposed.height, -yLimit), yLimit)
            return CGSize(width: cx, height: cy)
        }

        return GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.95).ignoresSafeArea()
                    .onTapGesture { onDismiss() }

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding()
                    .offset(zoom > 1.01 ? pan : drag)
                    .scaleEffect(zoom)
                    .scaleEffect(zoom > 1.01 ? 1.0 : (1 - max(0, drag.height) / 1200))
                    .gesture(
                        DragGesture(minimumDistance: 3)
                            .onChanged { value in
                                guard zoom > 1.01 else { return }
                                let proposed = CGSize(width: lastPan.width + value.translation.width,
                                                      height: lastPan.height + value.translation.height)
                                pan = clampedPan(proposed, in: geo)
                            }
                            .onEnded { _ in
                                guard zoom > 1.01 else { return }
                                lastPan = clampedPan(pan, in: geo)
                            }
                    )
                    .simultaneousGesture(magnify)
                    .simultaneousGesture(dismissDrag)
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            if zoom > 1.01 {
                                zoom = 1.0; lastZoom = 1.0; pan = .zero; lastPan = .zero
                            } else {
                                zoom = 2.2; lastZoom = 2.2
                            }
                        }
                    }

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.black.opacity(0.35), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
                .padding(.trailing, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
            .animation(.smoothCompat, value: drag)
            .animation(.smoothCompat, value: pan)
            .animation(.smoothCompat, value: zoom)
        }
    }
}

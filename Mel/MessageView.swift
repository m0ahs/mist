import SwiftUI
import UIKit

struct MessageView: View {
    let message: Message
    let onImageTap: (UIImage) -> Void
    var onShare: (([Any]) -> Void)? = nil

    @Environment(\.dynamicTypeSize) private var dType
    private var userTextMaxWidth: CGFloat {
        let base = min(UIScreen.main.bounds.width * 0.70, 340)
        return scaleForDynamicType(dType, base: base)
    }
    private var aiTextMaxWidth: CGFloat {
        let base = min(UIScreen.main.bounds.width * 0.70, 340)
        return scaleForDynamicType(dType, base: base)
    }
    private let maxBubbleWidth:   CGFloat = UIScreen.main.bounds.width * 0.9 // images
    private var bubbleCorner: CGFloat { scaleForDynamicType(dType, base: Theme.bubbleCorner) }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private func formatTime(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if !message.isUser {
                Image("AIAvatar")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Theme.avatarBorder, lineWidth: 1))
                    .shadow(color: .black.opacity(0.06), radius: 2, x: 0, y: 1)
                    .padding(.top, 2)
            } else {
                Spacer(minLength: 32)
            }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
                if let datas = message.imagesData, !datas.isEmpty {
                    AsyncChatImageDeckSwiper(datas: datas, onTapTop: { tapped in
                        onImageTap(tapped)
                    }, singleTiltDegrees: message.isUser ? 2.5 : 0)
                    .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
                    .padding(.trailing, message.isUser ? 10 : 0)
                    .padding(.leading,  message.isUser ? 0  : 10)
                    .contextMenu {
                        if let first = datas.first, let ui = ImageCache.shared.decodeImage(data: first) {
                            Button {
                                UIImageWriteToSavedPhotosAlbum(ui, nil, nil, nil)
                            } label: { Label("Enregistrer l’image", systemImage: "square.and.arrow.down") }
                        }
                        Button {
                            let imgs: [UIImage] = datas.compactMap { ImageCache.shared.decodeImage(data: $0) }
                            if !imgs.isEmpty { onShare?(imgs) }
                        } label: { Label("Partager", systemImage: "square.and.arrow.up") }
                    }
                }

                if let text = message.text {
                    if message.isUser {
                        let raw = text

                        Group {
                            if message.isSearchQuery {
                                let decorated: AttributedString = {
                                    let prefix = NSMutableAttributedString(string: "Search ")
                                    prefix.addAttribute(.foregroundColor, value: UIColor.systemBlue, range: NSRange(location: 0, length: prefix.length))
                                    let queryNS = NSAttributedString(linkified(raw, isUser: true))
                                    let result = NSMutableAttributedString()
                                    result.append(prefix)
                                    result.append(queryNS)
                                    return AttributedString(result)
                                }()
                                Text(decorated).lineSpacing(2).foregroundColor(.black)
                            } else {
                                Text(linkified(raw, isUser: true))
                                    .lineSpacing(2)
                                    .foregroundColor(.black)
                            }
                        }
                        .padding(.horizontal, scaleForDynamicType(dType, base: 16))
                        .padding(.vertical, scaleForDynamicType(dType, base: 12))
                        .background(
                            RoundedRectangle(cornerRadius: bubbleCorner, style: .continuous)
                                .fill(Color.white)
                        )
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: userTextMaxWidth, alignment: .trailing)
                        .contextMenu {
                            Button { UIPasteboard.general.string = raw } label: { Label("Copier", systemImage: "doc.on.doc") }
                            Button { onShare?([raw]) } label: { Label("Partager", systemImage: "square.and.arrow.up") }
                        }
                    } else {
                        Text(linkified(text, isUser: false))
                            .lineSpacing(2)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: aiTextMaxWidth, alignment: .leading)
                            .contextMenu {
                                Button { UIPasteboard.general.string = text } label: { Label("Copier", systemImage: "doc.on.doc") }
                                Button { onShare?([text]) } label: { Label("Partager", systemImage: "square.and.arrow.up") }
                            }
                    }
                }

                Text(formatTime(message.timestamp))
                    .font(.caption2)
                    .foregroundColor(.gray.opacity(0.6))
                    .padding(.top, 2)
                    .padding(message.isUser ? .trailing : .leading, 8)
            }
        }
    }

    private func linkified(_ text: String, isUser: Bool) -> AttributedString {
        var mutable = AttributedString(text)
        if isUser { mutable.foregroundColor = .black }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let ns = NSString(string: text)
        let range = NSRange(location: 0, length: ns.length)
        detector?.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let match = match, let url = match.url else { return }
            if let swiftRange = Range(match.range, in: mutable) {
                mutable[swiftRange].foregroundColor = isUser ? .blue : .primary
                mutable[swiftRange].underlineStyle = .single
                mutable[swiftRange].link = url
            }
        }
        return AttributedString(mutable)
    }
}

private struct ChatImageDeckSquare: View {
    let images: [UIImage]
    let onTap: (UIImage) -> Void
    var singleTiltDegrees: Double = 0.0

    @Environment(\.dynamicTypeSize) private var dType
    private var side: CGFloat { scaleForDynamicType(dType, base: 140) }
    private var corner: CGFloat { scaleForDynamicType(dType, base: Theme.bubbleCorner) }

    var body: some View {
        let imgs = Array(images.suffix(3))
        ZStack {
            ForEach(Array(imgs.enumerated()), id: \.offset) { idx, img in
                let order = idx
                let rot: Double = (imgs.count == 1) ? singleTiltDegrees : [-6, 0, 6][order]
                let off: CGFloat = CGFloat(order) * 10

                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .stroke(Color(.separator).opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.11), radius: 7, x: 0, y: 3)
                    .rotationEffect(.degrees(rot))
                    .offset(x: off, y: -off)
                    .onTapGesture { onTap(img) }
                    .zIndex(Double(order))
            }
        }
        .frame(width: side + 20, height: side + 20, alignment: .center)
        .contentShape(Rectangle())
    }
}

private struct ChatImageDeckSwiper: View {
    let images: [UIImage]
    let onTapTop: (UIImage) -> Void
    var singleTiltDegrees: Double = 0.0

    @State private var topIndex: Int = 0
    @State private var dragX: CGFloat = 0

    @Environment(\.dynamicTypeSize) private var dType
    private var side: CGFloat { scaleForDynamicType(dType, base: 140) }
    private var corner: CGFloat { scaleForDynamicType(dType, base: Theme.bubbleCorner) }

    var body: some View {
        let count = images.count
        let ordered = (0..<count).map { (topIndex + $0) % count }

        ZStack {
            ForEach(Array(ordered.enumerated()), id: \.element) { pos, idx in
                let isTop = (pos == 0)
                let baseOffset: CGFloat = CGFloat(pos) * 10
                let baseRot: Double = (count == 1) ? singleTiltDegrees : [0, -6, 6, -10, 10][min(pos, 4)]

                Image(uiImage: images[idx])
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .stroke(Color(.separator).opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.11), radius: 7, x: 0, y: 3)
                    .rotationEffect(.degrees(baseRot))
                    .offset(x: isTop ? dragX : 0, y: -baseOffset)
                    .scaleEffect(isTop ? 1.0 : 0.98)
                    .zIndex(Double(count - pos))
                    .animation(.smoothCompat, value: topIndex)
                    .onTapGesture { if isTop { onTapTop(images[idx]) } }
            }
        }
        .frame(width: side + 20, height: side + 20)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { v in dragX = v.translation.width }
                .onEnded { v in
                    let vx = v.predictedEndTranslation.width
                    let threshold: CGFloat = 60
                    if vx < -threshold || dragX < -threshold {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        topIndex = (topIndex + 1) % images.count
                    } else if vx > threshold || dragX > threshold {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        topIndex = (topIndex - 1 + images.count) % images.count
                    }
                    withAnimation(.smoothCompat) { dragX = 0 }
                }
        )
    }
}

private struct AsyncChatImageDeckSwiper: View {
    let datas: [Data]
    let onTapTop: (UIImage) -> Void
    var singleTiltDegrees: Double = 0.0

    @State private var uiImages: [UIImage] = []

    var body: some View {
        Group {
            if uiImages.isEmpty {
                ProgressView().task {
                    let decoded: [UIImage] = await Task.detached(priority: .userInitiated) {
                        datas.compactMap { ImageCache.shared.decodeThumbnail(data: $0, maxPixelSize: 900) }
                    }.value
                    await MainActor.run {
                        var tx = Transaction()
                        tx.disablesAnimations = true
                        withTransaction(tx) { self.uiImages = decoded }
                    }
                }
            } else {
                ChatImageDeckSwiper(images: uiImages, onTapTop: onTapTop, singleTiltDegrees: singleTiltDegrees)
            }
        }
    }
}

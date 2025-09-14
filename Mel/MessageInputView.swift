import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct MessageInputView: View {
    @Binding var newMessage: String
    @Binding var isSearchMode: Bool
    @FocusState.Binding var isTextFieldFocused: Bool
    let isAIThinking: Bool
    let attachedImages: [Data]
    let onMoveAttachment: (_ from: Int, _ to: Int) -> Void
    let onRemoveAttachment: (Int) -> Void
    let onOpenAttachment: (UIImage) -> Void
    let onSendMessage: () -> Void
    let onCancel: () -> Void
    let onAttachment: () -> Void

    @Environment(\.dynamicTypeSize) private var dType
    private let buttonSize: CGFloat = 28
    private let fieldVerticalPadding: CGFloat = 6
    private let barMinHeight: CGFloat = 36
    private let thumbSide: CGFloat = 100              // taille vignette max
    private let badgeOverhang: CGFloat = 8           // débord du bouton X à l’intérieur
    private let innerVPad: CGFloat = 6                // padding vertical interne du ScrollView
    private var attachmentsRowHeight: CGFloat {       // slot = side + overhang + inner pads
        thumbSide + badgeOverhang + innerVPad * 2
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {

            Button(action: { hapticLight(); onAttachment() }) {
                Image(systemName: "plus")
                    .font(.system(size: scaleForDynamicType(dType, base: 20), weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: scaleForDynamicType(dType, base: 40),
                           height: scaleForDynamicType(dType, base: 40))
                    .background(Color.white, in: Circle())
                    .overlay(
                        Circle().stroke(Color(.separator).opacity(0.18), lineWidth: 1)
                    )
            }
            .disabled(attachedImages.count >= 3)
            .opacity(attachedImages.count >= 3 ? 0.5 : 1)
            .buttonStyle(.plain)

            VStack(spacing: 4) {
                if !attachedImages.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: scaleForDynamicType(dType, base: 10)) {
                            ForEach(Array(attachedImages.enumerated()), id: \.offset) { idx, data in
                                AsyncAttachmentCard(
                                    data: data,
                                    side: thumbSide,
                                    onRemove: { onRemoveAttachment(idx) },
                                    onTap: { img in onOpenAttachment(img) }
                                )
                                .onDrag { NSItemProvider(object: "\(idx)" as NSString) }
                                .onDrop(of: [UTType.text.identifier], isTargeted: nil) { providers in
                                    guard let provider = providers.first else { return false }
                                    var didHandle = false
                                    provider.loadObject(ofClass: NSString.self) { obj, _ in
                                        if let str = obj as? String, let from = Int(str) {
                                            DispatchQueue.main.async {
                                                onMoveAttachment(from, idx)
                                            }
                                            didHandle = true
                                        }
                                    }
                                    return didHandle
                                }
                            }
                            .padding(.horizontal, 2)
                            .padding(.vertical, innerVPad)
                        }
                    }
                    .frame(height: attachmentsRowHeight)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if isSearchMode {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.blue)
                            Text("Search")
                                .font(.callout.weight(.semibold))
                                .foregroundColor(.blue)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.blue.opacity(0.15)))

                        Button {
                            isSearchMode = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.primary)
                                .padding(6)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                HStack(alignment: .center, spacing: scaleForDynamicType(dType, base: 8)) {
                    let binding = Binding<String>(
                        get: { newMessage },
                        set: { val in
                            if !isSearchMode && val.lowercased().hasPrefix("/search ") {
                                isSearchMode = true
                                newMessage = String(val.dropFirst("/search ".count)).trimmingCharacters(in: .whitespaces)
                            } else {
                                newMessage = val
                            }
                        }
                    )

                    TextField(isSearchMode ? "Votre requête…" : "Talk to Mist...", text: binding, axis: .vertical)
                        .font(.body)
                        .foregroundColor(.primary)
                        .focused($isTextFieldFocused)
                        .lineLimit(1...6)

                    if isAIThinking {
                        HStack(spacing: 8) {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .frame(width: scaleForDynamicType(dType, base: 28),
                                       height: scaleForDynamicType(dType, base: 28))
                            Button(action: { onCancel() }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: scaleForDynamicType(dType, base: 20), weight: .semibold))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Annuler la requête")
                        }
                    } else if (!newMessage.isEmpty || !attachedImages.isEmpty) {
                        Button(action: { hapticMedium(); onSendMessage() }) {
                            Circle().fill(Color.black)
                                .frame(width: scaleForDynamicType(dType, base: 28),
                                       height: scaleForDynamicType(dType, base: 28))
                                .overlay(Image(systemName: "arrow.up")
                                    .foregroundColor(.white)
                                    .font(.system(size: scaleForDynamicType(dType, base: 16), weight: .medium)))
                        }
                        .contentShape(Circle())
                        .transition(.scale.combined(with: .opacity))
                    } else {
                        Color.clear.frame(width: scaleForDynamicType(dType, base: 28),
                                          height: scaleForDynamicType(dType, base: 28))
                    }
                }
                .padding(.horizontal, scaleForDynamicType(dType, base: 16))
                .padding(.vertical, scaleForDynamicType(dType, base: 6))
                .background(RoundedRectangle(cornerRadius: Theme.inputCorner).fill(Theme.inputBackground))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .animation(.smoothCompat, value: isTextFieldFocused)
        .animation(.spring(response: 0.55, dampingFraction: 0.85), value: isSearchMode)
    }

    private func hapticLight() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    private func hapticMedium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

private struct AttachmentCard: View {
    let image: UIImage
    let onRemove: () -> Void
    let onTap: () -> Void
    let side: CGFloat
    @State private var dragOffset: CGFloat = 0

    private let corner: CGFloat = 18

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.medium)
                .antialiased(true)
                .aspectRatio(1, contentMode: .fit)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .stroke(Color(.separator).opacity(0.18), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                .offset(y: -dragOffset)
                .gesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { v in dragOffset = max(0, -v.translation.height) }
                        .onEnded { _ in
                            if dragOffset > 28 { onRemove() }
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { dragOffset = 0 }
                        }
                )
                .onTapGesture { onTap() }
                .overlay(alignment: .topTrailing) {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.primary)
                            .padding(6)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().stroke(Color(.separator).opacity(0.18), lineWidth: 1))
                            .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                }
        }
        .contextMenu {
            Button(role: .destructive) { onRemove() } label: { Label("Retirer", systemImage: "trash") }
            Button { onTap() } label: { Label("Agrandir", systemImage: "arrow.up.left.and.arrow.down.right") }
        }
    }
}

private struct AsyncAttachmentCard: View {
    let data: Data
    let side: CGFloat
    let onRemove: () -> Void
    let onTap: (UIImage) -> Void

    @State private var image: UIImage? = nil

    var body: some View {
        Group {
            if let img = image {
                AttachmentCard(image: img, onRemove: onRemove, onTap: { onTap(img) }, side: side)
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
                    .frame(width: side, height: side)
                    .overlay(
                        ProgressView()
                            .progressViewStyle(.circular)
                    )
            }
        }
        .task(id: data) {
            let decoded: UIImage? = await Task.detached(priority: .userInitiated) {
                ImageCache.shared.decodeThumbnail(data: data, maxPixelSize: 640)
            }.value
            await MainActor.run {
                var tx = Transaction()
                tx.disablesAnimations = true
                withTransaction(tx) { self.image = decoded }
            }
        }
    }
}

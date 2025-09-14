import SwiftUI

struct AttachmentSheet: View {
    @Binding var isPresented: Bool
    var takePhoto: () -> Void
    var openLibrary: () -> Void

    @State private var offset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            if isPresented {
                Color.black.opacity(0.10)
                    .ignoresSafeArea()
                    .transition(.opacity.animation(.easeInOut(duration: 0.25)))
                    .onTapGesture { dismiss() }
            }

            if isPresented {
                VStack(spacing: 0) {
                    Capsule().fill(Color.secondary.opacity(0.35))
                        .frame(width: 36, height: 5)
                        .padding(.top, 8)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        ActionRow(systemName: "camera.fill", title: "Prendre une photo", action: takePhoto)
                        Divider().opacity(0.08)
                        ActionRow(systemName: "photo.on.rectangle", title: "Choisir une photo", action: openLibrary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                }
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Theme.modalBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Theme.separatorStroke, lineWidth: 1)
                        )
                )
                .compositingGroup()
                .offset(y: offset)
                .gesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { value in
                            offset = max(0, value.translation.height)
                        }
                        .onEnded { value in
                            if value.translation.height > 120 { dismiss(); return }
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                                offset = 0
                            }
                        }
                )
                .padding(.horizontal, 10)
                .padding(.bottom, 32)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: isPresented)
            }
        }
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            isPresented = false
        }
    }
}

private struct ActionRow: View {
    let systemName: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                        .frame(width: 42, height: 42)
                    Image(systemName: systemName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
                        .opacity(0.9)
                }

                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundColor(.primary)

                Spacer()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

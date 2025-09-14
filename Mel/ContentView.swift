//
//  ContentView.swift
//  Mel
//
//  Created by Joseph Mbai Bisso on 14.09.2025.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import Photos
import ImageIO

// MARK: - Helpers

private func clamp(_ v: CGFloat, _ minV: CGFloat = 0, _ maxV: CGFloat = 1) -> CGFloat {
    return max(minV, min(maxV, v))
}

// Early downscale utility: cap longest side and compress to JPEG
private func earlyDownscale(image: UIImage, maxDimension: CGFloat = 2048, quality: CGFloat = 0.82) -> Data? {
    let size = image.size
    guard size.width > 0, size.height > 0 else { return image.jpegData(compressionQuality: quality) ?? image.pngData() }
    let maxSide = max(size.width, size.height)
    let scale = min(1.0, maxDimension / maxSide)
    let target = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
    let renderer = UIGraphicsImageRenderer(size: target)
    let scaled = renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: target))
    }
    return scaled.jpegData(compressionQuality: quality) ?? image.pngData()
}

private func earlyDownscale(data: Data, maxDimension: CGFloat = 2048, quality: CGFloat = 0.82) -> Data? {
    // Thread-safe path using ImageIO (no UIKit), safe in PHPicker callbacks
    guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return data }
    var maxPixel = Int(maxDimension)
    if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
        let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
        let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
        if w > 0, h > 0 {
            let maxSide = max(w, h)
            let scale = min(1.0, Double(maxDimension) / maxSide)
            maxPixel = max(1, Int(maxSide * scale))
        }
    }
    let opts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixel
    ]
    guard let cgThumb = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
        return data
    }
    let outData = CFDataCreateMutable(nil, 0)!
    guard let dest = CGImageDestinationCreateWithData(outData, UTType.jpeg.identifier as CFString, 1, nil) else {
        return data
    }
    let destOpts: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
    CGImageDestinationAddImage(dest, cgThumb, destOpts as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { return data }
    return outData as Data
}

/// Courbe douce (cubic Hermite) pour éviter les à-coups visuels.
private func smoothstep(_ x: CGFloat) -> CGFloat {
    let t = clamp(x)
    return t * t * (3 - 2 * t)
}

extension Animation {
    static var smoothCompat: Animation {
        if #available(iOS 17.0, *) {
            return .smooth(duration: 0.28, extraBounce: 0)
        } else {
            return .easeOut(duration: 0.28)
        }
    }
}

// MARK: - Dynamic Type scaling
@inline(__always)
private func scaleForDynamicType(_ size: DynamicTypeSize, base: CGFloat) -> CGFloat {
    switch size {
    case .xSmall: return base * 0.9
    case .small: return base * 0.95
    case .medium: return base * 1.0
    case .large: return base * 1.05
    case .xLarge: return base * 1.1
    case .xxLarge: return base * 1.15
    case .xxxLarge: return base * 1.2
    case .accessibility1: return base * 1.28
    case .accessibility2: return base * 1.36
    case .accessibility3: return base * 1.44
    case .accessibility4: return base * 1.54
    case .accessibility5: return base * 1.64
    @unknown default: return base * 1.0
    }
}

// Mesure de la hauteur de la barre d'input
private struct InputBarHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// MARK: - Photos Authorization

enum PhotoAuthState {
    case notDetermined, limited, authorized, denied
}

func currentPhotoAuthState() -> PhotoAuthState {
    let s = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    switch s {
    case .notDetermined: return .notDetermined
    case .limited:       return .limited
    case .authorized:    return .authorized
    case .denied, .restricted: return .denied
    @unknown default:    return .denied
    }
}

func requestPhotoAccessIfNeeded(_ completion: @escaping (PhotoAuthState) -> Void) {
    let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    if status == .notDetermined {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in
            DispatchQueue.main.async { completion(currentPhotoAuthState()) }
        }
    } else {
        completion(currentPhotoAuthState())
    }
}

// MARK: - Model

/// État d'envoi par message pour afficher "sending/failed" et permettre Retry.
enum SendStatus: Equatable { case sending, sent, failed(String?) }

/// Un message peut contenir du texte, une image, ou les deux.
/// → Un seul timestamp pour l’ensemble, donc plus le “double envoi”.
struct Message: Identifiable, Equatable {
    let id = UUID()
    var text: String?
    var imagesData: [Data]? // multiple images support
    let isUser: Bool
    let timestamp: Date
    var status: SendStatus
    var isSearchQuery: Bool

    init(text: String? = nil, imagesData: [Data]? = nil, isUser: Bool, status: SendStatus = .sent, isSearchQuery: Bool = false) {
        self.text = text?.isEmpty == true ? nil : text
        self.imagesData = (imagesData?.isEmpty == true) ? nil : imagesData
        self.isUser = isUser
        self.timestamp = Date()
        self.status = status
        self.isSearchQuery = isSearchQuery
    }

    static func == (lhs: Message, rhs: Message) -> Bool { lhs.id == rhs.id }
}

// MARK: - ContentView

struct ContentView: View {
        @State private var messages: [Message] = []
        @State private var newMessage = ""
        @FocusState private var isTextFieldFocused: Bool
        @StateObject private var aiManager = AIManager()

    @State private var scrollPosition: CGPoint = .zero
    @State private var showPhotoPicker = false
    @State private var showAttachmentOptions = false
    @State private var showCamera = false
    @State private var pendingAttachments: [Data] = []
    @State private var lightboxImage: UIImage? = nil
    @State private var photoAuth: PhotoAuthState = currentPhotoAuthState()
    @State private var scrollToBottomTrigger: Int = 0
        @State private var minScrollY: CGFloat = 0
        @State private var showScrollToBottom: Bool = false
    @State private var inputBarHeight: CGFloat = 0
    @State private var currentSendTask: Task<Void, Never>? = nil
    @State private var inFlightMessageID: UUID? = nil
        @State private var shareItems: [Any]? = nil
    @State private var isSearchMode: Bool = false

    // Tweaks pour le header/footer
    private let headerHeight: CGFloat = 66
    private let fadeDistanceHeader: CGFloat = 110

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                // Zone de contenu
                conversationList

                // Zone de saisie
                MessageInputView(
                    newMessage: $newMessage,
                    isSearchMode: $isSearchMode,
                    isTextFieldFocused: $isTextFieldFocused,
                    isAIThinking: aiManager.currentState == .thinking || aiManager.currentState == .responding,
                    attachedImages: pendingAttachments,
                    onMoveAttachment: { from, to in
                        guard from != to,
                              pendingAttachments.indices.contains(from)
                        else { return }
                        var target = to
                        if target < 0 { target = 0 }
                        if target >= pendingAttachments.count { target = pendingAttachments.count - 1 }
                        let moved = pendingAttachments.remove(at: from)
                        let insertIndex = from < target ? max(0, target - 1) : target
                        pendingAttachments.insert(moved, at: insertIndex)
                    },
                    onRemoveAttachment: { index in
                        withAnimation(.smoothCompat) { if pendingAttachments.indices.contains(index) { pendingAttachments.remove(at: index) } }
                    },
                    onOpenAttachment: { img in
                        isTextFieldFocused = false
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { lightboxImage = img }
                    },
                    onSendMessage: sendMessage,
                    onCancel: cancelSend,
                    onAttachment: {
                        isTextFieldFocused = false
                        showAttachmentOptions = true
                    }
                )
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: InputBarHeightKey.self, value: proxy.size.height)
                    }
                )
                .onPreferenceChange(InputBarHeightKey.self) { inputBarHeight = $0 }
            }

            // Header blur + dégradé
            headerOverlay

            // Bandeau d’avertissement si accès limité
            if photoAuth == .limited {
                LimitedLibraryActionView()
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        // Popover pièces jointes
        .overlay(alignment: .bottomLeading) { attachmentOverlay }
        // Bouton pour redescendre en bas
        .overlay(alignment: .bottomTrailing) {
            if showScrollToBottom {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    scrollToBottomTrigger &+= 1
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.primary)
                        .frame(width: 48, height: 48)
                        .background(.regularMaterial, in: Circle())
                        .overlay(Circle().stroke(Theme.separatorStroke, lineWidth: 1))
                        .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 6)
                }
                .padding(.trailing, 16)
                .padding(.bottom, inputBarHeight + 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showScrollToBottom)
            }
        }
        // Lightbox plein écran
        .overlay {
            if let img = lightboxImage {
                Lightbox(image: img) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                        lightboxImage = nil
                    }
                }
                .transition(.opacity.combined(with: .scale))
            }
        }
        // Partage système pour texte/images
        .sheet(isPresented: Binding(get: { shareItems != nil }, set: { if !$0 { shareItems = nil } })) {
            if let items = shareItems { ShareSheet(items: items) }
        }
        .background(Theme.pageBackground)
        .onTapGesture { isTextFieldFocused = false }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { isTextFieldFocused = true }
            requestPhotoAccessIfNeeded { newState in
                photoAuth = newState
            }
        }
        .sheet(isPresented: $showPhotoPicker) {
            LimitedPhotosPicker(maxSelection: max(0, 3 - pendingAttachments.count)) { pickedDatas in
                guard !pickedDatas.isEmpty else { return }
                let availableSlots = max(0, 3 - pendingAttachments.count)
                // Downscale early on the main queue to keep memory low
                let slice = Array(pickedDatas.prefix(availableSlots))
                let downsized: [Data] = slice.compactMap { earlyDownscale(data: $0) }
                withAnimation(.smoothCompat) { pendingAttachments.append(contentsOf: downsized) }
                if downsized.count > 1 { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker { image in
                guard pendingAttachments.count < 3 else { return }
                if let data = earlyDownscale(image: image) {
                    withAnimation(.smoothCompat) { pendingAttachments.append(data) }
                }
            }
        }
    }

    // MARK: - Overlays

    private var conversationList: some View {
        ScrollViewReader { scrollView in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    if messages.isEmpty {
                        WelcomeView(isAIAvailable: aiManager.isAvailable)
                    } else {
                        ForEach(messages) { message in
                            MessageView(
                                message: message,
                                onImageTap: { img in
                                    isTextFieldFocused = false
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                                        lightboxImage = img
                                    }
                                },
                                onShare: { items in
                                    shareItems = items
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 24)
                .padding(.bottom, 20)
                .overlay(
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: geometry.frame(in: .named("scroll")).origin
                        )
                    }
                )
                .overlay(
                    Spacer().id("scrollBottom").frame(height: 1),
                    alignment: .bottom
                )
            }
            .coordinateSpace(name: "scroll")
            .scrollDismissesKeyboard(.interactively)
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                self.scrollPosition = value
                self.minScrollY = min(self.minScrollY, value.y)
                self.showScrollToBottom = value.y > (self.minScrollY + 60)
            }
            .onChange(of: messages) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.smoothCompat) {
                        scrollView.scrollTo("scrollBottom", anchor: .bottom)
                    }
                }
            }
            .onChange(of: aiManager.currentState) { _, newValue in
                if newValue == .responding {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.smoothCompat) {
                            scrollView.scrollTo("scrollBottom", anchor: .bottom)
                        }
                    }
                }
            }
            .onChange(of: isTextFieldFocused) { _, newValue in
                if newValue {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.smoothCompat) {
                            scrollView.scrollTo("scrollBottom", anchor: .bottom)
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.smoothCompat) {
                        scrollView.scrollTo("scrollBottom", anchor: .bottom)
                    }
                }
            }
            .onChange(of: scrollToBottomTrigger) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                    withAnimation(.smoothCompat) {
                        scrollView.scrollTo("scrollBottom", anchor: .bottom)
                    }
                }
            }
        }
    }

    private var headerOverlay: some View {
        // y < 0 quand on scrolle vers le bas
        let y   = scrollPosition.y
        let raw = clamp((-y + 12) / fadeDistanceHeader)
        let t   = smoothstep(raw) // 0→1 pour doser le blur
        let tintOpacity = Double(t) * 0.4

        return ZStack {
            Theme.pageBackground
            Rectangle().fill(.thickMaterial).opacity(Double(t))
                .overlay(Theme.pageBackground.opacity(tintOpacity))
        }
        .frame(height: headerHeight)
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black,               location: 0.00),
                    .init(color: .black,               location: 0.70),
                    .init(color: .black.opacity(0.85), location: 0.86),
                    .init(color: .clear,               location: 1.00)
                ],
                startPoint: .top, endPoint: .bottom
            )
        )
        .compositingGroup()
        .animation(.smoothCompat, value: scrollPosition.y)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var attachmentOverlay: some View {
        if showAttachmentOptions {
            AttachmentSheet(
                isPresented: $showAttachmentOptions,
                takePhoto: {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { showAttachmentOptions = false }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        showCamera = true
                    } else {
                        showPhotoPicker = true
                    }
                },
                openLibrary: {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { showAttachmentOptions = false }
                    showPhotoPicker = true
                }
            )
            .transition(AnyTransition.move(edge: .bottom).combined(with: .opacity))
            .ignoresSafeArea()
        }
    }

    // MARK: - Actions

    /// Construit un seul Message combinant texte + plusieurs images si besoin.
    private func sendMessage() {
        let trimmed = newMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !(trimmed.isEmpty && pendingAttachments.isEmpty) else { return }

        // Use explicit search mode; input already stripped of "/search"
        let isSearchCommand = isSearchMode
        let queryOnly = trimmed

        let outgoing = Message(text: queryOnly.isEmpty ? nil : queryOnly,
                               imagesData: pendingAttachments.isEmpty ? nil : pendingAttachments,
                               isUser: true,
                               status: .sending,
                               isSearchQuery: isSearchCommand)

        withAnimation(.smoothCompat) { messages.append(outgoing) }

        newMessage = ""
        let imagesToSend = pendingAttachments
        pendingAttachments = []
        isTextFieldFocused = true
        inFlightMessageID = outgoing.id
        currentSendTask?.cancel()
        // Commande /search -> exa.ai
        if isSearchCommand {
            let query = queryOnly
            currentSendTask = Task { await performSearchFlow(messageID: outgoing.id, query: query) }
        } else {
            currentSendTask = Task { await performSend(messageID: outgoing.id, text: trimmed, imagesData: imagesToSend) }
        }
    }

    private func updateMessageStatus(id: UUID, to newStatus: SendStatus) {
        if let idx = messages.firstIndex(where: { $0.id == id }) {
            messages[idx].status = newStatus
        }
    }

    private func performSend(messageID: UUID, text: String, imagesData: [Data]) async {
        do {
            let aiResponse = try await aiManager.generateResponse(for: text, imagesData: imagesData)
            await MainActor.run {
                withAnimation(.smoothCompat) {
                    updateMessageStatus(id: messageID, to: .sent)
                    messages.append(Message(text: aiResponse, imagesData: nil, isUser: false))
                }
            }
        } catch {
            await MainActor.run {
                withAnimation(.smoothCompat) {
                    updateMessageStatus(id: messageID, to: .failed(humanizeAIError(error)))
                }
            }
        }
        await MainActor.run {
            currentSendTask = nil
            inFlightMessageID = nil
        }
    }

    private func performSearchFlow(messageID: UUID, query: String) async {
        let svc = ExaService()
        if !svc.isConfigured {
            await MainActor.run { withAnimation(.smoothCompat) { updateMessageStatus(id: messageID, to: .failed("Clé EXA manquante.")) } }
            currentSendTask = nil; inFlightMessageID = nil; return
        }
        do {
            let ans = try await svc.answer(query, limit: 5)

            // Résumé seul (pas de citations)
            let summary = ans.answer.trimmingCharacters(in: .whitespacesAndNewlines)
            let text: String = summary.isEmpty
                ? "Je n’ai pas trouvé de résumé pour « \(query) »."
                : summary

            await MainActor.run {
                withAnimation(.smoothCompat) {
                    updateMessageStatus(id: messageID, to: .sent)
                    messages.append(Message(text: text, imagesData: nil, isUser: false))
                }
            }
        } catch {
            let ns = error as NSError
            let msg: String
            if ns.domain == "ExaService" {
                switch ns.code {
                case -100: msg = "Clé EXA manquante."; default: msg = ns.userInfo[NSLocalizedDescriptionKey] as? String ?? "Erreur EXA."
                }
            } else { msg = error.localizedDescription }
            await MainActor.run { withAnimation(.smoothCompat) { updateMessageStatus(id: messageID, to: .failed(msg)) } }
        }
        await MainActor.run { currentSendTask = nil; inFlightMessageID = nil }
    }

    private func cancelSend() {
        currentSendTask?.cancel()
        if let id = inFlightMessageID {
            withAnimation(.smoothCompat) { updateMessageStatus(id: id, to: .failed("Annulé")) }
        }
        aiManager.resetState()
        currentSendTask = nil
        inFlightMessageID = nil
    }

    private func humanizeAIError(_ error: Error) -> String {
        if (error as? CancellationError) != nil { return "Annulé" }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorTimedOut: return "Temps dépassé. Réessaie."
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost: return "Hors ligne. Vérifie ta connexion."
            case NSURLErrorCancelled: return "Annulé"
            default: break
            }
        }
        if ns.domain == "OpenRouterService" {
            switch ns.code {
            case 401: return "Clé API invalide."
            case 402: return "Crédit requis."
            case 403: return "Accès refusé."
            case 404: return "Modèle introuvable."
            case 409: return "Conflit côté service."
            case 429: return "Trop de requêtes. Réessaie."
            case 500...599: return "Panne côté service. Réessaie."
            default: break
            }
        }
        if ns.domain == "AIManager" && ns.code == -100 { return "Clé API manquante." }
        return "Oups. Je n’ai pas pu répondre. Réessaie."
    }

    // Retry UI supprimé; logique de renvoi conservée via performSend si nécessaire
}

// MARK: - Limited Library Banner

struct LimitedLibraryActionView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Accès limité aux photos")
                .font(.subheadline.weight(.semibold))
            Text("Tu ne vois que les images déjà autorisées. Ajoute d’autres photos ou autorise l’accès complet.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                Button("Choisir d’autres photos") {
                    guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                          let root = scene.keyWindow?.rootViewController else { return }
                    PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: root)
                }
                .buttonStyle(.bordered)

                Button("Autoriser toutes les photos") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(.thinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.separator).opacity(0.18), lineWidth: 1))
        .padding(.horizontal, 16)
    }
}

private extension UIWindowScene {
    var keyWindow: UIWindow? { self.windows.first { $0.isKeyWindow } }
}

// MARK: - Attachment Sheet (file-scope)

private struct AttachmentSheet: View {
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

// MARK: - Action Row (unique)

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

// MARK: - Welcome

struct WelcomeView: View {
    let isAIAvailable: Bool
    var body: some View {
        Spacer()
        VStack(spacing: 20) { /* placeholder */ }
        .padding(.top, 100)
        Spacer()
    }
}

// MARK: - Input Bar

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

    // Search mode is controlled by binding. We still detect the trigger text
    // "/search " to turn it on, then we strip it from the input content.

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {

            // Bouton +
            Button(action: { hapticLight(); onAttachment() }) {
                Image(systemName: "plus")
                    .font(.system(size: scaleForDynamicType(dType, base: 20), weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: scaleForDynamicType(dType, base: 40), height: scaleForDynamicType(dType, base: 40))
                    .background(Color.white, in: Circle())
                    .overlay(
                        Circle().stroke(Color(.separator).opacity(0.18), lineWidth: 1)
                    )
            }
            .disabled(attachedImages.count >= 3)
            .opacity(attachedImages.count >= 3 ? 0.5 : 1)
            .buttonStyle(.plain)

            // Colonne droite = [preview] + [input]
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
                                // Drag & Drop reordering (local): drag index as text
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
                    .frame(height: attachmentsRowHeight)     // contrôle la hauteur du SLOT
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Bulle de mode recherche au-dessus de l'input
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
                            // Quitter le mode recherche
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

                // Champ d'input
                HStack(alignment: .center, spacing: scaleForDynamicType(dType, base: 8)) {
                    let binding = Binding<String>(
                        get: { newMessage },
                        set: { val in
                            // Detect trigger typing
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
                                .frame(width: scaleForDynamicType(dType, base: 28), height: scaleForDynamicType(dType, base: 28))
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
                                .frame(width: scaleForDynamicType(dType, base: 28), height: scaleForDynamicType(dType, base: 28))
                                .overlay(Image(systemName: "arrow.up")
                                    .foregroundColor(.white)
                                    .font(.system(size: scaleForDynamicType(dType, base: 16), weight: .medium)))
                        }
                        .contentShape(Circle())
                        .transition(.scale.combined(with: .opacity))
                    } else {
                        Color.clear.frame(width: scaleForDynamicType(dType, base: 28), height: scaleForDynamicType(dType, base: 28))
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

// MARK: - Message Cell

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

            // Avatar à gauche pour l'AI, placeholder à gauche pour l'utilisateur
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

            // Bulle (image + texte + heure)
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
                        // ===== USER =====
                        let raw = text

                        Group {
                            if message.isSearchQuery {
                                // Prefix "Search " in blue, then the query in normal style
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
                        // ===== AI ===== (pas de fond gris)
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
        // Aligne toute la ligne selon l'auteur et supprime le spacer de DROITE
        .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
        .padding(.vertical, 4)
        .padding(.leading, 0)
        .padding(.trailing, message.isUser ? 2 : 0)
    }
}

// MARK: - Limited Photos Picker (selection limit)

// Link detection helper (URLs -> tappable links with underline)
private extension MessageView {
    func linkified(_ text: String, isUser: Bool) -> AttributedString {
        let nsText = text as NSString
        let mutable = NSMutableAttributedString(string: text)
        var linkedRanges = IndexSet()
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let matches = detector.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
            for m in matches {
                guard m.resultType == .link, let url = m.url else { continue }
                mutable.addAttribute(.link, value: url, range: m.range)
                // Style couleur sans soulignage
                let color = UIColor.systemBlue
                mutable.addAttribute(.foregroundColor, value: color, range: m.range)
                linkedRanges.insert(integersIn: m.range.location..<(m.range.location + m.range.length))
            }
        }

        // www.* without scheme -> assume https
        if let wwwRegex = try? NSRegularExpression(pattern: "(?i)\\bwww\\.[A-Z0-9._%+-\\-~:/?#\\[\\]@!$&'()*+,;=%]+", options: []) {
            let matches = wwwRegex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
            for m in matches {
                if linkedRanges.contains(m.range.location) { continue }
                let raw = nsText.substring(with: m.range)
                if let url = URL(string: "https://\(raw)") {
                    mutable.addAttribute(.link, value: url, range: m.range)
                    let color = UIColor.systemBlue
                    mutable.addAttribute(.foregroundColor, value: color, range: m.range)
                }
            }
        }

        // Email addresses -> mailto:
        if let emailRegex = try? NSRegularExpression(pattern: "(?i)[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}", options: []) {
            let matches = emailRegex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
            for m in matches {
                if linkedRanges.contains(m.range.location) { continue }
                let raw = nsText.substring(with: m.range)
                if let url = URL(string: "mailto:\(raw)") {
                    mutable.addAttribute(.link, value: url, range: m.range)
                    let color = UIColor.systemBlue
                    mutable.addAttribute(.foregroundColor, value: color, range: m.range)
                }
            }
        }

        // Mentions @username (non cliquables, stylisées par la couleur uniquement)
        if let mentionRegex = try? NSRegularExpression(pattern: "(?<![A-Za-z0-9_])@[A-Za-z0-9_\\.]+", options: []) {
            let matches = mentionRegex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
            for m in matches {
                // éviter les collisions avec des liens déjà stylés
                if linkedRanges.contains(m.range.location) { continue }
                let color = UIColor.systemBlue
                mutable.addAttribute(.foregroundColor, value: color, range: m.range)
            }
        }
        return AttributedString(mutable)
    }

    func searchDecorated(_ raw: String) -> AttributedString {
        let lower = raw.lowercased()
        guard lower.hasPrefix("/search") else { return AttributedString(raw) }
        let query = String(raw.dropFirst("/search".count)).trimmingCharacters(in: .whitespaces)

        let result = NSMutableAttributedString()
        // "Search" tag in blue
        let tag = NSMutableAttributedString(string: query.isEmpty ? "Search" : "Search ")
        tag.addAttribute(.foregroundColor, value: UIColor.systemBlue, range: NSRange(location: 0, length: tag.length))
        result.append(tag)
        if !query.isEmpty {
            // Append the query with link styling but default color (will be set per link), otherwise black
            let qAttrAS = linkified(query, isUser: true) // AttributedString
            let qNS = NSAttributedString(qAttrAS)
            result.append(qNS)
        }
        return AttributedString(result)
    }
}

private struct LimitedPhotosPicker: UIViewControllerRepresentable {
    let maxSelection: Int
    let onPicked: ([Data]) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = max(0, maxSelection)
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: LimitedPhotosPicker
        init(_ parent: LimitedPhotosPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !results.isEmpty else {
                parent.dismiss()
                return
            }

            var datas: [Data] = []
            let group = DispatchGroup()

            for result in results {
                let provider = result.itemProvider
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    group.enter()
                    provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                        if let data {
                            if let downsized = earlyDownscale(data: data) { datas.append(downsized) }
                            else { datas.append(data) }
                        }
                        group.leave()
                    }
                } else if provider.canLoadObject(ofClass: UIImage.self) {
                    group.enter()
                    provider.loadObject(ofClass: UIImage.self) { obj, _ in
                        defer { group.leave() }
                        guard let img = obj as? UIImage else { return }
                        // Encode via CoreGraphics (thread-safe) and reuse data-based downscale
                        if let cg = img.cgImage {
                            let out = CFDataCreateMutable(nil, 0)!
                            if let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) {
                                let opts: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.82]
                                CGImageDestinationAddImage(dest, cg, opts as CFDictionary)
                                if CGImageDestinationFinalize(dest) {
                                    let d = out as Data
                                    if let downsized = earlyDownscale(data: d) { datas.append(downsized) }
                                    else { datas.append(d) }
                                }
                            }
                        }
                    }
                }
            }

            group.notify(queue: .main) {
                self.parent.onPicked(datas)
                self.parent.dismiss()
            }
        }
    }
}


// Image bubble cohérente avec le chat, taille fixe (petit-moyen)
private struct ChatImageBubble: View {
    let image: UIImage
    let maxWidth: CGFloat
    let isUser: Bool

    @Environment(\.dynamicTypeSize) private var dType
    private var corner: CGFloat { scaleForDynamicType(dType, base: Theme.bubbleCorner) }
    private var bubbleSide: CGFloat { scaleForDynamicType(dType, base: 180) }   // taille carrée scalable

    var body: some View {
        return Image(uiImage: image)
            .resizable()
            .aspectRatio(1, contentMode: .fit)   // carré, fit
            .frame(width: bubbleSide, height: bubbleSide)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(Color(.separator).opacity(0.18), lineWidth: 1)
            )
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(6)
                    .background(.secondary.opacity(0.14), in: Circle())
                    .padding(6)
                    .opacity(0.9)
            }
    }
}

// Deck carré pour afficher jusqu'à 3 images empilées
private struct ChatImageDeckSquare: View {
    let images: [UIImage]          // jusqu’à 3
    let onTap: (UIImage) -> Void
    var singleTiltDegrees: Double = 0.0

    @Environment(\.dynamicTypeSize) private var dType
    private var side: CGFloat { scaleForDynamicType(dType, base: 140) }
    private var corner: CGFloat { scaleForDynamicType(dType, base: Theme.bubbleCorner) }

    var body: some View {
        // On ne montre que les 3 dernières
        let imgs = Array(images.suffix(3))
        ZStack {
            ForEach(Array(imgs.enumerated()), id: \.offset) { idx, img in
                let order = idx            // 0,1,2
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

// Deck carré avec swipe gauche/droite pour faire défiler l'image du dessus
private struct ChatImageDeckSwiper: View {
    let images: [UIImage]           // 1..N
    let onTapTop: (UIImage) -> Void
    var singleTiltDegrees: Double = 0.0

    @State private var topIndex: Int = 0      // index de l’image au-dessus
    @State private var dragX: CGFloat = 0

    @Environment(\.dynamicTypeSize) private var dType
    private var side: CGFloat { scaleForDynamicType(dType, base: 140) }
    private var corner: CGFloat { scaleForDynamicType(dType, base: Theme.bubbleCorner) }

    var body: some View {
        let count = images.count
        let ordered = (0..<count).map { (topIndex + $0) % count } // ordre d’affichage: top, suivante, ...

        ZStack {
            ForEach(Array(ordered.enumerated()), id: \.element) { pos, idx in
                // pos=0: carte du dessus, pos=1: suivante, etc.
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
                        // swipe gauche -> carte suivante
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        topIndex = (topIndex + 1) % images.count
                    } else if vx > threshold || dragX > threshold {
                        // swipe droite -> carte précédente
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        topIndex = (topIndex - 1 + images.count) % images.count
                    }
                    withAnimation(.smoothCompat) { dragX = 0 }
                }
        )
    }
}


// Async wrapper: decodes [Data] -> [UIImage] off-main, then shows deck
private struct AsyncChatImageDeckSwiper: View {
    let datas: [Data]
    let onTapTop: (UIImage) -> Void
    var singleTiltDegrees: Double = 0.0

    @State private var uiImages: [UIImage] = []

    var body: some View {
        Group {
            if uiImages.isEmpty {
                // Simple placeholder while decoding
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
                    .frame(width: 160, height: 160)
            } else {
                ChatImageDeckSwiper(images: uiImages, onTapTop: onTapTop, singleTiltDegrees: singleTiltDegrees)
            }
        }
        .task(id: datas) {
            let decoded: [UIImage] = await Task.detached(priority: .userInitiated) {
                let cache = ImageCache.shared
                // Decode at a reasonable display size to save memory
                return datas.compactMap { cache.decodeThumbnail(data: $0, maxPixelSize: 640) }
            }.value
            await MainActor.run {
                var tx = Transaction()
                tx.disablesAnimations = true
                withTransaction(tx) { self.uiImages = decoded }
            }
        }
    }
}


// Chip d’aperçu dans la barre d’input
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
                .aspectRatio(1, contentMode: .fit)   // carré, fit
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
                    .padding(6)                  // badge à l'intérieur de la vignette
                }
        }
        .contextMenu {
            Button(role: .destructive) { onRemove() } label: { Label("Retirer", systemImage: "trash") }
            Button { onTap() } label: { Label("Agrandir", systemImage: "arrow.up.left.and.arrow.down.right") }
        }
    }
}

// Async wrapper: decodes Data -> UIImage off-main and renders AttachmentCard
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



// MARK: - Utilities

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGPoint = .zero
    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) {}
}

struct CameraPicker: UIViewControllerRepresentable {
    typealias UIViewControllerType = UIImagePickerController
    var onImagePicked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
            }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
}

// MARK: - Lightbox View

// Feuille de partage système
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct Lightbox: View {
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
                // Drag vertical pour dismiss uniquement quand pas de zoom
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

        // Clamp helper based on geometry and current zoom
        func clampedPan(_ proposed: CGSize, in geo: GeometryProxy) -> CGSize {
            guard zoom > 1.01 else { return .zero }
            let padding: CGFloat = 32 // .padding() default ~16 each side
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
                    // Double tap pour zoomer/dézoomer rapidement
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

// MARK: - Preview

#Preview { ContentView() }

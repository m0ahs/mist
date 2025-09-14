import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import Photos
import ImageIO

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

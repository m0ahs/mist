import Foundation

/// État d'envoi par message pour afficher "sending/failed" et permettre Retry.
public enum SendStatus: Equatable { case sending, sent, failed(String?) }

/// Un message peut contenir du texte, une image, ou les deux.
/// → Un seul timestamp pour l’ensemble, donc plus le “double envoi”.
public struct Message: Identifiable, Equatable {
    public let id = UUID()
    public var text: String?
    public var imagesData: [Data]? // multiple images support
    public let isUser: Bool
    public let timestamp: Date
    public var status: SendStatus
    public var isSearchQuery: Bool

    public init(text: String? = nil,
                imagesData: [Data]? = nil,
                isUser: Bool,
                status: SendStatus = .sent,
                isSearchQuery: Bool = false) {
        self.text = text?.isEmpty == true ? nil : text
        self.imagesData = (imagesData?.isEmpty == true) ? nil : imagesData
        self.isUser = isUser
        self.timestamp = Date()
        self.status = status
        self.isSearchQuery = isSearchQuery
    }

    public static func == (lhs: Message, rhs: Message) -> Bool { lhs.id == rhs.id }
}

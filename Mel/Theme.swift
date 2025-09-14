import SwiftUI

struct Theme {
    // Colors
    static let pageBackground = Color(hex: "#F1F1F1")
    static let modalBackground = Color(hex: "#F0F0F0")
    static let inputBackground = Color.white
    static let separatorStroke = Color(.separator).opacity(0.18)
    static let avatarBorder = Color(.separator).opacity(0.25)

    // Metrics
    static let bubbleCorner: CGFloat = 18
    static let inputCorner: CGFloat = 22

    // Shadows
    static func deckShadowColor(_ opacity: Double = 0.11) -> Color { .black.opacity(opacity) }
}


//
//  ORTypes.swift
//  Mist
//
//  Created by Joseph Mbai Bisso on 14.09.2025.
//

import Foundation

struct ORContent: Codable, Equatable {
    let type: String              // "text" | "image_url"
    let text: String?
    let image_url: String?

    init(type: String, text: String? = nil, image_url: String? = nil) {
        self.type = type
        self.text = text
        self.image_url = image_url
    }
}

struct ORMessage: Codable, Equatable {
    let role: String              // "system" | "user" | "assistant"
    var content: [ORContent]
}

struct ORRequest: Codable {
    let model: String
    let messages: [ORMessage]
    let temperature: Double?
    let max_tokens: Int?
}

struct ORChoice: Codable {
    struct ORMessageContent: Codable {
        let role: String
        let content: String
    }
    let index: Int?
    let message: ORMessageContent
    let finish_reason: String?
}

struct ORError: Codable {
    let message: String
}

struct ORResponse: Codable {
    let id: String?
    let choices: [ORChoice]?
    let error: ORError?
}

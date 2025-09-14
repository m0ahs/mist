//
//  OpenRouterService.swift
//  Mel
//

import Foundation   // <- indispensable pour URL, Data, JSONEncoder, etc.

final class OpenRouterService {
    private let apiKey: String
    private let model: String
    private let referer: String
    private let appTitle: String
    
    var isConfigured: Bool { !apiKey.isEmpty }
    
    init(apiKey: String,
         model: String = "openrouter/auto",
         referer: String = "https://alynengineering.com",
         appTitle: String = "Mist") {
        // Sanitize key: trim espaces et guillemets éventuels
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        self.model = model
        self.referer = referer
        self.appTitle = appTitle
    }
    
    func generate(systemPrompt: String,
                  userPrompt: String,
                  userImagesData: [Data] = [],
                  history: [ORMessage] = [],
                  maxTokens: Int = 256,
                  temperature: Double = 0.7) async throws -> String {
        let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        
        // Construire les messages
        var messages: [ORMessage] = []
        messages.append(
            ORMessage(
                role: "system",
                content: [ORContent(type: "text", text: systemPrompt, image_url: nil)]
            )
        )
        messages.append(contentsOf: history)
        
        // Tour courant
        var userContent: [ORContent] = [
            ORContent(type: "text",
                      text: userPrompt.isEmpty ? "Please respond to the image." : userPrompt,
                      image_url: nil)
        ]
        for data in userImagesData {
            let base64 = data.base64EncodedString()
            let dataURL = "data:image/jpeg;base64,\(base64)"
            userContent.append(ORContent(type: "image_url", text: nil, image_url: dataURL))
        }
        messages.append(ORMessage(role: "user", content: userContent))
        
        let body = ORRequest(model: model,
                             messages: messages,
                             temperature: temperature,
                             max_tokens: maxTokens)
        
        // Préparer requête
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30 // graceful timeout
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue(referer, forHTTPHeaderField: "HTTP-Referer")
        request.addValue(appTitle, forHTTPHeaderField: "X-Title")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        // Envoyer
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            if let decoded = try? JSONDecoder().decode(ORResponse.self, from: data),
               let err = decoded.error?.message {
                throw NSError(domain: "OpenRouterService",
                              code: status,
                              userInfo: [NSLocalizedDescriptionKey: err])
            }
            let msg = HTTPURLResponse.localizedString(forStatusCode: status)
            throw NSError(domain: "OpenRouterService",
                          code: status,
                          userInfo: [NSLocalizedDescriptionKey: msg.capitalized])
        }
        
        // Parser réponse
        let decoded = try JSONDecoder().decode(ORResponse.self, from: data)
        if let err = decoded.error?.message {
            throw NSError(domain: "OpenRouterService",
                          code: -3,
                          userInfo: [NSLocalizedDescriptionKey: err])
        }
        guard let text = decoded.choices?.first?.message.content,
              !text.isEmpty else {
            throw NSError(domain: "OpenRouterService",
                          code: -4,
                          userInfo: [NSLocalizedDescriptionKey: "Empty completion."])
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

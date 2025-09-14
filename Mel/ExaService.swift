//
//  ExaService.swift
//  Mel
//

import Foundation

struct ExaResult: Codable {
    let title: String
    let url: String
    let snippet: String?
}

// /answer response model
struct ExaAnswer: Codable {
    let answer: String
    let citations: [ExaResult]
}

final class ExaService {
    private let apiKey: String
    var isConfigured: Bool { !apiKey.isEmpty }

    init() {
        let fromPlist = Bundle.main.object(forInfoDictionaryKey: "EXA_API_KEY") as? String ?? "6cdedc68-4449-473a-8625-8373830e1daf"
        let fromEnv = ProcessInfo.processInfo.environment["EXA_API_KEY"] ?? "6cdedc68-4449-473a-8625-8373830e1daf"
        let key = fromPlist.isEmpty ? fromEnv : fromPlist
        apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func search(_ query: String, limit: Int = 5) async throws -> [ExaResult] {
        guard isConfigured else {
            throw NSError(domain: "ExaService", code: -100, userInfo: [NSLocalizedDescriptionKey: "EXA_API_KEY missing."])
        }

        let url = URL(string: "https://api.exa.ai/search")!

        struct Req: Codable { let query: String; let numResults: Int }
        struct Resp: Codable {
            struct Item: Codable { let title: String?; let url: String?; let text: String? }
            let results: [Item]?
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.httpBody = try JSONEncoder().encode(Req(query: query, numResults: max(1, limit)))

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "ExaService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No HTTP response"]) }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "ExaService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: body])
        }
        let decoded = try JSONDecoder().decode(Resp.self, from: data)
        let items = decoded.results ?? []
        return items.compactMap { item in
            guard let t = item.title, let u = item.url else { return nil }
            return ExaResult(title: t, url: u, snippet: item.text)
        }
    }

    /// Calls Exa /answer to get a drafted answer plus citations.
    /// Requests fast, web-grounded answers and decodes flexibly.
    func answer(_ query: String, limit: Int = 5) async throws -> ExaAnswer {
        guard isConfigured else {
            throw NSError(domain: "ExaService", code: -100,
                          userInfo: [NSLocalizedDescriptionKey: "EXA_API_KEY missing."])
        }

        let url = URL(string: "https://api.exa.ai/answer")!

        struct Req: Codable {
            let query: String
            let numResults: Int
            // Do not fetch full text to keep response concise
            let text: Bool?
            let stream: Bool?
        }
        struct Resp: Codable {
            // Different deployments may use alternative keys for the answer text
            let answer: String?
            let response: String?
            let final_answer: String?
            let output: String?
            struct Cit: Codable {
                let title: String?
                let url: String?
                let text: String?
                let snippet: String?
                let highlight: String?
            }
            // Citations may appear under various keys
            let citations: [Cit]?
            let sources: [Cit]?
            let results: [Cit]?
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.httpBody = try JSONEncoder().encode(
            Req(
                query: query,
                numResults: max(1, limit),
                text: false,
                stream: nil
            )
        )

        let (data, res) = try await URLSession.shared.data(for: req)
        guard let http = res as? HTTPURLResponse else {
            throw NSError(domain: "ExaService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No HTTP response"])
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "ExaService", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: body])
        }

        let decoded = try JSONDecoder().decode(Resp.self, from: data)
        let answerText =
            decoded.answer ??
            decoded.response ??
            decoded.final_answer ??
            decoded.output ??
            ""
        let rawCitations = decoded.citations ?? decoded.sources ?? decoded.results ?? []
        let cites: [ExaResult] = rawCitations.compactMap { c in
            guard let t = c.title, let u = c.url else { return nil }
            let snippet = c.text ?? c.snippet ?? c.highlight
            return ExaResult(title: t, url: u, snippet: snippet)
        }
        return ExaAnswer(answer: answerText, citations: cites)
    }
}

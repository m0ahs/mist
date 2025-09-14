import Foundation
import CoreML

final class LocalLLMService {
    private var model: MLModel?

    var isAvailable: Bool { model != nil }

    init() {
        loadModel()
    }

    private func loadModel() {
        guard let url = Bundle.main.url(forResource: "MistLM", withExtension: "mlmodelc") else { return }
        model = try? MLModel(contentsOf: url)
    }

    func generate(prompt: String, maxTokens: Int = 128) async throws -> String {
        throw NSError(domain: "LocalLLMService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Local model not present or generation pipeline not implemented."])
    }
}
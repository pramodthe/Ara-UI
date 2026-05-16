//
//  ImageGenerationService.swift
//  araui
//
//  Service to generate images through the local AraUI backend.
//

import Foundation
import AppKit

final class ImageGenerationService {
    static let shared = ImageGenerationService()
    
    private init() {}
    
    func generateImage(fromImagePath imagePath: String, prompt: String) async throws -> Data {
        let imageData = try Data(contentsOf: URL(fileURLWithPath: imagePath))
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPrompt.isEmpty == false else {
            throw GenerationError.missingPrompt
        }

        let mimeType = Self.mimeType(for: imagePath)
        return try await BackendClient().generateImage(
            fromImageData: imageData,
            mimeType: mimeType,
            prompt: trimmedPrompt
        )
    }

    private static func mimeType(for imagePath: String) -> String {
        switch URL(fileURLWithPath: imagePath).pathExtension.lowercased() {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "webp":
            return "image/webp"
        default:
            return "image/png"
        }
    }
    
    enum GenerationError: LocalizedError {
        case missingPrompt
        
        var errorDescription: String? {
            switch self {
            case .missingPrompt:
                return "Enter a prompt for Qwen Image."
            }
        }
    }
}

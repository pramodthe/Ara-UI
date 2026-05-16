//
//  ImageGenerationService.swift
//  nova
//
//  Service to generate images using Gemini API
//

import Foundation
import AppKit

final class ImageGenerationService {
    static let shared = ImageGenerationService()
    
    private init() {}
    
    func generateImage(fromImagePath imagePath: String, prompt: String) async throws -> Data {
        guard let apiKey = try KeychainService.shared.readApiKey(),
              apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw GenerationError.missingApiKey
        }
        
        // Read and encode the image
        let imageData = try Data(contentsOf: URL(fileURLWithPath: imagePath))
        let base64Image = imageData.base64EncodedString()
        
        // Prepare the API request
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image:generateContent")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": prompt],
                    [
                        "inline_data": [
                            "mime_type": "image/png",
                            "data": base64Image
                        ]
                    ]
                ]
            ]]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        // Make the request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GenerationError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            if let responseString = String(data: data, encoding: .utf8) {
                print("HTTP Error \(httpResponse.statusCode): \(responseString)")
            }
            throw GenerationError.httpError(statusCode: httpResponse.statusCode)
        }
        
        // Parse the response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("Failed to parse JSON from response")
            throw GenerationError.invalidResponseFormat
        }
        
        print("Response JSON: \(json)")
        
        guard let candidates = json["candidates"] as? [[String: Any]] else {
            print("No 'candidates' array found in response")
            throw GenerationError.invalidResponseFormat
        }
        
        guard let firstCandidate = candidates.first else {
            print("Candidates array is empty")
            throw GenerationError.invalidResponseFormat
        }
        
        guard let content = firstCandidate["content"] as? [String: Any] else {
            print("No 'content' in first candidate")
            throw GenerationError.invalidResponseFormat
        }
        
        guard let parts = content["parts"] as? [[String: Any]] else {
            print("No 'parts' array in content")
            throw GenerationError.invalidResponseFormat
        }
        
        guard let firstPart = parts.first else {
            print("Parts array is empty")
            throw GenerationError.invalidResponseFormat
        }
        
        guard let inlineData = firstPart["inlineData"] as? [String: Any] else {
            print("No 'inlineData' in first part")
            throw GenerationError.invalidResponseFormat
        }
        
        guard let base64Data = inlineData["data"] as? String else {
            print("No 'data' field in inline_data")
            throw GenerationError.invalidResponseFormat
        }
        
        // Decode the base64 image
        guard let imageData = Data(base64Encoded: base64Data) else {
            print("Failed to decode base64 data")
            throw GenerationError.base64DecodingFailed
        }
        
        print("Successfully generated image: \(imageData.count) bytes")
        return imageData
    }
    
    enum GenerationError: LocalizedError {
        case invalidResponse
        case missingApiKey
        case httpError(statusCode: Int)
        case invalidResponseFormat
        case base64DecodingFailed
        
        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Invalid response from server"
            case .missingApiKey:
                return "Missing Gemini API key"
            case .httpError(let code):
                return "HTTP error: \(code)"
            case .invalidResponseFormat:
                return "Invalid response format"
            case .base64DecodingFailed:
                return "Failed to decode image data"
            }
        }
    }
}

//
//  BackendClient.swift
//  araui
//
//  Non-streaming client for the custom AraUI backend.
//

import Foundation

/// Simple DTO for backend responses.
private struct BackendResponse: Decodable {
    struct Content: Decodable {
        struct Part: Decodable { let text: String? }
        let role: String
        let parts: [Part]
    }
    let content: Content

    var text: String { content.parts.compactMap { $0.text }.joined() }
}

private struct BackendErrorResponse: Decodable {
    let error: String?
    let detail: String?

    var message: String? {
        error ?? detail
    }
}

final class BackendClient {
    private static let baseURL = URL(string: "http://localhost:8000")!
    private static let appName = "multi_tool_agent"
    private static let userId = "u"
    private static var sessionId: String = UUID().uuidString
    private static let sessionQueue = DispatchQueue(label: "araui.backendclient.session")
    private static var sessionTask: Task<Void, Error>?

    private let decoder = JSONDecoder()

    init() {
        Task {
            try await BackendClient.ensureSession()
        }
    }

    static func ensureSession() async throws {
        let task: Task<Void, Error> = sessionQueue.sync {
            if let existing = sessionTask, existing.isCancelled == false {
                return existing
            }

            sessionId = UUID().uuidString
            let newTask = Task {
                try await createSession(
                    baseURL: baseURL,
                    appName: appName,
                    userId: userId,
                    sessionId: sessionId
                )
            }
            sessionTask = newTask
            return newTask
        }

        try await task.value
    }

    private static func createSession(baseURL: URL, appName: String, userId: String, sessionId: String) async throws {
        struct SessionPayload: Encodable {
            let state: [String: String]
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("apps/\(appName)/users/\(userId)/sessions/\(sessionId)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = SessionPayload(state: [:])
        request.httpBody = try JSONEncoder().encode(payload)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200..<300, 409:
            return
        default:
            let message = Self.backendErrorMessage(from: data) ?? "Failed to create session (status: \(http.statusCode))"
            throw NSError(domain: "BackendClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    func sendMessage(text: String, inlineImageData: Data?, mimeType: String?, hiddenContext: String?) async throws -> String {
        try await BackendClient.ensureSession()

        struct InlineData: Encodable {
            let mimeType: String
            let data: String
        }
        struct Part: Encodable {
            var text: String?
            var inlineData: InlineData?
        }
        struct NewMessage: Encodable {
            let role: String
            let parts: [Part]
        }
        struct Payload: Encodable {
            let appName: String
            let userId: String
            let sessionId: String
            let newMessage: NewMessage
            let streaming: Bool
        }

        var parts: [Part] = []
        parts.append(Part(text: text, inlineData: nil))
        if let ctxRaw = hiddenContext?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), ctxRaw.isEmpty == false {
            parts.append(Part(text: "<context>" + ctxRaw + "</context>", inlineData: nil))
        }
        if let data = inlineImageData, let type = mimeType {
            parts.append(Part(text: nil, inlineData: InlineData(mimeType: type, data: data.base64EncodedString())))
        }

        let payload = Payload(
            appName: BackendClient.appName,
            userId: BackendClient.userId,
            sessionId: BackendClient.sessionId,
            newMessage: NewMessage(role: "user", parts: parts),
            streaming: false
        )

        var request = URLRequest(url: BackendClient.baseURL.appendingPathComponent("run_sse"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let message = BackendClient.backendErrorMessage(from: data) ?? "Server error (status: \(statusCode))"
            throw NSError(domain: "BackendClient", code: statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }

        let rawString = String(data: data, encoding: .utf8) ?? ""
        let payloads = extractPayloads(from: rawString)
        var textFragments: [String] = []
        var decodeError: Error?

        for payload in payloads {
            guard let payloadData = payload.data(using: .utf8) else { continue }
            if let backendError = try? decoder.decode(BackendErrorResponse.self, from: payloadData),
               let message = backendError.message,
               message.isEmpty == false {
                throw NSError(domain: "BackendClient", code: -3, userInfo: [NSLocalizedDescriptionKey: message])
            }

            do {
                let response = try decoder.decode(BackendResponse.self, from: payloadData)
                let text = response.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                if text.isEmpty == false {
                    textFragments.append(text)
                }
            } catch {
                decodeError = error
            }
        }

        if let finalText = textFragments.last ?? textFragments.first {
            return finalText
        }

        if let error = decodeError {
            throw error
        }

        throw NSError(domain: "BackendClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid response encoding"])
    }

    func generateImage(fromImageData imageData: Data, mimeType: String, prompt: String) async throws -> Data {
        struct Payload: Encodable {
            let prompt: String
            let imageData: String
            let mimeType: String

            enum CodingKeys: String, CodingKey {
                case prompt
                case imageData = "image_data"
                case mimeType = "mime_type"
            }
        }

        let payload = Payload(
            prompt: prompt,
            imageData: imageData.base64EncodedString(),
            mimeType: mimeType
        )

        return try await postBinary(
            path: "araui/image-generation",
            body: payload,
            timeout: 180,
            fallbackError: "Image generation failed"
        )
    }

    func synthesizeSpeech(text: String, voice: String = "Cherry") async throws -> Data {
        struct Payload: Encodable {
            let text: String
            let voice: String
            let languageType: String

            enum CodingKeys: String, CodingKey {
                case text
                case voice
                case languageType = "language_type"
            }
        }

        let payload = Payload(text: text, voice: voice, languageType: "English")
        return try await postBinary(
            path: "araui/tts",
            body: payload,
            timeout: 120,
            fallbackError: "Text-to-speech failed"
        )
    }
}

private extension BackendClient {
    func postBinary<T: Encodable>(path: String, body: T, timeout: TimeInterval, fallbackError: String) async throws -> Data {
        var request = URLRequest(url: BackendClient.baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let message = BackendClient.backendErrorMessage(from: data) ?? "\(fallbackError) (status: \(statusCode))"
            throw NSError(domain: "BackendClient", code: statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }

        return data
    }

    static func backendErrorMessage(from data: Data) -> String? {
        if let decoded = try? JSONDecoder().decode(BackendErrorResponse.self, from: data),
           let message = decoded.message,
           message.isEmpty == false {
            return message
        }

        let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return raw?.isEmpty == false ? raw : nil
    }

    func extractPayloads(from raw: String) -> [String] {
        var payloads: [String] = []
        var buffer = ""

        let lines = raw.split(maxSplits: Int.max, omittingEmptySubsequences: false, whereSeparator: \.isNewline)

        for lineSubstring in lines {
            let line = String(lineSubstring)
            let trimmedLine = line.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

            if trimmedLine.isEmpty {
                if buffer.isEmpty == false {
                    payloads.append(buffer)
                    buffer.removeAll(keepingCapacity: true)
                }
                continue
            }

            if trimmedLine.hasPrefix("data:") {
                let dataStart = trimmedLine.index(trimmedLine.startIndex, offsetBy: 5)
                let dataPayload = trimmedLine[dataStart...].trimmingCharacters(in: CharacterSet.whitespaces)
                guard dataPayload != "[DONE]" else { continue }

                if buffer.isEmpty == false {
                    buffer.append("\n")
                }
                buffer.append(dataPayload)
            } else if trimmedLine.hasPrefix("event:") || trimmedLine.hasPrefix("id:") || trimmedLine == "[DONE]" {
                continue
            } else {
                if buffer.isEmpty == false {
                    buffer.append("\n")
                }
                buffer.append(trimmedLine)
            }
        }

        if buffer.isEmpty == false {
            payloads.append(buffer)
        }

        return payloads
    }
}

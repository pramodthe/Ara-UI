//
//  BackendClient.swift
//  nova
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

final class BackendClient {
    private static let baseURL = URL(string: "http://localhost:8000")!
    private static let appName = "multi_tool_agent"
    private static let userId = "u"
    private static var sessionId: String = UUID().uuidString
    private static let sessionQueue = DispatchQueue(label: "nova.backendclient.session")
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
            struct State: Encodable {
                let key1: String
                let key2: Int
            }
            let state: State
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("apps/\(appName)/users/\(userId)/sessions/\(sessionId)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = SessionPayload(state: .init(key1: "value1", key2: 42))
        request.httpBody = try JSONEncoder().encode(payload)
        request.timeoutInterval = 60

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200..<300, 409:
            return
        default:
            throw NSError(domain: "BackendClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed to create session (status: \(http.statusCode))"])
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

        if let body = request.httpBody,
           var json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            if var newMessage = json["newMessage"] as? [String: Any],
               var parts = newMessage["parts"] as? [[String: Any]] {
                for idx in parts.indices {
                    if var inlineData = parts[idx]["inlineData"] as? [String: Any], inlineData["data"] != nil {
                        inlineData["data"] = "value..."
                        parts[idx]["inlineData"] = inlineData
                    }
                }
                newMessage["parts"] = parts
                json["newMessage"] = newMessage
            }

            if let sanitizedData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]),
               let bodyString = String(data: sanitizedData, encoding: .utf8) {
                print("Sending request to \(request.url?.absoluteString ?? "<unknown>"):\n\(bodyString)")
            }
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "BackendClient", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: "Server error"])
        }

        let rawString = String(data: data, encoding: .utf8) ?? ""
        print("Received response (status: \(http.statusCode)):\n\(rawString)")

        let payloads = extractPayloads(from: rawString)
        var textFragments: [String] = []
        var decodeError: Error?

        for payload in payloads {
            guard let payloadData = payload.data(using: .utf8) else { continue }
            do {
                let response = try decoder.decode(BackendResponse.self, from: payloadData)
                let text = response.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                if text.isEmpty == false {
                    textFragments.append(text)
                }
            } catch {
                decodeError = error
                print("Failed to decode backend payload: \(payload)\nError: \(error)")
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
}

private extension BackendClient {
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


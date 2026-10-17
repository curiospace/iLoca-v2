import Foundation

// MARK: - ClaudeClient
// Minimal Anthropic Messages API client over URLSession (Swift has no official SDK).
// Streams Server-Sent Events so answers appear as they're written.

enum ClaudeError: LocalizedError {
    case missingAPIKey
    case http(Int, String)
    case refused(String?)
    case api(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No Claude API key set. Set ANTHROPIC_API_KEY in the Xcode scheme."
        case .http(let code, let message):
            switch code {
            case 401: return "Claude rejected the API key (401). Check ANTHROPIC_API_KEY in the Xcode scheme."
            case 429: return "Claude is rate-limiting requests right now (429). Try again in a moment."
            case 529: return "Claude is temporarily overloaded (529). Try again shortly."
            default: return "Claude API error \(code): \(message)"
            }
        case .refused(let category):
            return "Claude declined to answer this\(category.map { " (\($0))" } ?? ""). Try rephrasing the question."
        case .api(let message):
            return "Claude API error: \(message)"
        }
    }
}

struct ClaudeClient {
    static let defaultModel = "claude-sonnet-5-5"

    /// Model ID from the ANTHROPIC_MODEL environment variable (set in the Xcode
    /// scheme), or Claude Sonnet 5.5 when it's unset.
    static var model: String {
        let value = ProcessInfo.processInfo.environment["ANTHROPIC_MODEL"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value! : defaultModel
    }
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    struct Message: Encodable {
        let role: String   // "user" | "assistant"
        let content: String
    }

    let apiKey: String

    var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 600
        return URLSession(configuration: config)
    }()

    /// Streams the text of Claude's reply.
    /// - Parameters:
    ///   - system: grounding instructions + data. Sent as a cached block, since it
    ///     stays identical for every turn of a conversation.
    ///   - effort: "low" suits chat Q&A; "medium" for longer written output.
    /// - Parameter onModel: called with the model that actually served the reply
    ///   (differs from `model` if a refusal fallback kicked in).
    func stream(system: String, messages: [Message], effort: String = "low", maxTokens: Int = 16_000,
                onModel: (@Sendable (String) -> Void)? = nil) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: Self.endpoint)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "content-type")
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    // Server-side fallback: if a safety classifier declines, the API retries
                    // on Anthropic's recommended model for that category within the same call.
                    request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
                    request.httpBody = try JSONSerialization.data(withJSONObject: [
                        "model": Self.model,
                        "max_tokens": maxTokens,
                        "stream": true,
                        "fallbacks": "default",
                        "output_config": ["effort": effort],
                        "system": [[
                            "type": "text",
                            "text": system,
                            "cache_control": ["type": "ephemeral"]
                        ]],
                        "messages": messages.map { ["role": $0.role, "content": $0.content] }
                    ] as [String: Any])

                    let (bytes, response) = try await session.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 200 else {
                        var body = ""
                        for try await line in bytes.lines { body += line }
                        throw ClaudeError.http(status, Self.errorMessage(from: body) ?? body)
                    }

                    var parser = ClaudeStreamParser()
                    for try await line in bytes.lines {
                        let previousModel = parser.servedModel
                        if let text = try parser.consume(line) { continuation.yield(text) }
                        if let served = parser.servedModel, served != previousModel { onModel?(served) }
                    }
                    try parser.finish()
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func errorMessage(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (json["error"] as? [String: Any])?["message"] as? String
    }
}

/// Parses the Messages API SSE stream line by line. Separate from the networking
/// so it can be unit-tested against recorded events.
struct ClaudeStreamParser {
    private(set) var stopReason: String?
    /// Model named in message_start (the fallback model, if one served the reply).
    private(set) var servedModel: String?
    private(set) var refusalCategory: String?

    /// Returns visible text to append, if this line carried any.
    mutating func consume(_ line: String) throws -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard let data = payload.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String else { return nil }

        switch type {
        case "content_block_delta":
            // Only text deltas are shown; thinking and other block types are skipped.
            guard let delta = event["delta"] as? [String: Any],
                  delta["type"] as? String == "text_delta" else { return nil }
            return delta["text"] as? String
        case "message_start":
            servedModel = (event["message"] as? [String: Any])?["model"] as? String ?? servedModel
            return nil
        case "message_delta":
            if let delta = event["delta"] as? [String: Any] {
                stopReason = delta["stop_reason"] as? String ?? stopReason
                if let details = delta["stop_details"] as? [String: Any] {
                    refusalCategory = details["category"] as? String
                }
            }
            return nil
        case "error":
            let message = (event["error"] as? [String: Any])?["message"] as? String ?? "Unknown error"
            throw ClaudeError.api(message)
        default:
            return nil
        }
    }

    /// Call at end of stream. A refusal arrives as HTTP 200, so check stop_reason.
    func finish() throws {
        if stopReason == "refusal" { throw ClaudeError.refused(refusalCategory) }
    }
}

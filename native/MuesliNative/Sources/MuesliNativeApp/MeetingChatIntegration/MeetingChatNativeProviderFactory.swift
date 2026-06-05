import Foundation
import MuesliMeetingChat

enum MeetingChatNativeProviderFactory {
    static func router(config: AppConfig, isChatGPTAuthenticated: Bool) -> MeetingChatProviderRouter {
        MeetingChatProviderRouter(providers: providers(config: config, isChatGPTAuthenticated: isChatGPTAuthenticated))
    }

    static func providers(config: AppConfig, isChatGPTAuthenticated: Bool) -> [any MeetingChatProvider] {
        var providers: [any MeetingChatProvider] = [
            ChatGPTMeetingChatProvider(
                isAuthenticated: isChatGPTAuthenticated,
                model: config.chatGPTModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "gpt-5.4-mini"
                    : config.chatGPTModel.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        ]

        let backend = config.meetingSummaryBackend.lowercased()
        if backend == MeetingSummaryBackendOption.openAI.backend || !config.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            providers.append(
                OpenAIResponsesMeetingChatProvider(
                    apiKey: config.openAIAPIKey,
                    model: config.openAIModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "gpt-5.4-mini"
                        : config.openAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
        }
        if backend == MeetingSummaryBackendOption.openRouter.backend || !config.openRouterAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            providers.append(
                ChatCompletionsMeetingChatProvider(
                    name: "OpenRouter",
                    url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!,
                    apiKey: config.openRouterAPIKey,
                    model: config.openRouterModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "stepfun/step-3.5-flash:free"
                        : config.openRouterModel.trimmingCharacters(in: .whitespacesAndNewlines),
                    extraHeaders: ["X-OpenRouter-Title": AppIdentity.displayName],
                    requiresAPIKey: true
                )
            )
        }
        if backend == MeetingSummaryBackendOption.ollama.backend {
            providers.append(
                OllamaMeetingChatProvider(
                    baseURL: URL(string: config.ollamaURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "http://localhost:11434" : config.ollamaURL)!,
                    model: config.ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "qwen3.5"
                        : config.ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
        }
        if backend == MeetingSummaryBackendOption.lmStudio.backend,
           !config.lmStudioModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let url = OpenAICompatibleURLResolver.chatCompletionsURL(from: config.lmStudioURL, defaultBase: "http://localhost:1234") {
            providers.append(
                ChatCompletionsMeetingChatProvider(
                    name: "LM Studio",
                    url: url,
                    apiKey: "",
                    model: config.lmStudioModel,
                    requiresAPIKey: false
                )
            )
        }
        if backend == MeetingSummaryBackendOption.customLLM.backend,
           config.customLLMFormat == CustomLLMFormat.openAI.rawValue,
           !config.customLLMModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let url = OpenAICompatibleURLResolver.chatCompletionsURL(from: config.customLLMURL, defaultBase: nil) {
            providers.append(
                ChatCompletionsMeetingChatProvider(
                    name: "Custom LLM",
                    url: url,
                    apiKey: config.customLLMAPIKey,
                    model: config.customLLMModel,
                    requiresAPIKey: false
                )
            )
        }
        return providers
    }
}

private enum MeetingChatPromptFactory {
    static let instructions = """
    You are Muesli's read-only meeting assistant. Answer using only the meeting context provided by the app. Do not invent facts. If the context is insufficient, say what is missing. Keep answers concise and useful. You may mention source meeting titles, but you cannot modify notes, create tasks, move meetings, or take actions.
    """

    static func userPrompt(for request: MeetingChatRequest) -> String {
        var parts = ["Context:\n\(request.context.prompt)"]
        if let memorySummary = request.memorySummary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !memorySummary.isEmpty {
            parts.append("Earlier chat memory:\n\(memorySummary)")
        }
        let prior = request.priorMessages.suffix(6)
        if !prior.isEmpty {
            let transcript = prior.map { "\($0.role.rawValue): \($0.text)" }.joined(separator: "\n")
            parts.append("Recent chat:\n\(transcript)")
        }
        parts.append("Question:\n\(request.question)")
        return parts.joined(separator: "\n\n---\n\n")
    }
}

private final class ChatGPTMeetingChatProvider: MeetingChatProvider, @unchecked Sendable {
    let name = "ChatGPT"
    let availability: MeetingChatProviderAvailability

    private let model: String
    private let url = URL(string: "https://chatgpt.com/backend-api/wham/responses")!

    init(isAuthenticated: Bool, model: String) {
        self.availability = isAuthenticated ? .available : .unavailable("Not signed in to ChatGPT")
        self.model = model
    }

    func send(_ request: MeetingChatRequest) async throws -> MeetingChatProviderResponse {
        let (token, accountId) = try await ChatGPTAuthManager.shared.validAccessToken()
        let body: [String: Any] = [
            "model": model,
            "store": false,
            "stream": true,
            "instructions": MeetingChatPromptFactory.instructions,
            "input": [
                [
                    "role": "user",
                    "content": [
                        ["type": "input_text", "text": MeetingChatPromptFactory.userPrompt(for: request)]
                    ]
                ] as [String: Any]
            ]
        ]

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if !accountId.isEmpty {
            urlRequest.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            var errorData = Data()
            for try await byte in bytes { errorData.append(byte) }
            throw MeetingChatError.providerFailed(Self.errorMessage(from: errorData, fallback: "ChatGPT chat failed with HTTP \(status)."))
        }

        var text = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let outputText = json["output_text"] as? String, !outputText.isEmpty {
                text = outputText
            }
            if let type = json["type"] as? String,
               type == "response.output_text.delta",
               let delta = json["delta"] as? String {
                text += delta
            }
        }
        return MeetingChatProviderResponse(text: text)
    }

    private static func errorMessage(from data: Data, fallback: String) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
                return message
            }
            if let message = json["message"] as? String {
                return message
            }
        }
        return String(data: data, encoding: .utf8) ?? fallback
    }
}

private final class OpenAIResponsesMeetingChatProvider: MeetingChatProvider, @unchecked Sendable {
    let name = "OpenAI"
    let availability: MeetingChatProviderAvailability

    private let apiKey: String
    private let model: String
    private let url = URL(string: "https://api.openai.com/v1/responses")!

    init(apiKey: String, model: String) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = model
        self.availability = self.apiKey.isEmpty ? .unavailable("No OpenAI API key") : .available
    }

    func send(_ request: MeetingChatRequest) async throws -> MeetingChatProviderResponse {
        let body: [String: Any] = [
            "model": model,
            "store": false,
            "input": [
                ["role": "system", "content": MeetingChatPromptFactory.instructions],
                ["role": "user", "content": MeetingChatPromptFactory.userPrompt(for: request)]
            ],
            "reasoning": ["effort": "low"],
            "text": ["verbosity": "low"],
            "max_output_tokens": 1600
        ]

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        try validateHTTPResponse(response, data: data, backend: name)
        let text = try Self.extractResponsesText(from: data, backend: name)
        return MeetingChatProviderResponse(text: text)
    }

    private static func extractResponsesText(from data: Data, backend: String) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MeetingChatError.emptyResponse(backend)
        }
        if let outputText = json["output_text"] as? String, !outputText.isEmpty {
            return outputText
        }
        let output = json["output"] as? [[String: Any]] ?? []
        for item in output {
            let content = item["content"] as? [[String: Any]] ?? []
            for entry in content {
                if let text = entry["text"] as? String, !text.isEmpty {
                    return text
                }
            }
        }
        throw MeetingChatError.emptyResponse(backend)
    }
}

private final class ChatCompletionsMeetingChatProvider: MeetingChatProvider, @unchecked Sendable {
    let name: String
    let availability: MeetingChatProviderAvailability

    private let url: URL
    private let apiKey: String
    private let model: String
    private let extraHeaders: [String: String]

    init(
        name: String,
        url: URL,
        apiKey: String,
        model: String,
        extraHeaders: [String: String] = [:],
        requiresAPIKey: Bool
    ) {
        self.name = name
        self.url = url
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.extraHeaders = extraHeaders
        if self.model.isEmpty {
            self.availability = .unavailable("No \(name) model selected")
        } else if requiresAPIKey && self.apiKey.isEmpty {
            self.availability = .unavailable("No \(name) API key")
        } else {
            self.availability = .available
        }
    }

    func send(_ request: MeetingChatRequest) async throws -> MeetingChatProviderResponse {
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": MeetingChatPromptFactory.instructions],
                ["role": "user", "content": MeetingChatPromptFactory.userPrompt(for: request)]
            ],
            "max_tokens": 1600
        ]

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        for (key, value) in extraHeaders {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        try validateHTTPResponse(response, data: data, backend: name)
        return MeetingChatProviderResponse(text: try Self.extractChatText(from: data, backend: name))
    }

    static func extractChatText(from data: Data, backend: String) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String,
              !text.isEmpty else {
            throw MeetingChatError.emptyResponse(backend)
        }
        return text
    }
}

private final class OllamaMeetingChatProvider: MeetingChatProvider, @unchecked Sendable {
    let name = "Ollama"
    let availability: MeetingChatProviderAvailability = .available

    private let baseURL: URL
    private let model: String

    init(baseURL: URL, model: String) {
        self.baseURL = baseURL
        self.model = model
    }

    func send(_ request: MeetingChatRequest) async throws -> MeetingChatProviderResponse {
        let url = baseURL.appendingPathComponent("api/chat")
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": MeetingChatPromptFactory.instructions],
                ["role": "user", "content": MeetingChatPromptFactory.userPrompt(for: request)]
            ],
            "stream": false,
            "options": ["num_predict": 1600]
        ]

        var urlRequest = URLRequest(url: url)
        urlRequest.timeoutInterval = 300
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        try validateHTTPResponse(response, data: data, backend: name)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let text = message["content"] as? String,
              !text.isEmpty else {
            throw MeetingChatError.emptyResponse(name)
        }
        return MeetingChatProviderResponse(text: text)
    }
}

private enum OpenAICompatibleURLResolver {
    static func chatCompletionsURL(from raw: String, defaultBase: String?) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? defaultBase : trimmed
        guard let base, let url = URL(string: base) else { return nil }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.hasSuffix("chat/completions") {
            return url
        }
        return url.appendingPathComponent("v1/chat/completions")
    }
}

private func validateHTTPResponse(_ response: URLResponse, data: Data, backend: String) throws {
    guard let http = response as? HTTPURLResponse else { return }
    guard (200..<300).contains(http.statusCode) else {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
                throw MeetingChatError.providerFailed("\(backend): \(message)")
            }
            if let message = json["message"] as? String {
                throw MeetingChatError.providerFailed("\(backend): \(message)")
            }
        }
        let body = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
        throw MeetingChatError.providerFailed("\(backend): \(body)")
    }
}

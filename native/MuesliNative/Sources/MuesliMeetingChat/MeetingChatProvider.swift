public enum MeetingChatProviderAvailability: Equatable, Sendable {
    case available
    case unavailable(String)
}

public protocol MeetingChatProvider: AnyObject, Sendable {
    var name: String { get }
    var availability: MeetingChatProviderAvailability { get }

    func send(_ request: MeetingChatRequest) async throws -> MeetingChatProviderResponse
}

public final class MeetingChatProviderRouter: Sendable {
    private let providers: [any MeetingChatProvider]

    public init(providers: [any MeetingChatProvider]) {
        self.providers = providers
    }

    public func send(_ request: MeetingChatRequest) async throws -> MeetingChatProviderResponse {
        var lastError: Error?
        var hasAvailableProvider = false

        for provider in providers {
            guard provider.availability == .available else {
                continue
            }
            hasAvailableProvider = true
            do {
                let response = try await provider.send(request)
                let trimmed = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    throw MeetingChatError.emptyResponse(provider.name)
                }
                return MeetingChatProviderResponse(
                    text: trimmed,
                    sources: response.sources.isEmpty ? request.context.sources : response.sources
                )
            } catch {
                lastError = error
            }
        }

        if let error = lastError {
            if let chatError = error as? MeetingChatError {
                throw chatError
            }
            throw MeetingChatError.providerFailed(error.localizedDescription)
        }
        if !hasAvailableProvider {
            throw MeetingChatError.noAvailableProvider
        }
        throw MeetingChatError.noAvailableProvider
    }
}

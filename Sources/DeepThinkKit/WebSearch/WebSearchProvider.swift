import Foundation

// MARK: - Web Search Result

public struct WebSearchResult: Sendable, Codable {
    public let title: String
    public let snippet: String
    public let url: String
    public var pageContent: String?

    public init(title: String, snippet: String, url: String, pageContent: String? = nil) {
        self.title = title
        self.snippet = snippet
        self.url = url
        self.pageContent = pageContent
    }
}

// MARK: - Web Search Provider Protocol

public protocol WebSearchProvider: Sendable {
    func search(keywords: String, maxResults: Int) async throws -> [WebSearchResult]
}

// MARK: - Web Search Error

public enum WebSearchError: Error, Sendable {
    case networkError(underlying: Error)
    case invalidResponse
}

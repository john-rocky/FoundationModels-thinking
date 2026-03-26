import Foundation

// MARK: - Web Page Fetcher

/// Fetches web pages and extracts main text content, stripping navigation, ads, and boilerplate.
public struct WebPageFetcher: Sendable {

    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
    private static let maxContentLength = 800

    public init() {}

    /// Fetch a web page and return its main text content.
    /// Returns an empty string on any failure (never throws).
    public func fetchPageContent(url: String, timeout: TimeInterval = 5) async -> String {
        guard let pageURL = URL(string: url) else { return "" }

        var request = URLRequest(url: pageURL)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = timeout

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            return ""
        }

        return Self.extractMainContent(from: html)
    }

    // MARK: - Content Extraction

    /// Extract main text content from raw HTML.
    static func extractMainContent(from html: String) -> String {
        // Step 1: Remove boilerplate blocks entirely
        var cleaned = removeBoilerplateBlocks(html)

        // Step 2: Try to extract content from <article> or <main> tags
        if let articleContent = extractTagContent(from: cleaned, tag: "article") {
            cleaned = articleContent
        } else if let mainContent = extractTagContent(from: cleaned, tag: "main") {
            cleaned = mainContent
        } else if let bodyContent = extractTagContent(from: cleaned, tag: "body") {
            cleaned = bodyContent
        }

        // Step 3: Strip all remaining HTML tags and decode entities
        let text = stripHTMLTags(cleaned)

        // Step 4: Collapse whitespace and trim
        let collapsed = collapseWhitespace(text)

        // Step 5: Truncate to budget
        guard collapsed.count > maxContentLength else { return collapsed }
        let truncated = collapsed.prefix(maxContentLength)
        if let lastBreak = truncated.lastIndex(where: { $0 == "\n" || $0 == "." || $0 == "。" }) {
            return String(truncated[truncated.startIndex...lastBreak])
        }
        return String(truncated)
    }

    // MARK: - Private Helpers

    /// Remove script, style, nav, header, footer, aside, iframe, noscript blocks.
    private static func removeBoilerplateBlocks(_ html: String) -> String {
        let tagsToRemove = ["script", "style", "nav", "header", "footer", "aside", "iframe", "noscript", "svg"]
        var result = html
        for tag in tagsToRemove {
            let pattern = "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>"
            result = result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return result
    }

    /// Extract text content from the first occurrence of a given HTML tag.
    private static func extractTagContent(from html: String, tag: String) -> String? {
        let pattern = "<\(tag)[^>]*>([\\s\\S]*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }
        let content = String(html[range])
        guard content.count > 100 else { return nil }
        return content
    }

    /// Strip all HTML tags and decode common HTML entities.
    private static func stripHTMLTags(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#\\d+;", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&#x[0-9a-fA-F]+;", with: "", options: .regularExpression)
    }

    /// Collapse multiple whitespace characters into single spaces, preserve paragraph breaks.
    private static func collapseWhitespace(_ text: String) -> String {
        text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

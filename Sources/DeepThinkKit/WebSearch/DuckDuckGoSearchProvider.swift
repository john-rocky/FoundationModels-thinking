import Foundation

// MARK: - DuckDuckGo Search Provider

public final class DuckDuckGoSearchProvider: WebSearchProvider, Sendable {

    public init() {}

    public func search(keywords: String, maxResults: Int) async throws -> [WebSearchResult] {
        guard let encoded = keywords.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://html.duckduckgo.com/html/?q=\(encoded)") else {
            return []
        }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 10

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            throw WebSearchError.networkError(underlying: error)
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw WebSearchError.invalidResponse
        }

        return parseResults(html: html, maxResults: maxResults)
    }

    // MARK: - HTML Parsing

    private func parseResults(html: String, maxResults: Int) -> [WebSearchResult] {
        var results: [WebSearchResult] = []

        // Extract result link blocks: <a rel="nofollow" class="result__a" href="...">Title</a>
        let linkPattern = #"class="result__a"[^>]*href="([^"]*)"[^>]*>([\s\S]*?)</a>"#
        let snippetPattern = #"class="result__snippet"[^>]*>([\s\S]*?)</a>"#

        guard let linkRegex = try? NSRegularExpression(pattern: linkPattern),
              let snippetRegex = try? NSRegularExpression(pattern: snippetPattern) else {
            return []
        }

        let nsHTML = html as NSString
        let linkMatches = linkRegex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
        let snippetMatches = snippetRegex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))

        let count = min(linkMatches.count, maxResults)
        for i in 0..<count {
            let linkMatch = linkMatches[i]

            guard linkMatch.numberOfRanges >= 3,
                  let hrefRange = Range(linkMatch.range(at: 1), in: html),
                  let titleRange = Range(linkMatch.range(at: 2), in: html) else {
                continue
            }

            let rawHref = String(html[hrefRange])
            let rawTitle = String(html[titleRange])

            let url = extractRealURL(from: rawHref)
            let title = stripHTML(rawTitle)

            guard !url.isEmpty, !title.isEmpty else { continue }

            var snippet = ""
            if i < snippetMatches.count {
                let snippetMatch = snippetMatches[i]
                if snippetMatch.numberOfRanges >= 2,
                   let snippetRange = Range(snippetMatch.range(at: 1), in: html) {
                    snippet = stripHTML(String(html[snippetRange]))
                }
            }

            results.append(WebSearchResult(title: title, snippet: snippet, url: url))
        }

        return results
    }

    /// Extract the real URL from DuckDuckGo's redirect link.
    /// Format: //duckduckgo.com/l/?uddg=<percent-encoded-url>&...
    private func extractRealURL(from href: String) -> String {
        if let uddgRange = href.range(of: "uddg=") {
            let afterUddg = href[uddgRange.upperBound...]
            let encoded: String
            if let ampRange = afterUddg.range(of: "&") {
                encoded = String(afterUddg[..<ampRange.lowerBound])
            } else {
                encoded = String(afterUddg)
            }
            return encoded.removingPercentEncoding ?? encoded
        }
        // Direct URL (no redirect wrapper)
        if href.hasPrefix("http") {
            return href
        }
        if href.hasPrefix("//") {
            return "https:" + href
        }
        return href
    }

    private func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

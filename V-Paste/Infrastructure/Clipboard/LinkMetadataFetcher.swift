import AppKit
import Foundation

struct LinkMetadata: Equatable {
    let title: String?
    let iconURL: URL?
}

struct LinkPreviewMetadata: Equatable {
    let title: String?
    let assetPath: String?
    let thumbnailPath: String?
}

enum LinkMetadataParser {
    static func parse(html: String, pageURL: URL) -> LinkMetadata {
        let title = firstMetaContent(
            in: html,
            matching: [
                ("property", "og:title"),
                ("name", "twitter:title")
            ]
        ) ?? titleTag(in: html)

        return LinkMetadata(
            title: cleanText(title),
            iconURL: iconURL(in: html, pageURL: pageURL)
        )
    }

    private static func firstMetaContent(
        in html: String,
        matching attributes: [(name: String, value: String)]
    ) -> String? {
        tags(named: "meta", in: html).compactMap { tag in
            guard attributes.contains(where: { name, value in
                attribute(name, in: tag)?.caseInsensitiveCompare(value) == .orderedSame
            }) else {
                return nil
            }

            return attribute("content", in: tag)
        }.first
    }

    private static func titleTag(in html: String) -> String? {
        let pattern = #"<title\b[^>]*>(.*?)</title>"#
        guard let match = firstMatch(pattern, in: html, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }

        return match
    }

    private static func iconURL(in html: String, pageURL: URL) -> URL? {
        let candidates = tags(named: "link", in: html).compactMap { tag -> URL? in
            guard let rel = attribute("rel", in: tag)?.lowercased(),
                  rel.contains("icon"),
                  let href = attribute("href", in: tag)
            else {
                return nil
            }

            return URL(string: href, relativeTo: pageURL)?.absoluteURL
        }

        return candidates.first
            ?? URL(string: "/favicon.ico", relativeTo: pageURL)?.absoluteURL
    }

    private static func tags(named tagName: String, in html: String) -> [String] {
        let pattern = #"<\#(tagName)\b[^>]*>"#
        return allMatches(pattern, in: html, options: [.caseInsensitive])
    }

    private static func attribute(_ attributeName: String, in tag: String) -> String? {
        let pattern = #"\b\#(attributeName)\s*=\s*(['"])(.*?)\1"#
        guard let match = firstMatch(pattern, in: tag, options: [.caseInsensitive]) else {
            return nil
        }

        return decodeHTMLEntities(match)
    }

    private static func cleanText(_ text: String?) -> String? {
        let cleaned = text?
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned?.isEmpty == false ? cleaned : nil
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    private static func firstMatch(
        _ pattern: String,
        in string: String,
        options: NSRegularExpression.Options
    ) -> String? {
        allMatches(pattern, in: string, options: options).first
    }

    private static func allMatches(
        _ pattern: String,
        in string: String,
        options: NSRegularExpression.Options
    ) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }

        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return regex.matches(in: string, range: range).compactMap { match in
            let captureIndex = match.numberOfRanges > 2 ? 2 : match.numberOfRanges - 1
            guard captureIndex >= 0,
                  let captureRange = Range(match.range(at: captureIndex), in: string)
            else {
                return nil
            }

            return String(string[captureRange])
        }
    }
}

final class LinkMetadataFetcher {
    private let assetCache: AssetCache
    private let session: URLSession
    private let maxHTMLBytes = 512_000
    private let maxIconBytes = 2_000_000

    init(assetCache: AssetCache, session: URLSession = .shared) {
        self.assetCache = assetCache
        self.session = session
    }

    func preview(for url: URL, itemID: UUID) async throws -> LinkPreviewMetadata? {
        let (htmlData, response) = try await session.data(for: request(for: url))
        try validate(response)

        let responseURL = response.url ?? url
        let html = String(decoding: htmlData.prefix(maxHTMLBytes), as: UTF8.self)
        let metadata = LinkMetadataParser.parse(html: html, pageURL: responseURL)
        let iconPaths = try? await iconPaths(from: metadata.iconURL, itemID: itemID)

        guard metadata.title != nil || iconPaths?.thumbnailPath != nil else {
            return nil
        }

        return LinkPreviewMetadata(
            title: metadata.title,
            assetPath: iconPaths?.assetPath,
            thumbnailPath: iconPaths?.thumbnailPath
        )
    }

    private func iconPaths(
        from iconURL: URL?,
        itemID: UUID
    ) async throws -> (assetPath: String?, thumbnailPath: String?) {
        guard let iconURL else {
            return (nil, nil)
        }

        let (iconData, response) = try await session.data(for: request(for: iconURL))
        try validate(response)
        guard iconData.count <= maxIconBytes,
              let image = NSImage(data: iconData)
        else {
            return (nil, nil)
        }

        return try assetCache.storeImage(image, id: itemID)
    }

    private func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Mozilla/5.0 V-Paste Link Preview", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,image/avif,image/webp,image/png,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        return request
    }

    private func validate(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            return
        }

        guard (200..<400).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}

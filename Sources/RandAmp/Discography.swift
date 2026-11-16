import Foundation

/// A release listed on an artist's or a label's /music page.
struct Release: Identifiable, Equatable {
    var id: String { url.absoluteString }
    let title: String
    /// Only on a label's page, where each release is by one of its artists.
    let artist: String?
    let url: URL
    let artURL: URL?

    /// The same release, whatever the query Bandcamp adds to the link (?label=…&tab=music).
    func isSame(as page: URL) -> Bool {
        url.host?.lowercased() == page.host?.lowercased() && url.path == page.path
    }
}

extension Bandcamp {
    /// Every release of the /music page, in the site's order (usually the newest first).
    /// The first ones are only in the HTML grid; the rest are only in data-client-items.
    static func releases(at root: URL) async throws -> [Release] {
        let (data, response) = try await session.data(from: root.appendingPathComponent("music"))
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
            throw URLError(.badServerResponse)
        }
        let page = String(decoding: data, as: UTF8.self)
        let base = response.url ?? root
        var seen = Set<String>()
        var releases: [Release] = []
        for release in gridReleases(in: page, base: base) + clientReleases(in: page, base: base) {
            let key = (release.url.host ?? "") + release.url.path
            if seen.insert(key).inserted { releases.append(release) }
        }
        // A site with a single release redirects /music to that release.
        if releases.isEmpty, let json = attribute("data-tralbum", in: page),
           let root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] {
            let title = (root["current"] as? [String: Any])?["title"] as? String ?? ""
            releases = [Release(title: title, artist: nil, url: base, artURL: (root["art_id"] as? NSNumber).flatMap(art))]
        }
        return releases
    }

    /// A cover's small picture (150 × 150 pixels on Bandcamp's image server).
    private static func art(_ id: NSNumber) -> URL? {
        URL(string: String(format: "https://f4.bcbits.com/img/a%010lld_2.jpg", id.int64Value))
    }

    private static func gridReleases(in page: String, base: URL) -> [Release] {
        let item = try! NSRegularExpression(
            pattern: #"<li data-item-id="(?:album|track)-\d+"[^>]*>(.*?)</li>"#, options: .dotMatchesLineSeparators)
        let ns = page as NSString
        return item.matches(in: page, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            let html = ns.substring(with: match.range(at: 1))
            guard let href = first(#"<a href="([^"]+)""#, in: html),
                  let url = URL(string: unescape(href), relativeTo: base)?.absoluteURL else { return nil }
            // Covers further down load lazily: the real address is in data-original.
            let image = first(#"data-original="([^"]+)""#, in: html) ?? first(#"<img src="(https://[^"]+)""#, in: html)
            let titleHTML = first(#"<p class="title">(.*?)</p>"#, in: html) ?? ""
            let parts = titleHTML.components(separatedBy: "<br>")
            let artist = first(#"artist-override">(.*?)</span>"#, in: titleHTML).map(plain)
            return Release(title: plain(parts[0]), artist: artist?.isEmpty == false ? artist : nil,
                           url: url, artURL: image.flatMap(URL.init(string:)))
        }
    }

    private static func clientReleases(in page: String, base: URL) -> [Release] {
        guard let json = attribute("data-client-items", in: page),
              let items = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]]
        else { return [] }
        return items.compactMap { item in
            guard let path = item["page_url"] as? String,
                  let url = URL(string: path, relativeTo: base)?.absoluteURL else { return nil }
            return Release(title: item["title"] as? String ?? "", artist: item["artist"] as? String,
                           url: url, artURL: (item["art_id"] as? NSNumber).flatMap(art))
        }
    }

    private static func first(_ pattern: String, in text: String) -> String? {
        let regex = try! NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators)
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    /// Text without tags, entities decoded, spaces collapsed.
    private static func plain(_ html: String) -> String {
        let text = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return unescape(text).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The releases of each site seen in the Artist tab, kept while RandAmp runs.
@MainActor
final class DiscographyStore: ObservableObject {
    static let shared = DiscographyStore()

    enum State: Equatable {
        case loading
        case loaded([Release])
        case failed
    }

    @Published private(set) var states: [URL: State] = [:]

    func state(for site: URL) -> State? { states[site] }

    func load(_ site: URL) async {
        switch states[site] {
        case .loaded?, .loading?: return
        default: break
        }
        states[site] = .loading
        do {
            states[site] = .loaded(try await Bandcamp.releases(at: site))
        } catch {
            states[site] = .failed
        }
    }
}

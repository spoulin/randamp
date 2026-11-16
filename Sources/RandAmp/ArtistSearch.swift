import Foundation

/// An artist or a label found by Bandcamp's search.
struct FoundArtist: Identifiable, Equatable {
    let id: Int // Bandcamp's band id.
    let name: String
    let site: URL
    let location: String
    let genre: String
    let isLabel: Bool
    let imageURL: URL?

    /// "Label · Montréal · Electronic", leaving out what Bandcamp doesn't know.
    var details: String {
        ([isLabel ? "Label" : ""] + [location, genre]).filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var asArtist: Artist { Artist(url: site, name: name) }
}

/// Searches Bandcamp's artists and labels by name, with the endpoint of Bandcamp's own search box
/// (its suggestions as you type). It isn't a documented API, so Bandcamp may change it.
enum ArtistSearch {
    static func search(_ text: String) async throws -> [FoundArtist] {
        var request = URLRequest(url: URL(string: "https://bandcamp.com/api/bcsearch_public_api/1/autocomplete_elastic")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "search_text": text, "search_filter": "b", "full_page": false, "fan_id": NSNull(),
        ])
        let (data, response) = try await Bandcamp.session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = (root["auto"] as? [String: Any])?["results"] as? [[String: Any]]
        else { throw FollowingError.notFound }
        return results.compactMap { item in
            guard item["type"] as? String == "b",
                  let id = (item["id"] as? NSNumber)?.intValue,
                  let root = item["item_url_root"] as? String,
                  let site = ArtistStore.siteURL(from: root) else { return nil }
            return FoundArtist(id: id, name: item["name"] as? String ?? (site.host ?? ""), site: site,
                               location: item["location"] as? String ?? "",
                               genre: item["genre_name"] as? String ?? "",
                               isLabel: item["is_label"] as? Bool ?? false,
                               imageURL: (item["img"] as? String).flatMap(URL.init(string:)))
        }
    }
}

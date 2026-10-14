import Foundation

/// Iskanje in ujemanje opazovanih živil.
/// Slovenščina ima sklone ("piščančje prsi" / "piščančja prsa"), zato primerjamo
/// predpone besed: pri daljših besedah odrežemo zadnji dve črki, pri krajših eno.
/// Enako pravilo uporablja Flutter aplikacija (lib/logic/matching.dart).
enum Matching {
    static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "sl_SI"))
            .lowercased()
    }

    static func words(_ s: String) -> [String] {
        normalize(s).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    static func stem(_ w: String) -> String {
        let n = w.count
        if n <= 3 { return w }
        if n <= 5 { return String(w.prefix(n - 1)) }
        return String(w.prefix(n - 2))
    }

    /// Ali ime izdelka vsebuje vse besede iskalnega niza (po predponah)?
    static func matches(term: String, name: String) -> Bool {
        let termWords = words(term)
        guard !termWords.isEmpty else { return false }
        let nameWords = words(name)
        return termWords.allSatisfy { tw in
            let st = stem(tw)
            return nameWords.contains { $0.hasPrefix(st) }
        }
    }

    static func matchesSearch(_ query: String, offer: Offer) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return true }
        return matches(term: q, name: "\(offer.name) \(offer.brand ?? "") \(offer.chain)")
    }
}

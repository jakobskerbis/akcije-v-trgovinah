import Foundation

/// Iskanje in ujemanje opazovanih živil.
/// Slovenščina ima sklone ("piščančje prsi" / "piščančja prsa"), zato primerjamo
/// predpone besed: pri daljših besedah odrežemo zadnji dve črki, pri krajših eno.
/// Enako pravilo uporablja Flutter aplikacija (lib/logic/matching.dart).
struct WatchTerm: Hashable {
    let term: String
    let category: String?
}

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

    /// Opazovano živilo s kategorijo: "mleko" v kategoriji mlečni izdelki ne zadene
    /// "Mleko za čiščenje" (drogerija).
    static func matches(_ w: WatchTerm, offer: Offer) -> Bool {
        if let c = w.category, offer.category != c { return false }
        return matches(term: w.term, name: offer.name)
    }

    /// Kategorija za novo opazovano živilo: najpogostejša med trenutnimi zadetki,
    /// če obsega vsaj polovico zadetkov.
    static func inferCategory(term: String, offers: [Offer]) -> String? {
        var counts: [String: Int] = [:]
        var total = 0
        for o in offers where !o.isExpired() && matches(term: term, name: o.name) {
            total += 1
            if let c = o.category { counts[c, default: 0] += 1 }
        }
        guard let best = counts.max(by: { $0.value < $1.value }), total > 0,
              Double(best.value) / Double(total) >= 0.5 else { return nil }
        return best.key
    }

    static func matchesSearch(_ query: String, offer: Offer) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return true }
        return matches(term: q, name: "\(offer.name) \(offer.brand ?? "") \(offer.chain)")
    }
}

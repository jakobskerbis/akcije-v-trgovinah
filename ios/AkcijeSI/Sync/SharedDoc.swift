import Foundation

/// Oblika datoteke shared.json v zasebnem repozitoriju (enaka v Flutter aplikaciji).
struct SharedDoc: Codable, Equatable {
    var schemaVersion: Int = 1
    var updatedAt: String = SharedTime.now()
    var watch: [SharedWatch] = []
    var shopping: [SharedShopping] = []
}

struct SharedWatch: Codable, Equatable {
    var id: String
    var term: String
    var category: String?
    var createdAt: String
    var updatedAt: String
    var deleted: Bool
    var by: String?
}

struct SharedShopping: Codable, Equatable {
    var id: String
    var title: String
    var offerId: String?
    var productKey: String?
    var chain: String?
    var price: Double?
    var quantity: Int
    var checked: Bool
    var note: String?
    var createdAt: String
    var updatedAt: String
    var deleted: Bool
    var by: String?
}

/// Časovni žigi: UTC, milisekunde, npr. "2026-10-14T08:30:00.123Z".
enum SharedTime {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func string(_ d: Date) -> String { withFraction.string(from: d) }
    static func now() -> String { string(.now) }

    static func date(_ s: String) -> Date {
        if let d = withFraction.date(from: s) ?? plain.date(from: s) { return d }
        // Dart lahko zapiše mikrosekunde – odrežemo na milisekunde
        if let dot = s.firstIndex(of: "."), let z = s.lastIndex(where: { $0 == "Z" || $0 == "+" }) {
            let frac = s[s.index(after: dot)..<z].prefix(3)
            let fixed: String = String(s[..<dot]) + "." + String(frac) + String(s[z...])
            if let d = withFraction.date(from: fixed) { return d }
        }
        return .distantPast
    }
}

enum SharedMerge {
    static let tombstoneDays: Double = 30

    /// Združi dva seznama po id; zmaga novejši updatedAt (pri enakem oddaljeni).
    static func merge<T>(_ remote: [T], _ local: [T], id: (T) -> String, updated: (T) -> String) -> [T] {
        var byId: [String: T] = [:]
        for r in remote { byId[id(r)] = r }
        for l in local {
            if let r = byId[id(l)] {
                if SharedTime.date(updated(l)) > SharedTime.date(updated(r)) { byId[id(l)] = l }
            } else {
                byId[id(l)] = l
            }
        }
        return Array(byId.values)
    }

    static func purge(_ doc: inout SharedDoc, now: Date = .now) {
        let cutoff = now.addingTimeInterval(-tombstoneDays * 86400)
        doc.watch.removeAll { $0.deleted && SharedTime.date($0.updatedAt) < cutoff }
        doc.shopping.removeAll { $0.deleted && SharedTime.date($0.updatedAt) < cutoff }
        doc.watch.sort { $0.createdAt < $1.createdAt }
        doc.shopping.sort { $0.createdAt < $1.createdAt }
    }
}

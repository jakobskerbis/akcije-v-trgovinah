import Foundation

// MARK: - Ponudbe (offers.json)

struct OffersFile: Codable {
    var schemaVersion: Int?
    var generatedAt: String?
    var offers: [Offer]
}

enum ConditionType: String, Codable, CaseIterable {
    case none, loyaltyCard, app, coupon, multiBuy

    var label: String {
        switch self {
        case .none: return "Brez pogoja"
        case .loyaltyCard: return "Kartica"
        case .app: return "Aplikacija"
        case .coupon: return "Kupon"
        case .multiBuy: return "Količinski"
        }
    }

    var symbol: String {
        switch self {
        case .none: return "checkmark.seal"
        case .loyaltyCard: return "creditcard"
        case .app: return "iphone"
        case .coupon: return "ticket"
        case .multiBuy: return "square.stack.3d.up"
        }
    }
}

struct OfferCondition: Codable, Hashable {
    var type: ConditionType
    var description: String?

    init(type: ConditionType, description: String?) {
        self.type = type
        self.description = description
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decodeIfPresent(String.self, forKey: .type) ?? "none"
        type = ConditionType(rawValue: raw) ?? .none
        description = try c.decodeIfPresent(String.self, forKey: .description)
    }
}

struct Offer: Codable, Identifiable, Hashable {
    var id: String
    var productKey: String?
    var chain: String
    var name: String
    var brand: String?
    var category: String?
    var kind: String?
    var packSize: String?
    var price: Double
    var regularPrice: Double?
    var discountPct: Int?
    var unitPrice: Double?
    var unit: String?
    var bestUnitPrice: Bool?
    var validFrom: String?
    var validTo: String?
    var condition: OfferCondition
    var ean: String?
    var sourceUrl: String?
    var imageUrl: String?
    var fetchedAt: String?
    var stale: Bool?

    var validFromDate: Date? { validFrom.flatMap(DateParsing.day) }
    var validToDate: Date? { validTo.flatMap(DateParsing.day) }
    var isBestUnitPrice: Bool { bestUnitPrice ?? false }

    /// Število dni do konca akcije (0 = danes zadnji dan), nil če ni znano.
    func daysLeft(now: Date = .now) -> Int? {
        guard let end = validToDate else { return nil }
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: end)).day
    }

    func isStarted(now: Date = .now) -> Bool {
        guard let start = validFromDate else { return true }
        return Calendar.current.startOfDay(for: start) <= now
    }

    func isExpired(now: Date = .now) -> Bool {
        guard let d = daysLeft(now: now) else { return false }
        return d < 0
    }

    var historyKey: String { "\(productKey ?? id)|\(condition.type.rawValue)" }
}

// MARK: - Kuponi (coupons.json)

struct CouponsFile: Codable {
    var generatedAt: String?
    var coupons: [Coupon]
}

struct Coupon: Codable, Identifiable, Hashable {
    var id: String
    var chain: String
    var title: String
    var discount: String?
    var conditions: String?
    var validFrom: String?
    var validTo: String?
    var howToRedeem: String
    var personal: Bool?
    var needsActivation: Bool?
    var imageUrl: String?
    var backImageUrl: String?
    var sourceUrl: String

    var redeemLabel: String {
        switch howToRedeem {
        case "app": return "V aplikaciji"
        case "card": return "S kartico"
        case "printed": return "Tiskan kupon"
        default: return howToRedeem
        }
    }
}

// MARK: - Meta (meta.json)

struct MetaFile: Codable {
    var generatedAt: String?
    var discountThresholdDefault: Int?
    var sources: [SourceStatus]
    var chains: [Chain]
    var catalogs: [Catalog]?
    var sections: [SectionInfo]
    var categories: [CategoryInfo]
    var kinds: [KindInfo]?
}

struct SourceStatus: Codable, Hashable, Identifiable {
    var chain: String
    var source: String
    var url: String
    var status: String
    var count: Int
    var error: String?
    var fetchedAt: String?
    var notes: [String]?
    var id: String { chain + source }
}

struct Chain: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var color: String
    var website: String?
    var catalogUrl: String?
    var section: String?
}

struct Catalog: Codable, Hashable, Identifiable {
    var chain: String
    var title: String
    var url: String
    var validFrom: String?
    var validTo: String?
    var id: String { url }
}

struct SectionInfo: Codable, Hashable, Identifiable {
    var id: String
    var label: String
}

struct CategoryInfo: Codable, Hashable, Identifiable {
    var id: String
    var label: String
    var section: String
    var food: Bool
    var icon: String
}

struct KindInfo: Codable, Hashable, Identifiable {
    var id: String
    var label: String
}

// MARK: - Zgodovina cen (history.json): { "kljuc": [["2026-10-14", 2.49], ...] }

struct PricePoint: Hashable, Identifiable {
    var date: Date
    var price: Double
    var id: Date { date }
}

enum HistoryDecoding {
    static func decode(_ data: Data) -> [String: [PricePoint]] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: [[Any]]] else { return [:] }
        var out: [String: [PricePoint]] = [:]
        out.reserveCapacity(obj.count)
        for (k, rows) in obj {
            out[k] = rows.compactMap { row in
                guard row.count == 2, let s = row[0] as? String, let d = DateParsing.day(s) else { return nil }
                let p = (row[1] as? NSNumber)?.doubleValue ?? 0
                return PricePoint(date: d, price: p)
            }
        }
        return out
    }
}

// MARK: - Datumi

enum DateParsing {
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Ljubljana")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func day(_ s: String) -> Date? { dayFormatter.date(from: String(s.prefix(10))) }

    static func iso(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    static func short(_ d: Date) -> String {
        d.formatted(.dateTime.day().month(.defaultDigits).locale(Locale(identifier: "sl_SI")))
    }
}

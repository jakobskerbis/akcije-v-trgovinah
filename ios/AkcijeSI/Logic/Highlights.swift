import Foundation

enum HighlightReason: String, CaseIterable, Hashable {
    case watch, discount, bestUnit

    var title: String {
        switch self {
        case .watch: return "Z najinega seznama"
        case .discount: return "Velik popust"
        case .bestUnit: return "Najnižja cena na enoto"
        }
    }

    var symbol: String {
        switch self {
        case .watch: return "eye"
        case .discount: return "percent"
        case .bestUnit: return "scalemass"
        }
    }
}

enum SortOrder: String, CaseIterable, Identifiable {
    case discount, unitPrice, price, ending
    var id: String { rawValue }
    var label: String {
        switch self {
        case .discount: return "Popust"
        case .unitPrice: return "Cena na enoto"
        case .price: return "Cena"
        case .ending: return "Konec akcije"
        }
    }
}

struct OfferFilter: Equatable {
    var chains: Set<String> = []          // prazno = vse
    var categories: Set<String> = []      // prazno = vse
    var conditions: Set<ConditionType> = []
    var onlyActive = false                // skrij akcije, ki se še niso začele
    var section: String = "zivila"

    func accepts(_ o: Offer, categorySection: [String: String]) -> Bool {
        if let cat = o.category, let sec = categorySection[cat], sec != section { return false }
        if !chains.isEmpty && !chains.contains(o.chain) { return false }
        if !categories.isEmpty && !categories.contains(o.category ?? "") { return false }
        if !conditions.isEmpty && !conditions.contains(o.condition.type) { return false }
        if onlyActive && !o.isStarted() { return false }
        if o.isExpired() { return false }
        return true
    }

    var isActive: Bool { !chains.isEmpty || !categories.isEmpty || !conditions.isEmpty || onlyActive }
}

enum Highlights {
    static func reasons(for o: Offer, threshold: Int, watchTerms: [WatchTerm]) -> Set<HighlightReason> {
        var r = Set<HighlightReason>()
        if (o.discountPct ?? 0) >= threshold { r.insert(.discount) }
        if o.isBestUnitPrice { r.insert(.bestUnit) }
        if watchTerms.contains(where: { Matching.matches($0, offer: o) }) { r.insert(.watch) }
        return r
    }

    static func sort(_ offers: [Offer], by order: SortOrder) -> [Offer] {
        switch order {
        case .discount:
            return offers.sorted { ($0.discountPct ?? -1, -$0.price) > ($1.discountPct ?? -1, -$1.price) }
        case .unitPrice:
            return offers.sorted { ($0.unitPrice ?? .infinity) < ($1.unitPrice ?? .infinity) }
        case .price:
            return offers.sorted { $0.price < $1.price }
        case .ending:
            return offers.sorted { ($0.daysLeft() ?? Int.max) < ($1.daysLeft() ?? Int.max) }
        }
    }
}

enum Format {
    static let euro: FloatingPointFormatStyle<Double>.Currency =
        .currency(code: "EUR").locale(Locale(identifier: "sl_SI"))

    static func price(_ v: Double) -> String { v.formatted(euro) }

    static func unitPrice(_ o: Offer) -> String? {
        guard let up = o.unitPrice, let u = o.unit else { return nil }
        return "\(price(up))/\(u)"
    }

    static func daysLeft(_ o: Offer) -> String? {
        if !o.isStarted(), let s = o.validFromDate { return "od \(DateParsing.short(s))" }
        guard let d = o.daysLeft() else { return o.chain == "hofer" ? "do razprodaje" : nil }
        switch d {
        case ..<0: return "poteklo"
        case 0: return "še danes"
        case 1: return "še 1 dan"
        case 2: return "še 2 dneva"
        case 3, 4: return "še \(d) dni"
        default: return "še \(d) dni"
        }
    }
}

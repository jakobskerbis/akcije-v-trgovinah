import Foundation
import Observation
import SwiftData

/// Osrednji vir podatkov: prenese JSON z GitHub Pages (ali iz veje "data"),
/// ga shrani v SwiftData predpomnilnik in ga dekodira za prikaz.
@MainActor
@Observable
final class AppStore {
    static let feeds = ["offers", "coupons", "meta", "guide", "history"]
    static let primaryBase = URL(string: "https://jakobskerbis.github.io/akcije-v-trgovinah/")!
    static let fallbackBase = URL(string: "https://raw.githubusercontent.com/jakobskerbis/akcije-v-trgovinah/data/")!

    var offers: [Offer] = []
    var coupons: [Coupon] = []
    var meta: MetaFile?
    var guide: Guide?
    var history: [String: [PricePoint]] = [:]

    var isRefreshing = false
    var lastError: String?
    var lastFetched: Date?
    var generatedAt: Date?

    private(set) var chainsById: [String: Chain] = [:]
    private(set) var categoriesById: [String: CategoryInfo] = [:]
    private(set) var categorySection: [String: String] = [:]
    private(set) var offersById: [String: Offer] = [:]

    let demoMode: Bool

    init(demoMode: Bool = ProcessInfo.processInfo.arguments.contains("-demo")) {
        self.demoMode = demoMode
    }

    // MARK: Nalaganje

    func loadCached(context: ModelContext) {
        if demoMode {
            loadDemo()
            return
        }
        let all = (try? context.fetch(FetchDescriptor<CachedFeed>())) ?? []
        for feed in all { apply(name: feed.name, data: feed.data) }
        lastFetched = all.map(\.fetchedAt).max()
        rebuildIndexes()
    }

    private func loadDemo() {
        for name in Self.feeds {
            if let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "Demo")
                ?? Bundle.main.url(forResource: name, withExtension: "json"),
               let data = try? Data(contentsOf: url) {
                apply(name: name, data: data)
            }
        }
        lastFetched = .now
        rebuildIndexes()
    }

    /// Prenese vse datoteke. Vrne ID-je ponudb, ki so nove glede na prejšnje stanje.
    @discardableResult
    func refresh(context: ModelContext) async -> Set<String> {
        if demoMode { return [] }
        guard !isRefreshing else { return [] }
        isRefreshing = true
        defer { isRefreshing = false }
        let before = Set(offers.map(\.id))
        var errors: [String] = []
        for name in Self.feeds {
            do {
                let data = try await download(name: name)
                apply(name: name, data: data)
                upsert(name: name, data: data, context: context)
            } catch {
                errors.append("\(name): \(error.localizedDescription)")
            }
        }
        try? context.save()
        rebuildIndexes()
        lastError = errors.isEmpty ? nil : errors.joined(separator: "\n")
        if errors.count < Self.feeds.count { lastFetched = .now }
        return Set(offers.map(\.id)).subtracting(before)
    }

    private func download(name: String) async throws -> Data {
        var lastErr: Error = URLError(.badServerResponse)
        for base in [Self.primaryBase, Self.fallbackBase] {
            var req = URLRequest(url: base.appendingPathComponent("\(name).json"))
            req.cachePolicy = .reloadIgnoringLocalCacheData
            req.timeoutInterval = 30
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty {
                    return data
                }
                lastErr = URLError(.badServerResponse)
            } catch {
                lastErr = error
            }
        }
        throw lastErr
    }

    private func upsert(name: String, data: Data, context: ModelContext) {
        let pred = #Predicate<CachedFeed> { $0.name == name }
        if let existing = try? context.fetch(FetchDescriptor(predicate: pred)).first {
            existing.data = data
            existing.fetchedAt = .now
        } else {
            context.insert(CachedFeed(name: name, data: data))
        }
    }

    private func apply(name: String, data: Data) {
        let dec = JSONDecoder()
        switch name {
        case "offers":
            if let f = try? dec.decode(OffersFile.self, from: data) {
                offers = f.offers
                generatedAt = DateParsing.iso(f.generatedAt)
            }
        case "coupons":
            if let f = try? dec.decode(CouponsFile.self, from: data) { coupons = f.coupons }
        case "meta":
            if let f = try? dec.decode(MetaFile.self, from: data) { meta = f }
        case "guide":
            if let f = try? dec.decode(Guide.self, from: data) { guide = f }
        case "history":
            history = HistoryDecoding.decode(data)
        default:
            break
        }
    }

    private func rebuildIndexes() {
        chainsById = Dictionary((meta?.chains ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        categoriesById = Dictionary((meta?.categories ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        categorySection = categoriesById.mapValues(\.section)
        offersById = Dictionary(offers.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: Pomožne poizvedbe

    var sections: [SectionInfo] {
        meta?.sections ?? [SectionInfo(id: "zivila", label: "Živila in vsakdanje potrebščine"),
                           SectionInfo(id: "dom", label: "Dom, vrt in DIY")]
    }

    func categories(in section: String) -> [CategoryInfo] {
        (meta?.categories ?? []).filter { $0.section == section }
    }

    func chain(_ id: String) -> Chain? { chainsById[id] }
    func chainName(_ id: String) -> String { chainsById[id]?.name ?? id.capitalized }
    func category(_ id: String?) -> CategoryInfo? { id.flatMap { categoriesById[$0] } }
    func offer(id: String) -> Offer? { offersById[id] }

    func visibleOffers(filter: OfferFilter, search: String) -> [Offer] {
        offers.filter { filter.accepts($0, categorySection: categorySection) && Matching.matchesSearch(search, offer: $0) }
    }

    func count(category: String) -> Int {
        offers.lazy.filter { $0.category == category && !$0.isExpired() }.count
    }

    /// Primerjava med verigami: ista EAN koda ali ista vrsta živila.
    func comparable(to o: Offer) -> [Offer] {
        let same = offers.filter { other in
            guard other.id != o.id, !other.isExpired() else { return false }
            if let e = o.ean, let e2 = other.ean, e == e2 { return true }
            if let k = o.kind, k == other.kind, other.unit == o.unit { return true }
            return false
        }
        return same.sorted { ($0.unitPrice ?? $0.price) < ($1.unitPrice ?? $1.price) }
    }

    func history(for o: Offer) -> [PricePoint] {
        (history[o.historyKey] ?? []).sorted { $0.date < $1.date }
    }

    func catalogs(for chain: String? = nil) -> [Catalog] {
        let all = meta?.catalogs ?? []
        return chain.map { c in all.filter { $0.chain == c } } ?? all
    }
}

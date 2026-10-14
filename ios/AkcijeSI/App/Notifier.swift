import Foundation
import SwiftData
import UserNotifications

/// Lokalna obvestila: opazovana živila in nove izpostavljene akcije.
enum Notifier {
    private static let notifiedKey = "notifiedOfferIds"

    static func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    @MainActor
    static func notifyNew(store: AppStore, context: ModelContext) async {
        let d = UserDefaults.standard
        let notifyWatch = d.object(forKey: "notifyWatch") as? Bool ?? true
        let notifyHighlights = d.object(forKey: "notifyHighlights") as? Bool ?? true
        let threshold = d.object(forKey: "threshold") as? Int ?? store.meta?.discountThresholdDefault ?? 30
        guard notifyWatch || notifyHighlights else { return }

        var already = Set(d.stringArray(forKey: notifiedKey) ?? [])
        let firstRun = already.isEmpty
        let terms = ((try? context.fetch(FetchDescriptor<WatchItem>())) ?? []).filter { !$0.deleted }.map(\.term)
        let active = store.offers.filter { !$0.isExpired() }

        var watchHits: [(Offer, String)] = []
        var highlightHits: [Offer] = []
        for o in active where !already.contains(o.id) {
            if notifyWatch, let t = terms.first(where: { Matching.matches(term: $0, name: o.name) }) {
                watchHits.append((o, t))
            } else if notifyHighlights,
                      store.category(o.category)?.food == true,
                      (o.discountPct ?? 0) >= threshold || o.isBestUnitPrice {
                highlightHits.append(o)
            }
        }
        // ob prvem zagonu ne zasujemo uporabnika z obvestili za vse obstoječe akcije
        if !firstRun {
            for (o, term) in watchHits.prefix(5) {
                await post(id: "watch-\(o.id)",
                           title: "\(store.chainName(o.chain)): \(o.name)",
                           body: "\(Format.price(o.price))\(o.discountPct.map { " (−\($0) %)" } ?? "") · opazuješ »\(term)«")
            }
            if watchHits.count > 5 {
                await post(id: "watch-more", title: "Opazovana živila", body: "Še \(watchHits.count - 5) novih zadetkov na tvojem seznamu.")
            }
            if !highlightHits.isEmpty {
                let top = highlightHits.sorted { ($0.discountPct ?? 0) > ($1.discountPct ?? 0) }.prefix(3)
                let names = top.map { "\($0.name) −\($0.discountPct ?? 0) %" }.joined(separator: ", ")
                await post(id: "highlights-\(Int(Date.now.timeIntervalSince1970))",
                           title: "\(highlightHits.count) novih izpostavljenih akcij", body: names)
            }
        }
        for o in active { already.insert(o.id) }
        // obdrži le ID-je še veljavnih ponudb, da seznam ne raste v nedogled
        let activeIds = Set(active.map(\.id))
        d.set(Array(already.intersection(activeIds)), forKey: notifiedKey)
    }

    private static func post(id: String, title: String, body: String) async {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        let req = UNNotificationRequest(identifier: id, content: c, trigger: nil)
        try? await UNUserNotificationCenter.current().add(req)
    }
}

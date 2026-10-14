import Charts
import SwiftData
import SwiftUI

struct OfferDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(SyncService.self) private var sync
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    let offer: Offer
    @State private var added = 0
    @State private var watched = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                actions
                historySection
                comparisonSection
                infoSection
            }
            .padding()
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(offer.name)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: added)
        .sensoryFeedback(.selection, trigger: watched)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            OfferImage(url: offer.imageUrl, size: 120)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    ChainTag(chain: offer.chain)
                    if let c = store.category(offer.category) {
                        Label(c.label, systemImage: c.icon).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(offer.name).font(.title3.weight(.semibold))
                if let b = offer.brand { Text(b).foregroundStyle(.secondary) }
                if let p = offer.packSize { Text(p).font(.subheadline).foregroundStyle(.secondary) }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(Format.price(offer.price)).font(.largeTitle.weight(.bold)).monospacedDigit()
                    if let p = offer.discountPct, p > 0 { DiscountBadge(pct: p) }
                }
                if let r = offer.regularPrice {
                    Text("Redna cena \(Format.price(r))").strikethrough().foregroundStyle(.secondary)
                }
                if let up = Format.unitPrice(offer) {
                    Label(up, systemImage: offer.isBestUnitPrice ? "scalemass.fill" : "scalemass")
                        .foregroundStyle(offer.isBestUnitPrice ? .green : .secondary)
                }
                HStack { ConditionBadge(condition: offer.condition); DaysLeftLabel(offer: offer) }
            }
        }
    }

    private var actions: some View {
        HStack {
            Button {
                ListActions.addToShopping(offer, context: context, sync: sync)
                added += 1
            } label: {
                Label("Na seznam", systemImage: "cart.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            Button {
                ListActions.addWatch(term: watchTerm, category: offer.category, context: context, sync: sync)
                watched += 1
            } label: {
                Label("Opazuj »\(watchTerm)«", systemImage: "eye")
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
            if let s = offer.sourceUrl, let u = URL(string: s) {
                Button { openURL(u) } label: { Label("Vir", systemImage: "safari") }
                    .buttonStyle(.bordered)
            }
        }
        .controlSize(.regular)
    }

    /// Prvi dve besedi imena (npr. "Piščančje prsi") kot predlog za opazovanje.
    private var watchTerm: String {
        let words = offer.name.split(separator: " ").prefix(2).map { $0.trimmingCharacters(in: .punctuationCharacters) }
        return words.joined(separator: " ")
    }

    @ViewBuilder private var historySection: some View {
        let points = store.history(for: offer)
        VStack(alignment: .leading, spacing: 8) {
            Text("Zgodovina cene").font(.headline)
            if points.count < 2 {
                Text(points.isEmpty ? "Zgodovina se še zbira." : "Za zdaj en zapis: \(Format.price(points[0].price)) (\(DateParsing.short(points[0].date))).")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Chart(points) { p in
                    LineMark(x: .value("Datum", p.date), y: .value("Cena", p.price))
                        .interpolationMethod(.stepEnd)
                    PointMark(x: .value("Datum", p.date), y: .value("Cena", p.price))
                }
                .chartYAxisLabel("€")
                .frame(height: 180)
                let minP = points.map(\.price).min() ?? offer.price
                Text("Najnižja zabeležena cena: \(Format.price(minP))").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var comparisonSection: some View {
        let others = store.comparable(to: offer)
        VStack(alignment: .leading, spacing: 8) {
            Text("Primerjava med trgovinami").font(.headline)
            if others.isEmpty {
                Text("Ta teden ni primerljivih akcij v drugih trgovinah.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(others.prefix(12)) { o in
                    NavigationLink(value: o) {
                        HStack {
                            ChainTag(chain: o.chain)
                            Text(o.name).lineLimit(1)
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(Format.price(o.price)).monospacedDigit().bold()
                                if let up = Format.unitPrice(o) { Text(up).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let f = offer.validFromDate, let t = offer.validToDate {
                Text("Velja od \(DateParsing.short(f)) do \(DateParsing.short(t))")
            } else if let f = offer.validFromDate {
                Text("Velja od \(DateParsing.short(f))")
            }
            if let e = offer.ean { Text("EAN: \(e)") }
            if offer.stale == true { Text("Podatek iz prejšnjega zajema (vir trenutno ni dosegljiv).").foregroundStyle(.orange) }
            Text("Velja cena v trgovini. Podatki so informativni.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

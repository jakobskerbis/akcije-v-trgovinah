import SwiftData
import SwiftUI

enum BrowseScope: Hashable {
    case highlights
    case category(String)
    case chain(String)
    case all
}

struct OfferGroup: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let offers: [Offer]
}

@MainActor
enum Browse {
    static func groups(scope: BrowseScope, store: AppStore, ui: UIState, watchTerms: [WatchTerm], threshold: Int) -> [OfferGroup] {
        let base = store.visibleOffers(filter: ui.filter, search: ui.search)
        switch scope {
        case .highlights:
            let watch = base.filter { o in watchTerms.contains { Matching.matches($0, offer: o) } }
            let discount = base.filter { ($0.discountPct ?? 0) >= threshold }
            let best = base.filter(\.isBestUnitPrice)
            var out: [OfferGroup] = []
            if !watch.isEmpty {
                out.append(OfferGroup(id: "watch", title: HighlightReason.watch.title, symbol: HighlightReason.watch.symbol,
                                      offers: Highlights.sort(watch, by: ui.sort)))
            }
            if !best.isEmpty {
                out.append(OfferGroup(id: "best", title: HighlightReason.bestUnit.title, symbol: HighlightReason.bestUnit.symbol,
                                      offers: Highlights.sort(best, by: ui.sort == .discount ? .unitPrice : ui.sort)))
            }
            out.append(OfferGroup(id: "discount", title: "Popust ≥ \(threshold) %", symbol: HighlightReason.discount.symbol,
                                  offers: Highlights.sort(discount, by: ui.sort)))
            return out
        case .category(let c):
            let list = base.filter { $0.category == c }
            return [OfferGroup(id: "cat-\(c)", title: store.category(c)?.label ?? c, symbol: store.category(c)?.icon ?? "tag",
                               offers: Highlights.sort(list, by: ui.sort))]
        case .chain(let ch):
            let list = base.filter { $0.chain == ch }
            return [OfferGroup(id: "chain-\(ch)", title: store.chainName(ch), symbol: "cart",
                               offers: Highlights.sort(list, by: ui.sort))]
        case .all:
            return [OfferGroup(id: "all", title: "Vse ponudbe", symbol: "list.bullet", offers: Highlights.sort(base, by: ui.sort))]
        }
    }

    static func title(_ scope: BrowseScope, store: AppStore) -> String {
        switch scope {
        case .highlights: return "Izpostavljeno"
        case .category(let c): return store.category(c)?.label ?? c
        case .chain(let ch): return store.chainName(ch)
        case .all: return "Vse ponudbe"
        }
    }
}

/// Izbira sekcije: živila / dom, vrt in DIY.
struct StoreSectionPicker: View {
    @Environment(AppStore.self) private var store
    @Environment(UIState.self) private var ui

    var body: some View {
        Picker("Sekcija", selection: Binding(get: { ui.storeSection }, set: { ui.setStoreSection($0) })) {
            ForEach(store.sections) { s in
                Text(s.id == "zivila" ? "Živila" : "Dom in vrt").tag(s.id)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Sekcija")
    }
}

struct SortMenu: View {
    @Environment(UIState.self) private var ui

    var body: some View {
        Menu {
            Picker("Razvrsti", selection: Binding(get: { ui.sort }, set: { ui.sort = $0 })) {
                ForEach(SortOrder.allCases) { Text($0.label).tag($0) }
            }
        } label: {
            Label("Razvrsti", systemImage: "arrow.up.arrow.down")
        }
    }
}

struct FilterSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(UIState.self) private var ui
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var ui = ui
        NavigationStack {
            Form {
                Section("Trgovine") {
                    ForEach(store.meta?.chains ?? []) { ch in
                        Toggle(isOn: binding(for: ch.id, in: \.chains)) {
                            HStack {
                                Circle().fill(Color(hex: ch.color)).frame(width: 10, height: 10)
                                Text(ch.name)
                                Spacer()
                                Text("\(store.offers.filter { $0.chain == ch.id }.count)").foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    }
                }
                Section("Kategorije") {
                    ForEach(store.categories(in: ui.storeSection)) { c in
                        Toggle(isOn: binding(for: c.id, in: \.categories)) {
                            Label(c.label, systemImage: c.icon)
                        }
                    }
                }
                Section("Pogoj akcije") {
                    ForEach(ConditionType.allCases, id: \.self) { t in
                        Toggle(isOn: Binding(
                            get: { ui.filter.conditions.contains(t) },
                            set: { on in if on { ui.filter.conditions.insert(t) } else { ui.filter.conditions.remove(t) } }
                        )) { Label(t.label, systemImage: t.symbol) }
                    }
                }
                Section {
                    Toggle("Samo akcije, ki že veljajo", isOn: $ui.filter.onlyActive)
                }
            }
            .navigationTitle("Filtri")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Ponastavi") {
                        let s = ui.filter.section
                        ui.filter = OfferFilter()
                        ui.filter.section = s
                    }
                    .disabled(!ui.filter.isActive)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Končano") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func binding(for id: String, in path: WritableKeyPath<OfferFilter, Set<String>>) -> Binding<Bool> {
        Binding(
            get: { ui.filter[keyPath: path].contains(id) },
            set: { on in
                if on { ui.filter[keyPath: path].insert(id) } else { ui.filter[keyPath: path].remove(id) }
            }
        )
    }
}

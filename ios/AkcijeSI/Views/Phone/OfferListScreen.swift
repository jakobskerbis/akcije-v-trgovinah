import SwiftData
import SwiftUI

/// Seznam ponudb za iPhone (in ozko okno na iPadu): izpostavljeno, kategorija ali trgovina.
struct OfferListScreen: View {
    @Environment(AppStore.self) private var store
    @Environment(UIState.self) private var ui
    @Environment(SyncService.self) private var sync
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<WatchItem> { !$0.deleted }) private var watch: [WatchItem]
    @AppStorage("threshold") private var threshold = 30
    let scope: BrowseScope
    @State private var addedTick = 0

    var body: some View {
        let terms = watch.map { WatchTerm(term: $0.term, category: $0.category) }
        let groups = Browse.groups(scope: scope, store: store, ui: ui, watchTerms: terms, threshold: threshold)
        List {
            if case .highlights = scope {
                Section { StoreSectionPicker() }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
            ForEach(groups) { g in
                Section {
                    if g.offers.isEmpty {
                        Text("Ni zadetkov.").foregroundStyle(.secondary)
                    }
                    ForEach(g.offers.prefix(300)) { o in
                        NavigationLink(value: o) {
                            OfferRow(offer: o, reasons: Highlights.reasons(for: o, threshold: threshold, watchTerms: terms))
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                ListActions.addToShopping(o, context: context, sync: sync)
                                addedTick += 1
                            } label: {
                                Label("Na seznam", systemImage: "cart.badge.plus")
                            }
                            .tint(.green)
                        }
                        .contextMenu {
                            Button("Dodaj na nakupovalni seznam", systemImage: "cart.badge.plus") {
                                ListActions.addToShopping(o, context: context, sync: sync)
                                addedTick += 1
                            }
                            if let s = o.sourceUrl, let u = URL(string: s) {
                                Link(destination: u) { Label("Odpri pri trgovcu", systemImage: "safari") }
                            }
                        }
                    }
                    if g.offers.count > 300 {
                        Text("Prikazanih 300 od \(g.offers.count). Zoži iskanje ali filtre.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Label("\(g.title) · \(g.offers.count)", systemImage: g.symbol)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Browse.title(scope, store: store))
        .toolbar { BrowseToolbar() }
        .overlay {
            if store.offers.isEmpty {
                if store.isRefreshing { ProgressView("Nalagam akcije …") }
                else { EmptyStateView(title: "Ni podatkov", symbol: "wifi.slash", message: "Povleci navzdol za osvežitev.") }
            }
        }
        .sensoryFeedback(.success, trigger: addedTick)
    }
}

struct BrowseToolbar: ToolbarContent {
    @Environment(UIState.self) private var ui

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            SortMenu()
            Button {
                ui.showFilters = true
            } label: {
                Label("Filtri", systemImage: ui.filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
        }
    }
}

import SwiftData
import SwiftUI

/// iPad: NavigationSplitView s tremi stolpci.
/// 1) stranska vrstica, 2) mreža izdelkov, 3) podrobnosti izdelka.
struct PadRootView: View {
    @Environment(AppStore.self) private var store
    @Environment(UIState.self) private var ui
    @Environment(SyncService.self) private var sync
    @Environment(\.modelContext) private var context
    @State private var visibility: NavigationSplitViewVisibility = .all
    @State private var dropTick = 0

    var body: some View {
        @Bindable var ui = ui
        NavigationSplitView(columnVisibility: $visibility) {
            sidebar
                .navigationTitle("Akcije SI")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { ui.showSettings = true } label: { Label("Nastavitve", systemImage: "gearshape") }
                    }
                }
                .navigationSplitViewColumnWidth(min: 220, ideal: 270, max: 320)
        } content: {
            NavigationStack {
                content
                    .withAppDestinations()
            }
            .navigationSplitViewColumnWidth(min: 380, ideal: 600, max: 900)
        } detail: {
            NavigationStack {
                if let o = ui.selectedOffer {
                    OfferDetailView(offer: o)
                        .id(o.id)
                        .withAppDestinations()
                } else {
                    EmptyStateView(title: "Izberi izdelek", symbol: "hand.tap",
                                   message: "Podrobnosti, zgodovina cene in primerjava med trgovinami.")
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        // Pokončno (ali ozko okno) so trije stolpci pretesni: stranska vrstica se skrije in je
        // dosegljiva z gumbom v orodni vrstici.
        .onGeometryChange(for: Bool.self) { $0.size.width >= 1180 } action: { wide in
            visibility = wide ? .all : .doubleColumn
        }
        .onChange(of: ui.section) { _, s in ui.sidebar = SidebarItem(section: s) }
        .sensoryFeedback(.success, trigger: dropTick)
    }

    private var sidebar: some View {
        @Bindable var ui = ui
        return List(selection: $ui.sidebar) {
            Label("Izpostavljeno", systemImage: "star").tag(SidebarItem.highlights)
            Label("Vse kategorije", systemImage: "square.grid.2x2").tag(SidebarItem.categories)
            ForEach(store.sections) { sec in
                Section(sec.label) {
                    ForEach(store.categories(in: sec.id)) { c in
                        Label(c.label, systemImage: c.icon)
                            .badge(store.count(category: c.id))
                            .tag(SidebarItem.category(c.id))
                    }
                }
            }
            Section("Trgovine") {
                ForEach(store.meta?.chains ?? []) { ch in
                    Label {
                        Text(ch.name)
                    } icon: {
                        Circle().fill(Color(hex: ch.color)).frame(width: 12, height: 12)
                    }
                    .tag(SidebarItem.chain(ch.id))
                }
            }
            Section("Moje") {
                Label("Kuponi", systemImage: "ticket").tag(SidebarItem.coupons)
                Label("Moj seznam", systemImage: "checklist")
                    .tag(SidebarItem.myList)
                    .dropDestination(for: String.self) { ids, _ in
                        for id in ids {
                            if let o = store.offer(id: id) { ListActions.addToShopping(o, context: context, sync: sync) }
                        }
                        dropTick += 1
                        return true
                    }
                Label("Vodič", systemImage: "book").tag(SidebarItem.guide)
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder private var content: some View {
        switch ui.sidebar ?? .highlights {
        case .highlights:
            OfferGridScreen(scope: .highlights)
        case .categories:
            CategoriesView()
        case .category(let c):
            OfferGridScreen(scope: .category(c))
        case .chain(let ch):
            OfferGridScreen(scope: .chain(ch))
        case .coupons:
            CouponsView()
        case .myList:
            MyListView()
        case .guide:
            GuideView()
        }
    }
}

/// Prilagodljiva mreža (3–5 stolpcev glede na širino; v zelo ozkem oknu 2).
struct OfferGridScreen: View {
    @Environment(AppStore.self) private var store
    @Environment(UIState.self) private var ui
    @Environment(SyncService.self) private var sync
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<WatchItem> { !$0.deleted }) private var watch: [WatchItem]
    @AppStorage("threshold") private var threshold = 30
    @FocusState private var searchFocused: Bool
    let scope: BrowseScope
    @State private var addedTick = 0

    var body: some View {
        @Bindable var ui = ui
        let terms = watch.map { WatchTerm(term: $0.term, category: $0.category) }
        let effective: BrowseScope = ui.search.isEmpty ? scope : (scope == .highlights ? .all : scope)
        let groups = Browse.groups(scope: effective, store: store, ui: ui, watchTerms: terms, threshold: threshold)
        GeometryReader { geo in
            let cols = max(2, min(5, Int((geo.size.width - 32 + 12) / (170 + 12))))
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if case .highlights = scope { StoreSectionPicker().frame(maxWidth: 420) }
                    ForEach(groups) { g in
                        VStack(alignment: .leading, spacing: 10) {
                            Label("\(g.title) · \(g.offers.count)", systemImage: g.symbol)
                                .font(.headline)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: cols), spacing: 12) {
                                ForEach(g.offers.prefix(400)) { o in
                                    OfferCard(offer: o,
                                              reasons: Highlights.reasons(for: o, threshold: threshold, watchTerms: terms),
                                              selected: ui.selectedOffer?.id == o.id)
                                        .onTapGesture { ui.selectedOffer = o }
                                        .hoverEffect(.lift)
                                        .draggable(o.id) {
                                            Label(o.name, systemImage: "cart.badge.plus")
                                                .padding(10)
                                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                                        }
                                        .contextMenu {
                                            Button("Dodaj na nakupovalni seznam", systemImage: "cart.badge.plus") {
                                                ListActions.addToShopping(o, context: context, sync: sync)
                                                addedTick += 1
                                            }
                                        }
                                        .accessibilityAddTraits(.isButton)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle(Browse.title(scope, store: store))
        .searchable(text: $ui.search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Išči (⌘F)")
        .searchFocused($searchFocused)
        .onChange(of: ui.focusSearch) { _, _ in searchFocused = true }
        .toolbar {
            BrowseToolbar()
            ToolbarItem(placement: .topBarTrailing) {
                Button { ui.refreshRequest += 1 } label: { Label("Osveži", systemImage: "arrow.clockwise") }
                    .disabled(store.isRefreshing)
            }
        }
        .refreshable { ui.refreshRequest += 1 }
        .overlay {
            if store.offers.isEmpty {
                if store.isRefreshing { ProgressView("Nalagam akcije …") }
                else { EmptyStateView(title: "Ni podatkov", symbol: "wifi.slash", message: "Pritisni ⌘R za osvežitev.") }
            }
        }
        .sensoryFeedback(.success, trigger: addedTick)
        // Podatki se naložijo po prvem prikazu, zato ob spremembi in ne v onAppear.
        .onChange(of: groups.first(where: { !$0.offers.isEmpty })?.offers.first?.id, initial: true) { _, first in
            if ProcessInfo.processInfo.arguments.contains("-selectFirst"), ui.selectedOffer == nil, let first {
                ui.selectedOffer = store.offer(id: first)
            }
        }
    }
}

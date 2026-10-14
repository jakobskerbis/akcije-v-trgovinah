import SwiftData
import SwiftUI

/// Nakupovalni seznam in opazovana živila (skupna z drugimi napravami).
struct MyListView: View {
    @Environment(AppStore.self) private var store
    @Environment(SyncService.self) private var sync
    @Environment(UIState.self) private var ui
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<ShoppingItem> { !$0.deleted }, sort: \ShoppingItem.createdAt) private var items: [ShoppingItem]
    @Query(filter: #Predicate<WatchItem> { !$0.deleted }, sort: \WatchItem.createdAt) private var watch: [WatchItem]
    @State private var newItem = ""
    @State private var newWatch = ""
    @State private var tick = 0
    @FocusState private var focus: Field?

    enum Field { case item, watch }

    var body: some View {
        List {
            syncStatus
            Section {
                HStack {
                    TextField("Dodaj na seznam …", text: $newItem)
                        .focused($focus, equals: .item)
                        .submitLabel(.done)
                        .onSubmit(addItem)
                    Button(action: addItem) { Image(systemName: "plus.circle.fill") }
                        .disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityLabel("Dodaj")
                }
                ForEach(groupedItems) { group in
                    if let chain = group.chain {
                        Text(store.chainName(chain)).font(.caption.weight(.semibold)).foregroundStyle(store.color(for: chain))
                    }
                    ForEach(group.items) { item in ShoppingRow(item: item) { toggle(item) } }
                        .onDelete { idx in for i in idx { ListActions.delete(group.items[i], context: context, sync: sync) } }
                }
                if items.contains(where: \.checked) {
                    Button("Odstrani kupljeno", role: .destructive) {
                        ListActions.clearChecked(items, context: context, sync: sync)
                    }
                }
            } header: {
                Text("Nakupovalni seznam · \(items.filter { !$0.checked }.count)")
            } footer: {
                if let total = estimatedTotal { Text("Ocena po akcijskih cenah: \(Format.price(total))") }
            }
            .dropDestination(for: String.self) { ids, _ in
                for id in ids { if let o = store.offer(id: id) { ListActions.addToShopping(o, context: context, sync: sync) } }
                tick += 1
                return true
            }

            Section {
                HStack {
                    TextField("Opazuj živilo, npr. »piščančje prsi«", text: $newWatch)
                        .focused($focus, equals: .watch)
                        .submitLabel(.done)
                        .onSubmit(addWatch)
                    Button(action: addWatch) { Image(systemName: "eye.circle.fill") }
                        .disabled(newWatch.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityLabel("Dodaj opazovano živilo")
                }
                ForEach(watch) { w in
                    let hits = store.offers.filter { !$0.isExpired() && Matching.matches(term: w.term, name: $0.name) }
                    NavigationLink(value: WatchScope(term: w.term)) {
                        HStack {
                            Text(w.term)
                            Spacer()
                            Text(hits.isEmpty ? "ni akcij" : "\(hits.count) akcij").foregroundStyle(hits.isEmpty ? Color.secondary : Color.accentColor)
                            if let by = w.by { Text(by).font(.caption2).foregroundStyle(.tertiary) }
                        }
                    }
                }
                .onDelete { idx in for i in idx { ListActions.delete(watch[i], context: context, sync: sync) } }
            } header: {
                Text("Opazovana živila")
            } footer: {
                Text("Ko se opazovano živilo pojavi v akciji, dobiš obvestilo. Besede se ujemajo tudi v drugih sklonih.")
            }
        }
        .navigationTitle("Moj seznam")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { ui.showSettings = true } label: { Label("Skupna raba", systemImage: "person.2.badge.gearshape") }
            }
        }
        .refreshable { await sync.sync(context: context) }
        .sensoryFeedback(.success, trigger: tick)
    }

    @ViewBuilder private var syncStatus: some View {
        if !sync.isConfigured {
            Section {
                Button { ui.showSettings = true } label: {
                    Label("Poveži skupni seznam s partnerjem", systemImage: "person.2")
                }
            } footer: {
                Text("Seznam je zdaj samo na tej napravi. V nastavitvah vnesi GitHub žeton za skupni repozitorij.")
            }
        } else if let err = sync.lastError {
            Section { Label(err, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.footnote) }
        }
    }

    struct ItemGroup: Identifiable {
        let chain: String?
        let items: [ShoppingItem]
        var id: String { chain ?? "~" }
    }

    private var groupedItems: [ItemGroup] {
        let open = items.sorted { a, b in a.checked == b.checked ? a.createdAt < b.createdAt : !a.checked }
        let groups = Dictionary(grouping: open, by: \.chain)
        return groups.keys.sorted { ($0 ?? "~") < ($1 ?? "~") }.map { ItemGroup(chain: $0, items: groups[$0] ?? []) }
    }

    private var estimatedTotal: Double? {
        let prices = items.filter { !$0.checked }.compactMap { i in i.price.map { $0 * Double(i.quantity) } }
        return prices.isEmpty ? nil : prices.reduce(0, +)
    }

    private func addItem() {
        ListActions.addShopping(title: newItem, context: context, sync: sync)
        newItem = ""
        tick += 1
    }

    private func addWatch() {
        ListActions.addWatch(term: newWatch, context: context, sync: sync)
        newWatch = ""
        tick += 1
    }

    private func toggle(_ item: ShoppingItem) {
        ListActions.toggle(item, context: context, sync: sync)
        tick += 1
    }
}

struct WatchScope: Hashable { let term: String }

struct ShoppingRow: View {
    @Environment(AppStore.self) private var store
    let item: ShoppingItem
    var onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack {
                Image(systemName: item.checked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.checked ? Color.green : Color.secondary)
                    .font(.title3)
                VStack(alignment: .leading) {
                    Text(item.title).strikethrough(item.checked).foregroundStyle(item.checked ? .secondary : .primary)
                    if let o = item.offerId.flatMap(store.offer(id:)), let d = Format.daysLeft(o) {
                        Text(d).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let p = item.price { Text(Format.price(p)).monospacedDigit().foregroundStyle(.secondary) }
                if let by = item.by { Text(by).font(.caption2).foregroundStyle(.tertiary) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.title), \(item.checked ? "kupljeno" : "ni kupljeno")")
    }
}

/// Zadetki za eno opazovano živilo.
struct WatchResultsView: View {
    @Environment(AppStore.self) private var store
    let scope: WatchScope

    var body: some View {
        let hits = Highlights.sort(store.offers.filter { !$0.isExpired() && Matching.matches(term: scope.term, name: $0.name) }, by: .unitPrice)
        List(hits) { o in
            NavigationLink(value: o) { OfferRow(offer: o, reasons: [.watch]) }
        }
        .overlay { if hits.isEmpty { EmptyStateView(title: "Ni akcij", symbol: "eye.slash", message: "»\(scope.term)« ta teden ni v akciji.") } }
        .navigationTitle(scope.term)
    }
}

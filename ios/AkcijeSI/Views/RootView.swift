import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(SyncService.self) private var sync
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var hsc
    @Environment(\.scenePhase) private var scenePhase
    @State private var ui = UIState()
    @AppStorage("didAskNotifications") private var didAskNotifications = false

    var body: some View {
        @Bindable var ui = ui
        Group {
            if hsc == .regular && UIDevice.current.userInterfaceIdiom == .pad {
                PadRootView()
            } else {
                PhoneRootView()
            }
        }
        .environment(ui)
        .focusedSceneValue(\.uiState, ui)
        .sheet(isPresented: $ui.showFilters) { FilterSheet().environment(ui) }
        .sheet(isPresented: $ui.showSettings) { SettingsView() }
        .task { await start() }
        .task(id: ui.refreshRequest) {
            if ui.refreshRequest > 0 { await refresh() }
        }
        .task { await pollSync() }
    }

    private func start() async {
        store.loadCached(context: context)
        if store.demoMode { seedDemo(); return }
        if !didAskNotifications && !store.demoMode {
            didAskNotifications = true
            await Notifier.requestPermission()
        }
        BackgroundRefresh.schedule()
        let stale = store.lastFetched.map { Date.now.timeIntervalSince($0) > 3600 } ?? true
        if stale || store.offers.isEmpty { await refresh() }
        await sync.sync(context: context)
    }

    private func refresh() async {
        await store.refresh(context: context)
        await sync.sync(context: context)
        await Notifier.notifyNew(store: store, context: context)
    }

    /// Demo način (posnetki zaslona): nekaj opazovanih živil in postavk na seznamu.
    private func seedDemo() {
        let existing = (try? context.fetch(FetchDescriptor<WatchItem>())) ?? []
        guard existing.isEmpty else { return }
        for (term, by) in [("piščančje prsi", "Jakob"), ("mleko", "Partnerka"), ("losos", "Partnerka"), ("kava", "Jakob"), ("mandarine", "Jakob")] {
            context.insert(WatchItem(term: term, category: Matching.inferCategory(term: term, offers: store.offers), by: by))
        }
        let picks = store.offers.filter { ($0.discountPct ?? 0) >= 30 && store.category($0.category)?.food == true }.prefix(4)
        for (i, o) in picks.enumerated() {
            let item = ShoppingItem(title: o.name, offer: o, by: i % 2 == 0 ? "Jakob" : "Partnerka")
            item.checked = i == 3
            context.insert(item)
        }
        context.insert(ShoppingItem(title: "Kruh", by: "Partnerka"))
        try? context.save()
    }

    /// Ko je aplikacija odprta, preverja spremembe partnerja vsakih 20 s.
    private func pollSync() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(20))
            if scenePhase == .active && sync.isConfigured { await sync.sync(context: context) }
        }
    }
}

// MARK: - Bližnjice (⌘1–5, ⌘F, ⌘R)

struct UIStateKey: FocusedValueKey { typealias Value = UIState }

extension FocusedValues {
    var uiState: UIState? {
        get { self[UIStateKey.self] }
        set { self[UIStateKey.self] = newValue }
    }
}

struct AppCommands: Commands {
    @FocusedValue(\.uiState) private var ui

    var body: some Commands {
        CommandMenu("Akcije") {
            ForEach(AppSection.allCases) { s in
                Button(s.title) { ui?.section = s }
                    .keyboardShortcut(s.shortcut, modifiers: .command)
            }
            Divider()
            Button("Iskanje") {
                ui?.focusSearch += 1
            }
            .keyboardShortcut("f", modifiers: .command)
            Button("Osveži") {
                ui?.refreshRequest += 1
            }
            .keyboardShortcut("r", modifiers: .command)
            Button("Filtri") { ui?.showFilters = true }
                .keyboardShortcut("l", modifiers: [.command, .shift])
        }
    }
}

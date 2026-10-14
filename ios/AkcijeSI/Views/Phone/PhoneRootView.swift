import SwiftData
import SwiftUI

/// iPhone (in ozko okno na iPadu): TabView s petimi zavihki.
struct PhoneRootView: View {
    @Environment(AppStore.self) private var store
    @Environment(UIState.self) private var ui

    var body: some View {
        @Bindable var ui = ui
        TabView(selection: $ui.section) {
            NavigationStack {
                HighlightsRoot()
                    .withAppDestinations()
            }
            .tabItem { Label(AppSection.highlights.title, systemImage: AppSection.highlights.symbol) }
            .tag(AppSection.highlights)

            NavigationStack {
                CategoriesView()
                    .toolbar { SettingsButton() }
                    .withAppDestinations()
            }
            .tabItem { Label(AppSection.categories.title, systemImage: AppSection.categories.symbol) }
            .tag(AppSection.categories)

            NavigationStack {
                CouponsView().withAppDestinations()
            }
            .tabItem { Label(AppSection.coupons.title, systemImage: AppSection.coupons.symbol) }
            .tag(AppSection.coupons)

            NavigationStack {
                MyListView().withAppDestinations()
            }
            .tabItem { Label(AppSection.myList.title, systemImage: AppSection.myList.symbol) }
            .tag(AppSection.myList)

            NavigationStack {
                GuideView().withAppDestinations()
            }
            .tabItem { Label(AppSection.guide.title, systemImage: AppSection.guide.symbol) }
            .tag(AppSection.guide)
        }
    }
}

/// Izpostavljeno; ko uporabnik išče, prikaže vse zadetke.
struct HighlightsRoot: View {
    @Environment(AppStore.self) private var store
    @Environment(UIState.self) private var ui
    @Environment(SyncService.self) private var sync
    @Environment(\.modelContext) private var context
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var ui = ui
        OfferListScreen(scope: ui.search.isEmpty ? .highlights : .all)
            .searchable(text: $ui.search, prompt: "Išči izdelek ali trgovino")
            .searchFocused($searchFocused)
            .refreshable {
                await store.refresh(context: context)
                await Notifier.notifyNew(store: store, context: context)
            }
            .toolbar { SettingsButton() }
            .onChange(of: ui.focusSearch) { _, _ in searchFocused = true }
    }
}

struct SettingsButton: ToolbarContent {
    @Environment(UIState.self) private var ui

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { ui.showSettings = true } label: { Label("Nastavitve", systemImage: "gearshape") }
        }
    }
}

extension View {
    /// Skupni cilji navigacije za vse sklade.
    func withAppDestinations() -> some View {
        navigationDestination(for: Offer.self) { OfferDetailView(offer: $0) }
            .navigationDestination(for: BrowseScope.self) { OfferListScreen(scope: $0) }
            .navigationDestination(for: WatchScope.self) { WatchResultsView(scope: $0) }
            .navigationDestination(for: GuideApp.self) { GuideAppDetail(app: $0) }
            .navigationDestination(for: LoyaltyProgram.self) { LoyaltyDetail(program: $0) }
    }
}

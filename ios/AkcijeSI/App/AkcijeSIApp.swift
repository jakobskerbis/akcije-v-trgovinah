import BackgroundTasks
import SwiftData
import SwiftUI

@main
struct AkcijeSIApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = AppServices.shared.store
    @State private var sync = AppServices.shared.sync

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(sync)
                .modelContainer(AppServices.shared.container)
                .onOpenURL { url in
                    if url.scheme == "akcijesi", url.host == "sync" { _ = sync.apply(configURL: url) }
                }
        }
        .commands { AppCommands() }
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await BackgroundRefresh.run()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { BackgroundRefresh.schedule() }
        }
    }
}

/// Skupni objekti, dostopni tudi iz osveževanja v ozadju.
@MainActor
final class AppServices {
    static let shared = AppServices()

    let container: ModelContainer
    let store: AppStore
    let sync: SyncService

    private init() {
        let schema = Schema([CachedFeed.self, WatchItem.self, ShoppingItem.self])
        let inMemory = ProcessInfo.processInfo.arguments.contains("-demo")
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            // poškodovana baza: začnemo znova (vsi podatki so tudi na strežniku)
            container = try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        }
        store = AppStore()
        sync = SyncService()
    }
}

enum BackgroundRefresh {
    static let identifier = "com.jakobskerbis.akcijesi.refresh"

    static func schedule() {
        let req = BGAppRefreshTaskRequest(identifier: identifier)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 3 * 3600)
        try? BGTaskScheduler.shared.submit(req)
    }

    @MainActor
    static func run() async {
        schedule()
        let services = AppServices.shared
        let context = services.container.mainContext
        if services.store.offers.isEmpty { services.store.loadCached(context: context) }
        await services.store.refresh(context: context)
        await services.sync.sync(context: context)
        await Notifier.notifyNew(store: services.store, context: context)
    }
}

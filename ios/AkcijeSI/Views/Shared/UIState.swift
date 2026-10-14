import SwiftData
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case highlights, categories, coupons, myList, guide
    var id: String { rawValue }

    var title: String {
        switch self {
        case .highlights: return "Izpostavljeno"
        case .categories: return "Kategorije"
        case .coupons: return "Kuponi"
        case .myList: return "Moj seznam"
        case .guide: return "Vodič"
        }
    }

    var symbol: String {
        switch self {
        case .highlights: return "star"
        case .categories: return "square.grid.2x2"
        case .coupons: return "ticket"
        case .myList: return "checklist"
        case .guide: return "book"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .highlights: return "1"
        case .categories: return "2"
        case .coupons: return "3"
        case .myList: return "4"
        case .guide: return "5"
        }
    }
}

/// Stanje navigacije in filtrov, skupno iPhone in iPad postavitvi.
@MainActor
@Observable
final class UIState {
    var section: AppSection = .highlights
    var storeSection: String = UserDefaults.standard.string(forKey: "storeSection") ?? "zivila"
    var filter = OfferFilter()
    var sort: SortOrder = .discount
    var search = ""
    var selectedOffer: Offer?
    var selectedCategory: String?
    var selectedChain: String?
    var showFilters = false
    var showSettings = false
    var hapticAdd = 0
    var focusSearch = 0
    var refreshRequest = 0
    var sidebar: SidebarItem? = .highlights

    init() {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-storeSection"), args.count > i + 1 {
            storeSection = args[i + 1]
        }
        filter.section = storeSection
        if let s = ProcessInfo.processInfo.arguments.firstIndex(of: "-section"),
           ProcessInfo.processInfo.arguments.count > s + 1,
           let sec = AppSection(rawValue: ProcessInfo.processInfo.arguments[s + 1]) {
            section = sec
            sidebar = SidebarItem(section: sec)
        }
    }

    func setStoreSection(_ s: String) {
        storeSection = s
        filter.section = s
        filter.categories = []
        UserDefaults.standard.set(s, forKey: "storeSection")
    }
}

/// Izbira v stranski vrstici iPada.
enum SidebarItem: Hashable {
    case highlights
    case categories
    case category(String)
    case chain(String)
    case coupons
    case myList
    case guide

    init(section: AppSection) {
        switch section {
        case .highlights: self = .highlights
        case .categories: self = .categories
        case .coupons: self = .coupons
        case .myList: self = .myList
        case .guide: self = .guide
        }
    }
}

/// Dejanja nad seznami (SwiftData + sinhronizacija).
@MainActor
enum ListActions {
    static func addToShopping(_ offer: Offer, context: ModelContext, sync: SyncService) {
        let item = ShoppingItem(title: offer.name, offer: offer, by: sync.displayName.isEmpty ? nil : sync.displayName)
        context.insert(item)
        try? context.save()
        Task { await sync.sync(context: context) }
    }

    static func addShopping(title: String, context: ModelContext, sync: SyncService) {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        context.insert(ShoppingItem(title: t, by: sync.displayName.isEmpty ? nil : sync.displayName))
        try? context.save()
        Task { await sync.sync(context: context) }
    }

    static func addWatch(term: String, category: String? = nil, context: ModelContext, sync: SyncService) {
        let t = term.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        context.insert(WatchItem(term: t, category: category, by: sync.displayName.isEmpty ? nil : sync.displayName))
        try? context.save()
        Task { await sync.sync(context: context) }
    }

    static func toggle(_ item: ShoppingItem, context: ModelContext, sync: SyncService) {
        item.checked.toggle()
        item.updatedAt = .now
        try? context.save()
        Task { await sync.sync(context: context) }
    }

    static func delete(_ item: ShoppingItem, context: ModelContext, sync: SyncService) {
        item.deleted = true
        item.updatedAt = .now
        try? context.save()
        Task { await sync.sync(context: context) }
    }

    static func delete(_ item: WatchItem, context: ModelContext, sync: SyncService) {
        item.deleted = true
        item.updatedAt = .now
        try? context.save()
        Task { await sync.sync(context: context) }
    }

    static func clearChecked(_ items: [ShoppingItem], context: ModelContext, sync: SyncService) {
        for i in items where i.checked && !i.deleted {
            i.deleted = true
            i.updatedAt = .now
        }
        try? context.save()
        Task { await sync.sync(context: context) }
    }
}

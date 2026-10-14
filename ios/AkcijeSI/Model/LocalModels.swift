import Foundation
import SwiftData

/// Predpomnilnik prenesenih JSON datotek (offers, coupons, meta, guide, history).
@Model
final class CachedFeed {
    @Attribute(.unique) var name: String
    @Attribute(.externalStorage) var data: Data
    var fetchedAt: Date
    var etag: String?

    init(name: String, data: Data, fetchedAt: Date = .now, etag: String? = nil) {
        self.name = name
        self.data = data
        self.fetchedAt = fetchedAt
        self.etag = etag
    }
}

/// Opazovano živilo (npr. "piščančje prsi"). Deli se prek skupnega repozitorija.
@Model
final class WatchItem {
    @Attribute(.unique) var uid: String
    var term: String
    var category: String?
    var createdAt: Date
    var updatedAt: Date
    var deleted: Bool
    var by: String?

    init(term: String, category: String? = nil, by: String? = nil) {
        uid = UUID().uuidString
        self.term = term
        self.category = category
        createdAt = .now
        updatedAt = .now
        deleted = false
        self.by = by
    }
}

/// Postavka nakupovalnega seznama.
@Model
final class ShoppingItem {
    @Attribute(.unique) var uid: String
    var title: String
    var offerId: String?
    var productKey: String?
    var chain: String?
    var price: Double?
    var quantity: Int
    var checked: Bool
    var note: String?
    var createdAt: Date
    var updatedAt: Date
    var deleted: Bool
    var by: String?

    init(title: String, offer: Offer? = nil, by: String? = nil) {
        uid = UUID().uuidString
        self.title = title
        offerId = offer?.id
        productKey = offer?.productKey
        chain = offer?.chain
        price = offer?.price
        quantity = 1
        checked = false
        createdAt = .now
        updatedAt = .now
        deleted = false
        self.by = by
    }
}

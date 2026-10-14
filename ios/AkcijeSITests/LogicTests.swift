import XCTest
@testable import AkcijeSI

final class LogicTests: XCTestCase {
    func testMatchingHandlesSlovenianCases() {
        XCTAssertTrue(Matching.matches(term: "piščančje prsi", name: "Piščančja prsa Izbrana kakovost"))
        XCTAssertTrue(Matching.matches(term: "piscancje prsi", name: "NAŠE NAM PAŠE Piščančje prsi brez kože"))
        XCTAssertTrue(Matching.matches(term: "losos", name: "File lososa"))
        XCTAssertTrue(Matching.matches(term: "mleko", name: "Pomursko mleko 3,5% m.m."))
        XCTAssertFalse(Matching.matches(term: "piščančje prsi", name: "Piščančja bedra"))
        XCTAssertFalse(Matching.matches(term: "", name: "karkoli"))
    }

    func testMergePrefersNewer() {
        let old = SharedWatch(id: "a", term: "staro", category: nil, createdAt: "2026-10-01T10:00:00.000Z",
                              updatedAt: "2026-10-01T10:00:00.000Z", deleted: false, by: nil)
        var new = old
        new.term = "novo"
        new.updatedAt = "2026-10-02T10:00:00.123456Z"  // Dart zapis z mikrosekundami
        let merged = SharedMerge.merge([old], [new], id: \.id, updated: \.updatedAt)
        XCTAssertEqual(merged.first?.term, "novo")
        let merged2 = SharedMerge.merge([new], [old], id: \.id, updated: \.updatedAt)
        XCTAssertEqual(merged2.first?.term, "novo")
    }

    func testPurgeRemovesOldTombstones() {
        var doc = SharedDoc()
        doc.watch = [
            SharedWatch(id: "x", term: "x", category: nil, createdAt: "2026-01-01T00:00:00.000Z",
                        updatedAt: "2026-01-01T00:00:00.000Z", deleted: true, by: nil),
            SharedWatch(id: "y", term: "y", category: nil, createdAt: "2026-01-01T00:00:00.000Z",
                        updatedAt: SharedTime.now(), deleted: true, by: nil),
        ]
        SharedMerge.purge(&doc)
        XCTAssertEqual(doc.watch.map(\.id), ["y"])
    }

    func testDecodeOfferAndDaysLeft() throws {
        let json = """
        {"offers":[{"id":"1","chain":"lidl","name":"Kivi zlati","price":0.49,"regularPrice":0.69,"discountPct":28,
        "unitPrice":0.49,"unit":"kos","bestUnitPrice":false,"validFrom":"2026-10-15","validTo":"2026-10-25",
        "condition":{"type":"app","description":"Lidl Plus"},"sourceUrl":"u","imageUrl":null,"fetchedAt":"x"}]}
        """
        let f = try JSONDecoder().decode(OffersFile.self, from: Data(json.utf8))
        let o = try XCTUnwrap(f.offers.first)
        XCTAssertEqual(o.condition.type, .app)
        let now = try XCTUnwrap(DateParsing.day("2026-10-20"))
        XCTAssertEqual(o.daysLeft(now: now), 5)
        XCTAssertTrue(o.isStarted(now: now))
    }

    func testUnknownConditionFallsBackToNone() throws {
        let c = try JSONDecoder().decode(OfferCondition.self, from: Data(#"{"type":"nekaj","description":null}"#.utf8))
        XCTAssertEqual(c.type, .none)
    }
}

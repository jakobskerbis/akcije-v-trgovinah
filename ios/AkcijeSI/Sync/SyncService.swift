import Foundation
import Observation
import SwiftData

/// Skupna raba seznamov prek zasebnega GitHub repozitorija (namesto CloudKita,
/// ki zahteva plačljiv Apple Developer račun). Datoteka shared.json se bere in
/// piše prek GitHub Contents API; spori se razrešijo z združevanjem po id.
@MainActor
@Observable
final class SyncService {
    static let path = "shared.json"

    var owner: String
    var repo: String
    var displayName: String
    var token: String

    var isSyncing = false
    var lastSync: Date?
    var lastError: String?
    private var pending = false

    var isConfigured: Bool { !owner.isEmpty && !repo.isEmpty && !token.isEmpty }

    init() {
        let d = UserDefaults.standard
        owner = d.string(forKey: "syncOwner") ?? "jakobskerbis"
        repo = d.string(forKey: "syncRepo") ?? "akcije-skupno"
        displayName = d.string(forKey: "displayName") ?? ""
        token = Keychain.get("githubToken") ?? ""
    }

    func saveSettings() {
        let d = UserDefaults.standard
        d.set(owner.trimmingCharacters(in: .whitespaces), forKey: "syncOwner")
        d.set(repo.trimmingCharacters(in: .whitespaces), forKey: "syncRepo")
        d.set(displayName, forKey: "displayName")
        Keychain.set(token.trimmingCharacters(in: .whitespacesAndNewlines), for: "githubToken")
    }

    /// Nastavitve iz povezave/QR kode: akcijesi://sync?owner=..&repo=..&token=..
    func apply(configURL url: URL) -> Bool {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = comps.queryItems else { return false }
        func v(_ k: String) -> String? { items.first { $0.name == k }?.value }
        guard let t = v("token"), let o = v("owner"), let r = v("repo") else { return false }
        owner = o; repo = r; token = t
        saveSettings()
        return true
    }

    var configURL: URL? {
        guard isConfigured else { return nil }
        var c = URLComponents()
        c.scheme = "akcijesi"
        c.host = "sync"
        c.queryItems = [.init(name: "owner", value: owner), .init(name: "repo", value: repo), .init(name: "token", value: token)]
        return c.url
    }

    // MARK: Sinhronizacija

    func sync(context: ModelContext) async {
        guard isConfigured else { return }
        if isSyncing { pending = true; return }
        isSyncing = true
        defer { isSyncing = false }
        repeat {
            pending = false
            do {
                try await syncOnce(context: context)
                lastSync = .now
                lastError = nil
            } catch {
                lastError = (error as? SyncError)?.message ?? error.localizedDescription
            }
        } while pending
    }

    private func syncOnce(context: ModelContext) async throws {
        for _ in 0..<3 {
            let (remote, sha) = try await fetchRemote()
            let local = localDoc(context: context)
            var merged = SharedDoc(
                watch: SharedMerge.merge(remote.watch, local.watch, id: \.id, updated: \.updatedAt),
                shopping: SharedMerge.merge(remote.shopping, local.shopping, id: \.id, updated: \.updatedAt)
            )
            SharedMerge.purge(&merged)
            applyToLocal(merged, context: context)
            var remoteSorted = remote
            SharedMerge.purge(&remoteSorted)
            if merged.watch == remoteSorted.watch && merged.shopping == remoteSorted.shopping && sha != nil {
                return
            }
            merged.updatedAt = SharedTime.now()
            if try await putRemote(merged, sha: sha) { return }
            // spor (nekdo je medtem zapisal) – ponovi z novim stanjem
        }
        throw SyncError(message: "Sinhronizacija ni uspela zaradi sočasnih sprememb. Poskusi znova.")
    }

    private var contentsURL: URL {
        URL(string: "https://api.github.com/repos/\(owner)/\(repo)/contents/\(Self.path)")!
    }

    private func request(_ method: String, body: Data? = nil) -> URLRequest {
        var r = URLRequest(url: contentsURL)
        r.httpMethod = method
        r.cachePolicy = .reloadIgnoringLocalCacheData
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        r.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        r.setValue("AkcijeSI-iOS", forHTTPHeaderField: "User-Agent")
        if let body {
            r.httpBody = body
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return r
    }

    private struct ContentsResponse: Decodable {
        var sha: String
        var content: String?
    }

    private func fetchRemote() async throws -> (SharedDoc, String?) {
        let (data, resp) = try await URLSession.shared.data(for: request("GET"))
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 { return (SharedDoc(), nil) }
        guard code == 200 else { throw SyncError.http(code) }
        let c = try JSONDecoder().decode(ContentsResponse.self, from: data)
        let raw = (c.content ?? "").replacingOccurrences(of: "\n", with: "")
        guard let decoded = Data(base64Encoded: raw), !decoded.isEmpty else { return (SharedDoc(), c.sha) }
        let doc = (try? JSONDecoder().decode(SharedDoc.self, from: decoded)) ?? SharedDoc()
        return (doc, c.sha)
    }

    /// true = uspeh, false = spor (409/422)
    private func putRemote(_ doc: SharedDoc, sha: String?) async throws -> Bool {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let json = try enc.encode(doc)
        var body: [String: Any] = [
            "message": "Posodobitev seznamov (\(displayName.isEmpty ? "iPad/iPhone" : displayName))",
            "content": json.base64EncodedString(),
        ]
        if let sha { body["sha"] = sha }
        let data = try JSONSerialization.data(withJSONObject: body)
        let (_, resp) = try await URLSession.shared.data(for: request("PUT", body: data))
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 200 || code == 201 { return true }
        if code == 409 || code == 422 { return false }
        throw SyncError.http(code)
    }

    // MARK: Lokalni podatki <-> dokument

    private func localDoc(context: ModelContext) -> SharedDoc {
        let w = (try? context.fetch(FetchDescriptor<WatchItem>())) ?? []
        let s = (try? context.fetch(FetchDescriptor<ShoppingItem>())) ?? []
        return SharedDoc(
            watch: w.map { SharedWatch(id: $0.uid, term: $0.term, category: $0.category,
                                       createdAt: SharedTime.string($0.createdAt), updatedAt: SharedTime.string($0.updatedAt),
                                       deleted: $0.deleted, by: $0.by) },
            shopping: s.map { SharedShopping(id: $0.uid, title: $0.title, offerId: $0.offerId, productKey: $0.productKey,
                                             chain: $0.chain, price: $0.price, quantity: $0.quantity, checked: $0.checked,
                                             note: $0.note, createdAt: SharedTime.string($0.createdAt),
                                             updatedAt: SharedTime.string($0.updatedAt), deleted: $0.deleted, by: $0.by) }
        )
    }

    private func applyToLocal(_ doc: SharedDoc, context: ModelContext) {
        let w = (try? context.fetch(FetchDescriptor<WatchItem>())) ?? []
        var wById = Dictionary(w.map { ($0.uid, $0) }, uniquingKeysWith: { a, _ in a })
        for r in doc.watch {
            let item = wById[r.id] ?? {
                let n = WatchItem(term: r.term)
                n.uid = r.id
                context.insert(n)
                return n
            }()
            wById[r.id] = item
            item.term = r.term
            item.category = r.category
            item.createdAt = SharedTime.date(r.createdAt)
            item.updatedAt = SharedTime.date(r.updatedAt)
            item.deleted = r.deleted
            item.by = r.by
        }
        let ids = Set(doc.watch.map(\.id))
        for item in w where !ids.contains(item.uid) { context.delete(item) }

        let s = (try? context.fetch(FetchDescriptor<ShoppingItem>())) ?? []
        var sById = Dictionary(s.map { ($0.uid, $0) }, uniquingKeysWith: { a, _ in a })
        for r in doc.shopping {
            let item = sById[r.id] ?? {
                let n = ShoppingItem(title: r.title)
                n.uid = r.id
                context.insert(n)
                return n
            }()
            sById[r.id] = item
            item.title = r.title
            item.offerId = r.offerId
            item.productKey = r.productKey
            item.chain = r.chain
            item.price = r.price
            item.quantity = r.quantity
            item.checked = r.checked
            item.note = r.note
            item.createdAt = SharedTime.date(r.createdAt)
            item.updatedAt = SharedTime.date(r.updatedAt)
            item.deleted = r.deleted
            item.by = r.by
        }
        let sids = Set(doc.shopping.map(\.id))
        for item in s where !sids.contains(item.uid) { context.delete(item) }
        try? context.save()
    }
}

struct SyncError: Error {
    var message: String

    static func http(_ code: Int) -> SyncError {
        switch code {
        case 401: return SyncError(message: "Žeton ni veljaven (401). Preveri ga v nastavitvah.")
        case 403: return SyncError(message: "Dostop zavrnjen (403). Žeton potrebuje pravico Contents: Read and write.")
        case 404: return SyncError(message: "Repozitorij ne obstaja ali žeton nima dostopa (404).")
        default: return SyncError(message: "GitHub je vrnil napako \(code).")
        }
    }
}

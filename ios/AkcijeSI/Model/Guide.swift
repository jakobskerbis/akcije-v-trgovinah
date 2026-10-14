import Foundation

/// guide.json – vodič po aplikacijah trgovcev in programih zvestobe.
/// Posodablja se na strežniku, brez nove različice aplikacije.
struct Guide: Codable {
    var version: Int
    var updatedAt: String
    var title: String
    var intro: String
    var apps: [GuideApp]
    var loyaltyPrograms: [LoyaltyProgram]
    var coupleTips: [GuideStatement]
    var disclaimer: String
}

struct GuideSource: Codable, Hashable {
    var title: String
    var url: String
    var date: String?
    var accessed: String
}

struct GuideStatement: Codable, Hashable, Identifiable {
    var text: String
    var advice: Bool?
    var sources: [GuideSource]
    var id: String { text }
}

struct GuideAnswer: Codable, Hashable {
    var answer: String  // da | ne | delno | neznano
    var text: String
    var sources: [GuideSource]

    var label: String {
        switch answer {
        case "da": return "Da"
        case "ne": return "Ne"
        case "delno": return "Delno"
        default: return "Ni podatka"
        }
    }
}

struct GuideLinks: Codable, Hashable {
    var ios: String?
    var android: String?
    var web: String?
}

struct GuideApp: Codable, Hashable, Identifiable {
    var id: String
    var chain: String
    var appName: String?
    var program: String?
    var installPriority: Int
    var recommendation: String
    var summary: String
    var benefits: [GuideStatement]
    var personalCoupons: GuideAnswer
    var activationNeeded: GuideAnswer
    var cardLinking: [GuideStatement]
    var forCouple: [GuideStatement]
    var storesInRegion: GuideAnswer
    var links: GuideLinks

    var title: String { appName ?? program ?? id }
}

struct LoyaltyProgram: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var chain: String
    var rank: Int
    var worthIt: String  // da | morda | ne
    var why: String
    var cost: GuideStatement
    var keyFacts: [GuideStatement]

    var worthLabel: String {
        switch worthIt {
        case "da": return "Splača se"
        case "morda": return "Morda"
        default: return "Ne splača se"
        }
    }
}

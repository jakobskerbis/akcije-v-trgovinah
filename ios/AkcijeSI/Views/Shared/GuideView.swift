import SwiftUI

struct GuideView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Group {
            if let g = store.guide, !g.apps.isEmpty || !g.loyaltyPrograms.isEmpty {
                List {
                    Section { Text(g.intro) }
                    if !g.loyaltyPrograms.isEmpty {
                        Section("Programi zvestobe – ali se splača včlaniti?") {
                            ForEach(g.loyaltyPrograms.sorted { $0.rank < $1.rank }) { p in
                                NavigationLink(value: p) { LoyaltyRow(program: p) }
                            }
                        }
                    }
                    Section("Aplikacije trgovcev (vrstni red namestitve)") {
                        ForEach(g.apps.sorted { $0.installPriority < $1.installPriority }) { app in
                            NavigationLink(value: app) { GuideAppRow(app: app) }
                        }
                    }
                    if !g.coupleTips.isEmpty {
                        Section("Nasveti za par") {
                            ForEach(g.coupleTips) { StatementView(statement: $0) }
                        }
                    }
                    Section {
                        Text(g.disclaimer).font(.footnote).foregroundStyle(.secondary)
                        Text("Posodobljeno: \(g.updatedAt)").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            } else {
                EmptyStateView(title: "Vodič se nalaga", symbol: "book", message: "Vodič se prenese skupaj z akcijami.")
            }
        }
        .navigationTitle("Vodič")
    }
}

struct LoyaltyRow: View {
    @Environment(AppStore.self) private var store
    let program: LoyaltyProgram

    var body: some View {
        HStack(alignment: .top) {
            Text("\(program.rank).").font(.headline).monospacedDigit().frame(width: 28, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(program.name).font(.headline)
                    Spacer()
                    Text(program.worthLabel)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(worthColor.opacity(0.18), in: Capsule())
                        .foregroundStyle(worthColor)
                }
                Text(program.why).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
            }
        }
    }

    private var worthColor: Color {
        switch program.worthIt {
        case "da": return .green
        case "morda": return .orange
        default: return .secondary
        }
    }
}

struct GuideAppRow: View {
    @Environment(AppStore.self) private var store
    let app: GuideApp

    var body: some View {
        HStack(alignment: .top) {
            Text("\(app.installPriority).").font(.headline).monospacedDigit().frame(width: 28, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if app.chain != "other" { ChainTag(chain: app.chain) }
                    Text(app.title).font(.headline)
                }
                Text(app.recommendation.capitalized).font(.caption.weight(.semibold)).foregroundStyle(.tint)
                Text(app.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
            }
        }
    }
}

struct GuideAppDetail: View {
    let app: GuideApp

    var body: some View {
        List {
            Section { Text(app.summary) }
            if !app.benefits.isEmpty {
                Section("Kaj prinese") { ForEach(app.benefits) { StatementView(statement: $0) } }
            }
            Section("Ali so kuponi osebni?") { AnswerView(answer: app.personalCoupons) }
            Section("Ali je kupone treba aktivirati?") { AnswerView(answer: app.activationNeeded) }
            if !app.cardLinking.isEmpty {
                Section("Povezava kartic") { ForEach(app.cardLinking) { StatementView(statement: $0) } }
            }
            if !app.forCouple.isEmpty {
                Section("Za par") { ForEach(app.forCouple) { StatementView(statement: $0) } }
            }
            Section("Trgovine v najini regiji") { AnswerView(answer: app.storesInRegion) }
            Section("Povezave") {
                if let s = app.links.ios, let u = URL(string: s) { Link("App Store", destination: u) }
                if let s = app.links.android, let u = URL(string: s) { Link("Google Play", destination: u) }
                if let s = app.links.web, let u = URL(string: s) { Link("Spletna stran", destination: u) }
            }
        }
        .navigationTitle(app.title)
    }
}

struct LoyaltyDetail: View {
    let program: LoyaltyProgram

    var body: some View {
        List {
            Section("Ocena") {
                Text(program.worthLabel).font(.headline)
                Text(program.why)
            }
            Section("Stroški") { StatementView(statement: program.cost) }
            if !program.keyFacts.isEmpty {
                Section("Ključna dejstva") { ForEach(program.keyFacts) { StatementView(statement: $0) } }
            }
        }
        .navigationTitle(program.name)
    }
}

struct StatementView: View {
    let statement: GuideStatement

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                if statement.advice == true {
                    Image(systemName: "lightbulb").foregroundStyle(.yellow).accessibilityLabel("Nasvet")
                }
                Text(statement.text)
            }
            SourcesView(sources: statement.sources)
        }
    }
}

struct AnswerView: View {
    let answer: GuideAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(answer.label).font(.headline)
            Text(answer.text)
            SourcesView(sources: answer.sources)
        }
    }
}

struct SourcesView: View {
    let sources: [GuideSource]

    var body: some View {
        ForEach(sources, id: \.self) { s in
            if let u = URL(string: s.url) {
                Link(destination: u) {
                    Text("Vir: \(s.title)\(s.date.map { ", \($0)" } ?? "") · preverjeno \(s.accessed)")
                        .font(.caption2)
                        .multilineTextAlignment(.leading)
                }
            }
        }
    }
}

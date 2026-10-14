import SwiftUI

/// Mreža kategorij izbrane sekcije (živila / dom) in seznam trgovin.
struct CategoriesView: View {
    @Environment(AppStore.self) private var store
    @Environment(UIState.self) private var ui

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                StoreSectionPicker()
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(store.categories(in: ui.storeSection)) { c in
                        NavigationLink(value: BrowseScope.category(c.id)) {
                            CategoryTile(category: c, count: store.count(category: c.id))
                        }
                        .buttonStyle(.plain)
                        .hoverEffect(.lift)
                    }
                }
                Text("Trgovine").font(.headline).padding(.top, 8)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(store.meta?.chains ?? []) { ch in
                        NavigationLink(value: BrowseScope.chain(ch.id)) {
                            ChainTile(chain: ch, count: store.offers.filter { $0.chain == ch.id && !$0.isExpired() }.count)
                        }
                        .buttonStyle(.plain)
                        .hoverEffect(.lift)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Kategorije")
    }
}

struct CategoryTile: View {
    let category: CategoryInfo
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: category.icon)
                .font(.title2)
                .foregroundStyle(.tint)
            Text(category.label)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
            Text("\(count) akcij").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

struct ChainTile: View {
    let chain: Chain
    let count: Int

    var body: some View {
        HStack {
            Circle().fill(Color(hex: chain.color)).frame(width: 14, height: 14)
            VStack(alignment: .leading) {
                Text(chain.name).font(.subheadline.weight(.semibold))
                Text("\(count) akcij").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

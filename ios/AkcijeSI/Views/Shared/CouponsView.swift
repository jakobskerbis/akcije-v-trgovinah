import SwiftUI

struct CouponsView: View {
    @Environment(AppStore.self) private var store
    @State private var zoomed: Coupon?

    var body: some View {
        List {
            let grouped = Dictionary(grouping: store.coupons, by: \.chain)
            ForEach(grouped.keys.sorted(), id: \.self) { chain in
                Section {
                    ForEach(grouped[chain] ?? []) { c in
                        CouponRow(coupon: c) { zoomed = c }
                    }
                } header: {
                    HStack { ChainTag(chain: chain); Text("kuponi in ugodnosti") }
                }
            }
            if store.coupons.isEmpty {
                Text("Trenutno ni zajetih kuponov.").foregroundStyle(.secondary)
            }
            Section("Katalogi in letaki") {
                ForEach(store.catalogs()) { cat in
                    if let u = URL(string: cat.url) {
                        Link(destination: u) {
                            HStack {
                                ChainTag(chain: cat.chain)
                                Text(cat.title).lineLimit(2)
                                Spacer()
                                Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                ForEach(store.meta?.chains ?? []) { ch in
                    if let s = ch.catalogUrl, let u = URL(string: s) {
                        Link(destination: u) {
                            HStack {
                                ChainTag(chain: ch.id)
                                Text("Aktualna ponudba")
                                Spacer()
                                Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Kuponi")
        .sheet(item: $zoomed) { c in CouponZoom(coupon: c) }
    }
}

struct CouponRow: View {
    let coupon: Coupon
    var onTapImage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(coupon.title).font(.headline)
            if let s = coupon.imageUrl, let u = URL(string: s) {
                Button(action: onTapImage) {
                    AsyncImage(url: u) { img in img.resizable().scaledToFit() } placeholder: { ProgressView() }
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Povečaj kupon")
            }
            HStack(spacing: 8) {
                Label(coupon.redeemLabel, systemImage: "creditcard")
                if coupon.personal == false { Label("Za vse člane", systemImage: "person.2") }
                if coupon.needsActivation == true { Label("Aktiviraj v aplikaciji", systemImage: "hand.tap") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let from = coupon.validFrom.flatMap(DateParsing.day), let to = coupon.validTo.flatMap(DateParsing.day) {
                Text("Velja \(DateParsing.short(from)) – \(DateParsing.short(to))").font(.caption)
            }
            if let c = coupon.conditions {
                DisclosureGroup("Pogoji") { Text(c).font(.caption).foregroundStyle(.secondary) }
            }
            if let u = URL(string: coupon.sourceUrl) {
                Link("Vir: \(u.host() ?? coupon.sourceUrl)", destination: u).font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Povečan kupon (s črtno kodo), da ga lahko skenirajo na blagajni.
struct CouponZoom: View {
    let coupon: Coupon
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach([coupon.imageUrl, coupon.backImageUrl].compactMap { $0 }, id: \.self) { s in
                        if let u = URL(string: s) {
                            AsyncImage(url: u) { img in img.resizable().scaledToFit() } placeholder: { ProgressView() }
                        }
                    }
                }
                .padding()
            }
            .background(Color.white)
            .navigationTitle(coupon.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Zapri") { dismiss() } } }
        }
    }
}

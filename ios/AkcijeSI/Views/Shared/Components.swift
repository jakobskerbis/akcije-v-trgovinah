import SwiftUI

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        let v = UInt64(s, radix: 16) ?? 0x888888
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}

extension AppStore {
    func color(for chainId: String) -> Color {
        self.chain(chainId).map { Color(hex: $0.color) } ?? .gray
    }
}

struct ChainTag: View {
    @Environment(AppStore.self) private var store
    let chain: String

    var body: some View {
        Text(store.chainName(chain))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(store.color(for: chain), in: Capsule())
            .accessibilityLabel("Trgovina \(store.chainName(chain))")
    }
}

struct DiscountBadge: View {
    let pct: Int

    var body: some View {
        Text("−\(pct) %")
            .font(.subheadline.weight(.heavy))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(pct >= 40 ? Color.red : Color.orange, in: RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel("Popust \(pct) odstotkov")
    }
}

struct ConditionBadge: View {
    let condition: OfferCondition

    var body: some View {
        if condition.type != .none || condition.description != nil {
            Label(condition.description ?? condition.type.label, systemImage: condition.type.symbol)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.thinMaterial, in: Capsule())
                .accessibilityLabel("Pogoj: \(condition.description ?? condition.type.label)")
        }
    }
}

struct DaysLeftLabel: View {
    let offer: Offer

    var body: some View {
        if let text = Format.daysLeft(offer) {
            let urgent = (offer.daysLeft() ?? 99) <= 1 && offer.isStarted()
            Label(text, systemImage: offer.isStarted() ? "clock" : "calendar")
                .font(.caption2)
                .foregroundStyle(urgent ? Color.red : Color.secondary)
        }
    }
}

struct PriceBlock: View {
    let offer: Offer
    var large = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Format.price(offer.price))
                .font(large ? .title2.weight(.bold) : .headline.weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
            HStack(spacing: 6) {
                if let r = offer.regularPrice {
                    Text(Format.price(r))
                        .strikethrough()
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Redna cena \(Format.price(r))")
                }
                if let up = Format.unitPrice(offer) {
                    Text(up).foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .monospacedDigit()
        }
    }
}

struct OfferImage: View {
    let url: String?
    var size: CGFloat = 64

    var body: some View {
        Group {
            if let s = url, let u = URL(string: s) {
                AsyncImage(url: u) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFit()
                    case .failure: placeholder
                    default: ProgressView()
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Image(systemName: "photo").foregroundStyle(.tertiary)
    }
}

/// Vrstica za seznam (iPhone).
struct OfferRow: View {
    @Environment(AppStore.self) private var store
    let offer: Offer
    var reasons: Set<HighlightReason> = []

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(store.color(for: offer.chain))
                .frame(width: 4)
            OfferImage(url: offer.imageUrl, size: 60)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    ChainTag(chain: offer.chain)
                    if let p = offer.discountPct, p > 0 { DiscountBadge(pct: p) }
                    if reasons.contains(.watch) { Image(systemName: "eye.fill").foregroundStyle(.tint).accessibilityLabel("Opazovano") }
                    if offer.isBestUnitPrice { Image(systemName: "scalemass.fill").foregroundStyle(.green).accessibilityLabel("Najnižja cena na enoto") }
                }
                Text(offer.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                if let b = offer.brand { Text(b).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                HStack(spacing: 6) {
                    ConditionBadge(condition: offer.condition)
                    DaysLeftLabel(offer: offer)
                }
            }
            Spacer(minLength: 4)
            PriceBlock(offer: offer, large: true)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 80, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Kartica za mrežo (iPad).
struct OfferCard: View {
    @Environment(AppStore.self) private var store
    let offer: Offer
    var reasons: Set<HighlightReason> = []
    var selected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                OfferImage(url: offer.imageUrl, size: 120)
                    .frame(maxWidth: .infinity)
                if let p = offer.discountPct, p > 0 { DiscountBadge(pct: p) }
            }
            HStack(spacing: 6) {
                ChainTag(chain: offer.chain)
                Spacer()
                if reasons.contains(.watch) { Image(systemName: "eye.fill").foregroundStyle(.tint) }
                if offer.isBestUnitPrice { Image(systemName: "scalemass.fill").foregroundStyle(.green) }
            }
            Text(offer.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2, reservesSpace: true)
            PriceBlock(offer: offer)
            HStack(spacing: 6) {
                ConditionBadge(condition: offer.condition)
                Spacer(minLength: 0)
                DaysLeftLabel(offer: offer)
            }
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 14)
                .fill(store.color(for: offer.chain))
                .frame(width: 5)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
        }
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

struct EmptyStateView: View {
    let title: String
    let symbol: String
    var message: String? = nil

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            if let message { Text(message) }
        }
    }
}

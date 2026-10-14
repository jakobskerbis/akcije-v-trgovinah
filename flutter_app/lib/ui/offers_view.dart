import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_store.dart';
import '../logic/highlights.dart';
import '../logic/matching.dart';
import '../models/feed.dart';
import 'filter_sheet.dart';
import 'offer_detail.dart';
import 'state.dart';
import 'widgets.dart';

class OfferGroup {
  final String id, title;
  final IconData icon;
  final List<Offer> offers;
  OfferGroup(this.id, this.title, this.icon, this.offers);
}

List<OfferGroup> groupsFor(BrowseScope scope, AppStore store, UiState ui, List<WatchTerm> terms) {
  final base = store.visible(ui.filter, ui.search);
  switch (scope) {
    case HighlightsScope():
      final watch = base.where((o) => terms.any((t) => matchesWatch(t, o.name, o.category))).toList();
      final best = base.where((o) => o.bestUnitPrice).toList();
      final disc = base.where((o) => (o.discountPct ?? 0) >= ui.threshold).toList();
      return [
        if (watch.isNotEmpty) OfferGroup('watch', 'Z najinega seznama', Icons.visibility, sortOffers(watch, ui.sort)),
        if (best.isNotEmpty)
          OfferGroup('best', 'Najnižja cena na enoto', Icons.scale,
              sortOffers(best, ui.sort == SortOrder.discount ? SortOrder.unitPrice : ui.sort)),
        OfferGroup('discount', 'Popust ≥ ${ui.threshold} %', Icons.percent, sortOffers(disc, ui.sort)),
      ];
    case AllScope():
      return [OfferGroup('all', 'Zadetki', Icons.search, sortOffers(base, ui.sort))];
    case CategoryScope(:final id):
      final c = store.category(id);
      return [
        OfferGroup('cat', c?.label ?? id, categoryIcon(c?.icon ?? ''),
            sortOffers(base.where((o) => o.category == id), ui.sort))
      ];
    case ChainScope(:final id):
      return [OfferGroup('chain', store.chainName(id), Icons.store, sortOffers(base.where((o) => o.chain == id), ui.sort))];
    case WatchScope(:final term, :final category):
      final w = WatchTerm(term, category);
      return [
        OfferGroup('w', term, Icons.visibility,
            sortOffers(store.offers.where((o) => !o.isExpired() && matchesWatch(w, o.name, o.category)), SortOrder.unitPrice))
      ];
  }
}

String scopeTitle(BrowseScope s, AppStore store) => switch (s) {
      HighlightsScope() => 'Izpostavljeno',
      AllScope() => 'Iskanje',
      CategoryScope(:final id) => store.category(id)?.label ?? id,
      ChainScope(:final id) => store.chainName(id),
      WatchScope(:final term) => term,
    };

class SectionSwitch extends StatelessWidget {
  const SectionSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    return AppListener(builder: (context, s) {
      return SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'zivila', label: Text('Živila'), icon: Icon(Icons.shopping_basket_outlined)),
          ButtonSegment(value: 'dom', label: Text('Dom in vrt'), icon: Icon(Icons.yard_outlined)),
        ],
        selected: {s.ui.storeSection},
        onSelectionChanged: (v) => s.ui.setStoreSection(v.first),
      );
    });
  }
}

class SortButton extends StatelessWidget {
  const SortButton({super.key});

  @override
  Widget build(BuildContext context) {
    final ui = AppScope.of(context).ui;
    return PopupMenuButton<SortOrder>(
      tooltip: 'Razvrsti',
      icon: const Icon(Icons.sort),
      initialValue: ui.sort,
      onSelected: ui.setSort,
      itemBuilder: (_) => [for (final s in SortOrder.values) CheckedPopupMenuItem(value: s, checked: ui.sort == s, child: Text(s.label))],
    );
  }
}

class FilterButton extends StatelessWidget {
  const FilterButton({super.key});

  @override
  Widget build(BuildContext context) {
    return AppListener(
      builder: (context, s) => IconButton(
        tooltip: 'Filtri',
        icon: Icon(s.ui.filter.isActive ? Icons.filter_alt : Icons.filter_alt_outlined),
        onPressed: () => showFilterSheet(context),
      ),
    );
  }
}

/// Seznam (telefon) ali mreža (širok zaslon) ponudb.
class OffersView extends StatelessWidget {
  final BrowseScope scope;
  final bool grid;
  final void Function(Offer)? onSelect;
  const OffersView({super.key, required this.scope, this.grid = false, this.onSelect});

  @override
  Widget build(BuildContext context) {
    return AppListener(builder: (context, s) {
      final effective = s.ui.search.isNotEmpty && scope is HighlightsScope ? const AllScope() : scope;
      final groups = groupsFor(effective, s.store, s.ui, s.lists.watchTerms);
      if (s.store.offers.isEmpty) {
        return s.store.isRefreshing
            ? const Center(child: CircularProgressIndicator())
            : const EmptyState(icon: Icons.wifi_off, title: 'Ni podatkov', message: 'Povleci navzdol ali pritisni Ctrl+R.');
      }
      final slivers = <Widget>[
        if (scope is HighlightsScope)
          const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 4), child: SectionSwitch())),
      ];
      for (final g in groups) {
        slivers.add(SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(children: [
              Icon(g.icon, size: 18),
              const SizedBox(width: 6),
              Text('${g.title} · ${g.offers.length}', style: Theme.of(context).textTheme.titleSmall),
            ]),
          ),
        ));
        final shown = g.offers.take(grid ? 400 : 300).toList();
        if (shown.isEmpty) {
          slivers.add(const SliverToBoxAdapter(
              child: Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Ni zadetkov.'))));
          continue;
        }
        if (grid) {
          slivers.add(SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 240, mainAxisExtent: 300, crossAxisSpacing: 12, mainAxisSpacing: 12),
              delegate: SliverChildBuilderDelegate(
                (c, i) => OfferCard(
                  offer: shown[i],
                  reasons: reasonsFor(shown[i], s.ui.threshold, s.lists.watchTerms),
                  selected: s.ui.selectedOffer?.id == shown[i].id,
                  onTap: () => onSelect != null ? onSelect!(shown[i]) : openDetail(c, shown[i]),
                ),
                childCount: shown.length,
              ),
            ),
          ));
        } else {
          slivers.add(SliverList.separated(
            itemCount: shown.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
            itemBuilder: (c, i) => OfferTile(
              offer: shown[i],
              reasons: reasonsFor(shown[i], s.ui.threshold, s.lists.watchTerms),
              onTap: () => openDetail(c, shown[i]),
            ),
          ));
        }
        if (g.offers.length > shown.length) {
          slivers.add(SliverToBoxAdapter(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Prikazanih ${shown.length} od ${g.offers.length}. Zoži iskanje ali filtre.'))));
        }
      }
      slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 24)));
      return RefreshIndicator(
        onRefresh: s.refresh,
        child: CustomScrollView(slivers: slivers),
      );
    });
  }
}

void openDetail(BuildContext context, Offer o) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => OfferDetailPage(offer: o)));
}

/// Vrstica za telefon; poteg v desno doda na nakupovalni seznam.
class OfferTile extends StatelessWidget {
  final Offer offer;
  final Set<HighlightReason> reasons;
  final VoidCallback onTap;
  const OfferTile({super.key, required this.offer, required this.reasons, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final tt = Theme.of(context).textTheme;
    return Dismissible(
      key: ValueKey('tile-${offer.id}'),
      direction: DismissDirection.startToEnd,
      background: Container(
        color: Colors.green.shade600,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: const Row(children: [
          Icon(Icons.add_shopping_cart, color: Colors.white),
          SizedBox(width: 8),
          Text('Na seznam', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        ]),
      ),
      confirmDismiss: (_) async {
        HapticFeedback.mediumImpact();
        await s.lists.addOffer(offer);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Dodano na seznam: ${offer.name}'), duration: const Duration(seconds: 2)));
        }
        return false;
      },
      child: InkWell(
        onTap: onTap,
        onLongPress: () async {
          HapticFeedback.mediumImpact();
          await s.lists.addOffer(offer);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Dodano na seznam: ${offer.name}')));
          }
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 12, 8),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(width: 4, color: chainColor(s.store, offer.chain)),
              const SizedBox(width: 10),
              Align(alignment: Alignment.topCenter, child: OfferImage(offer.imageUrl, size: 56)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    ChainTag(s.store, offer.chain),
                    if ((offer.discountPct ?? 0) > 0) DiscountBadge(offer.discountPct!),
                    if (reasons.contains(HighlightReason.watch)) const Icon(Icons.visibility, size: 16),
                    if (offer.bestUnitPrice) Icon(Icons.scale, size: 16, color: Colors.green.shade700),
                  ]),
                  const SizedBox(height: 4),
                  Text(offer.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: tt.titleSmall),
                  if (offer.brand != null)
                    Text(offer.brand!, maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.bodySmall?.copyWith(color: Theme.of(context).hintColor)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, runSpacing: 4, children: [ConditionBadge(offer), DaysLeftText(offer)]),
                ]),
              ),
              const SizedBox(width: 8),
              PriceBlock(offer, align: CrossAxisAlignment.end),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Kartica za mrežo; vlečenje na "Moj seznam" doda izdelek na seznam.
class OfferCard extends StatelessWidget {
  final Offer offer;
  final Set<HighlightReason> reasons;
  final bool selected;
  final VoidCallback onTap;
  const OfferCard({super.key, required this.offer, required this.reasons, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final card = Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: cs.primary.withValues(alpha: 0.06),
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: chainColor(s.store, offer.chain), width: 5)),
          ),
          foregroundDecoration: selected
              ? BoxDecoration(border: Border.all(color: cs.primary, width: 2), borderRadius: BorderRadius.circular(14))
              : null,
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Stack(children: [
              Center(child: OfferImage(offer.imageUrl, size: 110)),
              if ((offer.discountPct ?? 0) > 0) DiscountBadge(offer.discountPct!),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              ChainTag(s.store, offer.chain),
              const Spacer(),
              if (reasons.contains(HighlightReason.watch)) const Icon(Icons.visibility, size: 16),
              if (offer.bestUnitPrice) Icon(Icons.scale, size: 16, color: Colors.green.shade700),
            ]),
            const SizedBox(height: 6),
            Text(offer.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            PriceBlock(offer),
            const SizedBox(height: 4),
            Row(children: [
              Flexible(child: ConditionBadge(offer)),
              const Spacer(),
              DaysLeftText(offer),
            ]),
          ]),
        ),
      ),
    );
    return Draggable<Offer>(
      data: offer,
      feedback: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.add_shopping_cart),
            const SizedBox(width: 8),
            ConstrainedBox(constraints: const BoxConstraints(maxWidth: 220), child: Text(offer.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: card),
      child: Semantics(button: true, child: card),
    );
  }
}

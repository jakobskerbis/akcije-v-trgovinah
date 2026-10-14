import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../logic/highlights.dart';
import '../logic/matching.dart';
import '../models/feed.dart';
import '../models/shared_doc.dart';
import 'offers_view.dart';
import 'settings_view.dart';
import 'state.dart';
import 'widgets.dart';

class MyListView extends StatefulWidget {
  const MyListView({super.key});

  @override
  State<MyListView> createState() => _MyListViewState();
}

class _MyListViewState extends State<MyListView> {
  final _item = TextEditingController();
  final _watch = TextEditingController();

  @override
  void dispose() {
    _item.dispose();
    _watch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppListener(builder: (context, s) {
      final items = s.lists.shopping
        ..sort((a, b) => a.checked == b.checked ? a.createdAt.compareTo(b.createdAt) : (a.checked ? 1 : -1));
      final groups = <String?, List<SharedShopping>>{};
      for (final i in items) {
        groups.putIfAbsent(i.chain, () => []).add(i);
      }
      final keys = groups.keys.toList()..sort((a, b) => (a ?? '~').compareTo(b ?? '~'));
      final open = items.where((i) => !i.checked).toList();
      final total = open.where((i) => i.price != null).fold<double>(0, (t, i) => t + i.price! * i.quantity);

      return RefreshIndicator(
        onRefresh: s.lists.sync,
        child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
          if (!s.lists.isConfigured)
            Card(
              margin: const EdgeInsets.all(12),
              child: ListTile(
                leading: const Icon(Icons.group_add_outlined),
                title: const Text('Poveži skupni seznam s partnerjem'),
                subtitle: const Text('Seznam je zdaj samo na tej napravi. V nastavitvah vnesi GitHub žeton.'),
                onTap: () => openSettings(context),
              ),
            )
          else if (s.lists.lastError != null)
            ListTile(leading: const Icon(Icons.warning_amber, color: Colors.orange), title: Text(s.lists.lastError!)),
          _header(context, 'Nakupovalni seznam · ${open.length}'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _item,
              decoration: InputDecoration(
                hintText: 'Dodaj na seznam …',
                suffixIcon: IconButton(icon: const Icon(Icons.add_circle), tooltip: 'Dodaj', onPressed: _addItem),
              ),
              onSubmitted: (_) => _addItem(),
            ),
          ),
          for (final k in keys) ...[
            if (k != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(s.store.chainName(k),
                    style: TextStyle(color: chainColor(s.store, k), fontWeight: FontWeight.w600)),
              ),
            for (final i in groups[k]!)
              Dismissible(
                key: ValueKey('shop-${i.id}'),
                direction: DismissDirection.endToStart,
                background: Container(
                    color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20),
                    child: const Icon(Icons.delete, color: Colors.white)),
                onDismissed: (_) => s.lists.deleteItem(i),
                child: CheckboxListTile(
                  controlAffinity: ListTileControlAffinity.leading,
                  value: i.checked,
                  onChanged: (_) {
                    HapticFeedback.selectionClick();
                    s.lists.toggle(i);
                  },
                  title: Text(i.title,
                      style: TextStyle(
                          decoration: i.checked ? TextDecoration.lineThrough : null,
                          color: i.checked ? Theme.of(context).hintColor : null)),
                  subtitle: _subtitle(s, i),
                  secondary: i.price != null ? Text(formatPrice(i.price!)) : null,
                ),
              ),
          ],
          if (items.any((i) => i.checked))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextButton.icon(
                  onPressed: s.lists.clearChecked, icon: const Icon(Icons.delete_sweep), label: const Text('Odstrani kupljeno')),
            ),
          if (total > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text('Ocena po akcijskih cenah: ${formatPrice(total)}', style: Theme.of(context).textTheme.bodySmall),
            ),
          _header(context, 'Opazovana živila'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _watch,
              decoration: InputDecoration(
                hintText: 'Opazuj živilo, npr. »piščančje prsi«',
                suffixIcon: IconButton(icon: const Icon(Icons.visibility), tooltip: 'Dodaj opazovano živilo', onPressed: _addWatch),
              ),
              onSubmitted: (_) => _addWatch(),
            ),
          ),
          for (final w in s.lists.watch)
            Dismissible(
              key: ValueKey('watch-${w.id}'),
              direction: DismissDirection.endToStart,
              background: Container(
                  color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20),
                  child: const Icon(Icons.delete, color: Colors.white)),
              onDismissed: (_) => s.lists.deleteWatch(w),
              child: Builder(builder: (context) {
                final hits = s.store.offers.where((o) => !o.isExpired() && matchesTerm(w.term, o.name)).length;
                return ListTile(
                  title: Text(w.term),
                  subtitle: w.by != null ? Text(w.by!) : null,
                  trailing: Text(hits == 0 ? 'ni akcij' : '$hits akcij',
                      style: TextStyle(color: hits == 0 ? Theme.of(context).hintColor : Theme.of(context).colorScheme.primary)),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => Scaffold(appBar: AppBar(title: Text(w.term)), body: OffersView(scope: WatchScope(w.term))),
                  )),
                );
              }),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text('Ko se opazovano živilo pojavi v akciji, dobiš obvestilo. Besede se ujemajo tudi v drugih sklonih.'),
          ),
        ]),
      );
    });
  }

  Widget? _subtitle(AppScope s, SharedShopping i) {
    final parts = <String>[];
    final o = i.offerId == null ? null : s.store.offer(i.offerId!);
    if (o != null) {
      final d = formatDaysLeft(o);
      if (d != null) parts.add(d);
    }
    if (i.by != null) parts.add(i.by!);
    return parts.isEmpty ? null : Text(parts.join(' · '));
  }

  Widget _header(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(t, style: Theme.of(context).textTheme.titleMedium),
      );

  void _addItem() {
    AppScope.of(context).lists.addItem(_item.text);
    _item.clear();
    HapticFeedback.lightImpact();
  }

  void _addWatch() {
    AppScope.of(context).lists.addWatch(_watch.text);
    _watch.clear();
    HapticFeedback.lightImpact();
  }
}

/// Cilj za vlečenje kartic (širok zaslon): spuščen izdelek gre na seznam.
class ShoppingDropTarget extends StatelessWidget {
  final Widget child;
  const ShoppingDropTarget({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return DragTarget<Offer>(
      onAcceptWithDetails: (d) {
        HapticFeedback.mediumImpact();
        s.lists.addOffer(d.data);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Dodano na seznam: ${d.data.name}')));
      },
      builder: (context, candidates, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: candidates.isNotEmpty ? Theme.of(context).colorScheme.primaryContainer : null,
          borderRadius: BorderRadius.circular(16),
        ),
        child: child,
      ),
    );
  }
}

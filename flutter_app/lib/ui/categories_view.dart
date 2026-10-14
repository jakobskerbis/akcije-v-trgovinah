import 'package:flutter/material.dart';

import '../models/feed.dart';
import 'offers_view.dart';
import 'state.dart';
import 'widgets.dart';

class CategoriesView extends StatelessWidget {
  /// Če je podano, se izbira odpre v srednjem stolpcu (širok zaslon).
  final void Function(BrowseScope)? onOpen;
  const CategoriesView({super.key, this.onOpen});

  void _open(BuildContext context, BrowseScope scope) {
    if (onOpen != null) {
      onOpen!(scope);
      return;
    }
    final store = AppScope.of(context).store;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(scopeTitle(scope, store)), actions: const [SortButton(), FilterButton()]),
        body: OffersView(scope: scope),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AppListener(builder: (context, s) {
      final cats = s.store.categoriesIn(s.ui.storeSection);
      return CustomScrollView(slivers: [
        const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(16), child: SectionSwitch())),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200, mainAxisExtent: 120, crossAxisSpacing: 12, mainAxisSpacing: 12),
            delegate: SliverChildBuilderDelegate(
              (c, i) => _Tile(
                icon: categoryIcon(cats[i].icon),
                title: cats[i].label,
                subtitle: '${s.store.countCategory(cats[i].id)} akcij',
                onTap: () => _open(c, CategoryScope(cats[i].id)),
              ),
              childCount: cats.length,
            ),
          ),
        ),
        SliverToBoxAdapter(
            child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                child: Text('Trgovine', style: Theme.of(context).textTheme.titleMedium))),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220, mainAxisExtent: 72, crossAxisSpacing: 12, mainAxisSpacing: 12),
            delegate: SliverChildListDelegate([
              for (final Chain ch in s.store.meta?.chains ?? <Chain>[])
                _Tile(
                  leading: CircleAvatar(radius: 7, backgroundColor: hexColor(ch.color)),
                  title: ch.name,
                  subtitle: '${s.store.countChain(ch.id)} akcij',
                  onTap: () => _open(context, ChainScope(ch.id)),
                ),
            ]),
          ),
        ),
      ]);
    });
  }
}

class _Tile extends StatelessWidget {
  final IconData? icon;
  final Widget? leading;
  final String title, subtitle;
  final VoidCallback onTap;
  const _Tile({this.icon, this.leading, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: icon != null
              ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(icon, color: cs.primary),
                  const Spacer(),
                  Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ])
              : Row(children: [
                  leading ?? const SizedBox.shrink(),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(title, style: Theme.of(context).textTheme.titleSmall),
                      Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                    ]),
                  ),
                ]),
        ),
      ),
    );
  }
}

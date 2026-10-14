import 'package:flutter/material.dart';

import '../logic/highlights.dart';
import '../models/feed.dart';
import 'state.dart';
import 'widgets.dart';

Future<void> showFilterSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => AppScope(
      store: AppScope.of(context).store,
      lists: AppScope.of(context).lists,
      ui: AppScope.of(context).ui,
      refresh: AppScope.of(context).refresh,
      child: const FilterSheet(),
    ),
  );
}

class FilterSheet extends StatelessWidget {
  const FilterSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return AppListener(builder: (context, s) {
      final f = s.ui.filter;
      void toggle<T>(Set<T> set, T v, bool on) {
        on ? set.add(v) : set.remove(v);
        s.ui.filterChanged();
      }

      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (context, controller) => ListView(controller: controller, children: [
          ListTile(
            title: Text('Filtri', style: Theme.of(context).textTheme.titleLarge),
            trailing: TextButton(
              onPressed: f.isActive
                  ? () {
                      s.ui.filter = OfferFilter(section: f.section);
                      s.ui.filterChanged();
                    }
                  : null,
              child: const Text('Ponastavi'),
            ),
          ),
          const _Header('Trgovine'),
          for (final ch in s.store.meta?.chains ?? <Chain>[])
            CheckboxListTile(
              value: f.chains.contains(ch.id),
              onChanged: (v) => toggle(f.chains, ch.id, v ?? false),
              secondary: CircleAvatar(radius: 6, backgroundColor: hexColor(ch.color)),
              title: Text(ch.name),
              subtitle: Text('${s.store.countChain(ch.id)} akcij'),
            ),
          const _Header('Kategorije'),
          for (final c in s.store.categoriesIn(s.ui.storeSection))
            CheckboxListTile(
              value: f.categories.contains(c.id),
              onChanged: (v) => toggle(f.categories, c.id, v ?? false),
              secondary: Icon(categoryIcon(c.icon)),
              title: Text(c.label),
            ),
          const _Header('Pogoj akcije'),
          for (final t in ConditionType.values)
            CheckboxListTile(
              value: f.conditions.contains(t),
              onChanged: (v) => toggle(f.conditions, t, v ?? false),
              secondary: Icon(conditionIcon(t)),
              title: Text(t.label),
            ),
          SwitchListTile(
            value: f.onlyActive,
            onChanged: (v) {
              f.onlyActive = v;
              s.ui.filterChanged();
            },
            title: const Text('Samo akcije, ki že veljajo'),
          ),
          const SizedBox(height: 24),
        ]),
      );
    });
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}

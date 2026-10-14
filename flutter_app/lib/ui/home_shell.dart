import 'package:flutter/material.dart';

import 'categories_view.dart';
import 'coupons_view.dart';
import 'guide_view.dart';
import 'my_list_view.dart';
import 'offer_detail.dart';
import 'offers_view.dart';
import 'settings_view.dart';
import 'state.dart';
import 'widgets.dart';

/// Ozek zaslon (telefon): spodnja navigacija. Širok zaslon (Windows, tablica):
/// stranska vrstica + mreža izdelkov + podrobnosti.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => c.maxWidth >= 840 ? WideShell(showDetail: c.maxWidth >= 1180) : const NarrowShell(),
    );
  }
}

class SearchField extends StatelessWidget {
  final double width;
  const SearchField({super.key, this.width = 320});

  @override
  Widget build(BuildContext context) {
    final ui = AppScope.of(context).ui;
    return SizedBox(
      width: width,
      height: 44,
      child: TextField(
        controller: ui.searchController,
        focusNode: ui.searchFocus,
        onChanged: ui.setSearch,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Išči izdelek ali trgovino',
          prefixIcon: const Icon(Icons.search),
          isDense: true,
          filled: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
          suffixIcon: ListenableBuilder(
            listenable: ui.searchController,
            builder: (context, _) => ui.searchController.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Počisti',
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      ui.searchController.clear();
                      ui.setSearch('');
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

class NarrowShell extends StatefulWidget {
  const NarrowShell({super.key});

  @override
  State<NarrowShell> createState() => _NarrowShellState();
}

class _NarrowShellState extends State<NarrowShell> {
  final _navKeys = List.generate(AppSection.values.length, (_) => GlobalKey<NavigatorState>());

  @override
  Widget build(BuildContext context) {
    return AppListener(builder: (context, s) {
      final idx = s.ui.section.index;
      return PopScope(
        canPop: !(_navKeys[idx].currentState?.canPop() ?? false),
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _navKeys[idx].currentState?.maybePop();
        },
        child: Scaffold(
          body: IndexedStack(
            index: idx,
            children: [
              for (final sec in AppSection.values)
                Navigator(
                  key: _navKeys[sec.index],
                  onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => _root(sec)),
                ),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: idx,
            onDestinationSelected: (i) {
              if (i == idx) _navKeys[i].currentState?.popUntil((r) => r.isFirst);
              s.ui.setSection(AppSection.values[i]);
            },
            destinations: [
              for (final sec in AppSection.values)
                NavigationDestination(icon: Icon(sec.icon), selectedIcon: Icon(sec.selectedIcon), label: sec.title),
            ],
          ),
        ),
      );
    });
  }

  Widget _root(AppSection sec) {
    final settings = Builder(
      builder: (c) => IconButton(tooltip: 'Nastavitve', icon: const Icon(Icons.settings_outlined), onPressed: () => openSettings(c)),
    );
    return switch (sec) {
      AppSection.highlights => Scaffold(
          appBar: AppBar(
            title: const Text('Izpostavljeno'),
            leading: settings,
            actions: const [SortButton(), FilterButton()],
            bottom: const PreferredSize(
              preferredSize: Size.fromHeight(56),
              child: Padding(padding: EdgeInsets.fromLTRB(12, 0, 12, 8), child: SearchField(width: double.infinity)),
            ),
          ),
          body: const OffersView(scope: HighlightsScope()),
        ),
      AppSection.categories => Scaffold(appBar: AppBar(title: const Text('Kategorije'), leading: settings), body: const CategoriesView()),
      AppSection.coupons => Scaffold(appBar: AppBar(title: const Text('Kuponi')), body: const CouponsView()),
      AppSection.myList => Scaffold(appBar: AppBar(title: const Text('Moj seznam'), actions: [settings]), body: const MyListView()),
      AppSection.guide => Scaffold(appBar: AppBar(title: const Text('Vodič')), body: const GuideView()),
    };
  }
}

class WideShell extends StatelessWidget {
  final bool showDetail;
  const WideShell({super.key, required this.showDetail});

  @override
  Widget build(BuildContext context) {
    return AppListener(builder: (context, s) {
      final sec = s.ui.section;
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: sec.index,
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: (i) => s.ui.setSection(AppSection.values[i]),
            leading: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: Text('Akcije SI', style: Theme.of(context).textTheme.titleSmall),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: IconButton(tooltip: 'Nastavitve', icon: const Icon(Icons.settings_outlined), onPressed: () => openSettings(context)),
                ),
              ),
            ),
            destinations: [
              for (final d in AppSection.values)
                NavigationRailDestination(
                  icon: d == AppSection.myList
                      ? ShoppingDropTarget(child: Padding(padding: const EdgeInsets.all(4), child: Icon(d.icon)))
                      : Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: Text(d.title),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _middle(context, s)),
          if (showDetail && (sec == AppSection.highlights || sec == AppSection.categories)) ...[
            const VerticalDivider(width: 1),
            SizedBox(
              width: 420,
              child: s.ui.selectedOffer == null
                  ? const EmptyState(
                      icon: Icons.touch_app_outlined,
                      title: 'Izberi izdelek',
                      message: 'Podrobnosti, zgodovina cene in primerjava med trgovinami.')
                  : Scaffold(
                      appBar: AppBar(
                        title: Text(s.ui.selectedOffer!.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        automaticallyImplyLeading: false,
                        actions: [IconButton(tooltip: 'Zapri', icon: const Icon(Icons.close), onPressed: () => s.ui.select(null))],
                      ),
                      body: OfferDetailBody(
                          key: ValueKey(s.ui.selectedOffer!.id), offer: s.ui.selectedOffer!, onSelect: s.ui.select),
                    ),
            ),
          ],
        ]),
      );
    });
  }

  Widget _middle(BuildContext context, AppScope s) {
    void select(o) => showDetail ? s.ui.select(o) : openDetail(context, o);
    final actions = [
      const SearchField(),
      const SizedBox(width: 8),
      const SortButton(),
      const FilterButton(),
      IconButton(
        tooltip: 'Osveži (Ctrl+R)',
        icon: s.store.isRefreshing
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.refresh),
        onPressed: s.store.isRefreshing ? null : s.refresh,
      ),
      const SizedBox(width: 8),
    ];
    switch (s.ui.section) {
      case AppSection.highlights:
        return Scaffold(
          appBar: AppBar(title: const Text('Izpostavljeno'), actions: actions),
          body: OffersView(scope: const HighlightsScope(), grid: true, onSelect: select),
        );
      case AppSection.categories:
        final scope = s.ui.wideScope;
        if (scope is CategoryScope || scope is ChainScope) {
          return Scaffold(
            appBar: AppBar(
              leading: IconButton(
                  tooltip: 'Nazaj', icon: const Icon(Icons.arrow_back), onPressed: () => s.ui.setWideScope(const HighlightsScope())),
              title: Text(scopeTitle(scope, s.store)),
              actions: actions,
            ),
            body: OffersView(scope: scope, grid: true, onSelect: select),
          );
        }
        return Scaffold(appBar: AppBar(title: const Text('Kategorije')), body: CategoriesView(onOpen: s.ui.setWideScope));
      case AppSection.coupons:
        return Navigator(onGenerateRoute: (_) => MaterialPageRoute(
            builder: (_) => Scaffold(appBar: AppBar(title: const Text('Kuponi')), body: const CouponsView())));
      case AppSection.myList:
        return Navigator(onGenerateRoute: (_) => MaterialPageRoute(
            builder: (_) => Scaffold(appBar: AppBar(title: const Text('Moj seznam')), body: const MyListView())));
      case AppSection.guide:
        return Navigator(onGenerateRoute: (_) => MaterialPageRoute(
            builder: (_) => Scaffold(appBar: AppBar(title: const Text('Vodič')), body: const GuideView())));
    }
  }
}

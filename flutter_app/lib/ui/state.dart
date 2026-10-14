import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/app_store.dart';
import '../data/lists_store.dart';
import '../logic/highlights.dart';
import '../models/feed.dart';

enum AppSection { highlights, categories, coupons, myList, guide }

extension AppSectionX on AppSection {
  String get title => switch (this) {
        AppSection.highlights => 'Izpostavljeno',
        AppSection.categories => 'Kategorije',
        AppSection.coupons => 'Kuponi',
        AppSection.myList => 'Moj seznam',
        AppSection.guide => 'Vodič',
      };

  IconData get icon => switch (this) {
        AppSection.highlights => Icons.star_outline,
        AppSection.categories => Icons.grid_view,
        AppSection.coupons => Icons.local_offer_outlined,
        AppSection.myList => Icons.checklist,
        AppSection.guide => Icons.menu_book_outlined,
      };

  IconData get selectedIcon => switch (this) {
        AppSection.highlights => Icons.star,
        AppSection.categories => Icons.grid_view_rounded,
        AppSection.coupons => Icons.local_offer,
        AppSection.myList => Icons.checklist_rtl,
        AppSection.guide => Icons.menu_book,
      };
}

/// Kaj prikazuje srednji stolpec / seznam.
sealed class BrowseScope {
  const BrowseScope();
}

class HighlightsScope extends BrowseScope {
  const HighlightsScope();
}

class AllScope extends BrowseScope {
  const AllScope();
}

class CategoryScope extends BrowseScope {
  final String id;
  const CategoryScope(this.id);
}

class ChainScope extends BrowseScope {
  final String id;
  const ChainScope(this.id);
}

class WatchScope extends BrowseScope {
  final String term;
  final String? category;
  const WatchScope(this.term, [this.category]);
}

class UiState extends ChangeNotifier {
  AppSection section = AppSection.highlights;
  String storeSection = 'zivila';
  OfferFilter filter = OfferFilter();
  SortOrder sort = SortOrder.discount;
  String search = '';
  Offer? selectedOffer;
  BrowseScope wideScope = const HighlightsScope();
  int threshold = 30;
  bool notifyWatch = true;
  bool notifyHighlights = true;
  final searchFocus = FocusNode();
  final searchController = TextEditingController();

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    storeSection = p.getString('storeSection') ?? 'zivila';
    filter.section = storeSection;
    threshold = p.getInt('threshold') ?? 30;
    notifyWatch = p.getBool('notifyWatch') ?? true;
    notifyHighlights = p.getBool('notifyHighlights') ?? true;
    notifyListeners();
  }

  void setSection(AppSection s) {
    section = s;
    if (s == AppSection.highlights) wideScope = const HighlightsScope();
    notifyListeners();
  }

  Future<void> setStoreSection(String s) async {
    storeSection = s;
    filter.section = s;
    filter.categories = {};
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('storeSection', s);
  }

  void setSearch(String s) {
    search = s;
    notifyListeners();
  }

  void setSort(SortOrder s) {
    sort = s;
    notifyListeners();
  }

  void select(Offer? o) {
    selectedOffer = o;
    notifyListeners();
  }

  void setWideScope(BrowseScope s) {
    wideScope = s;
    selectedOffer = null;
    notifyListeners();
  }

  void filterChanged() => notifyListeners();

  Future<void> setThreshold(int v) async {
    threshold = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setInt('threshold', v);
  }

  Future<void> setNotify({bool? watch, bool? highlights}) async {
    notifyWatch = watch ?? notifyWatch;
    notifyHighlights = highlights ?? notifyHighlights;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool('notifyWatch', notifyWatch);
    await p.setBool('notifyHighlights', notifyHighlights);
  }

  void focusSearch() {
    if (section != AppSection.highlights && section != AppSection.categories) {
      setSection(AppSection.highlights);
    }
    searchFocus.requestFocus();
  }
}

/// Dostop do skupnih objektov v drevesu gradnikov.
class AppScope extends InheritedWidget {
  final AppStore store;
  final ListsStore lists;
  final UiState ui;
  final Future<void> Function() refresh;

  const AppScope({
    super.key,
    required this.store,
    required this.lists,
    required this.ui,
    required this.refresh,
    required super.child,
  });

  static AppScope of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope old) => false;
}

/// Prenovi gradnik ob vsaki spremembi podatkov, seznamov ali stanja UI.
class AppListener extends StatelessWidget {
  final Widget Function(BuildContext context, AppScope scope) builder;
  const AppListener({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([s.store, s.lists, s.ui]),
      builder: (context, _) => builder(context, s),
    );
  }
}

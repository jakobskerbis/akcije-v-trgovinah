import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../logic/highlights.dart';
import '../logic/matching.dart';
import '../models/feed.dart';
import '../models/guide.dart';

/// Prenese in predpomni JSON datoteke z GitHub Pages (ali iz veje "data").
class AppStore extends ChangeNotifier {
  static const feeds = ['offers', 'coupons', 'meta', 'guide', 'history'];
  static const primaryBase = 'https://jakobskerbis.github.io/akcije-v-trgovinah/';
  static const fallbackBase = 'https://raw.githubusercontent.com/jakobskerbis/akcije-v-trgovinah/data/';

  final bool demoMode;
  final http.Client _client;

  AppStore({this.demoMode = false, http.Client? client}) : _client = client ?? http.Client();

  List<Offer> offers = [];
  List<Coupon> coupons = [];
  Meta? meta;
  Guide? guide;
  Map<String, List<PricePoint>> history = {};
  bool isRefreshing = false;
  String? lastError;
  DateTime? lastFetched;
  DateTime? generatedAt;

  Map<String, Chain> _chains = {};
  Map<String, CategoryInfo> _categories = {};
  Map<String, String> categorySection = {};
  Map<String, Offer> _offersById = {};

  Future<Directory> _cacheDir() async {
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}${Platform.pathSeparator}feeds');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  Future<void> loadCached() async {
    if (demoMode) {
      for (final name in feeds) {
        try {
          _apply(name, await rootBundle.loadString('assets/demo/$name.json'));
        } catch (_) {}
      }
      lastFetched = DateTime.now();
    } else {
      final dir = await _cacheDir();
      DateTime? newest;
      for (final name in feeds) {
        final f = File('${dir.path}${Platform.pathSeparator}$name.json');
        if (f.existsSync()) {
          try {
            _apply(name, await f.readAsString());
            final m = f.lastModifiedSync();
            if (newest == null || m.isAfter(newest)) newest = m;
          } catch (_) {}
        }
      }
      lastFetched = newest;
    }
    _rebuild();
    notifyListeners();
  }

  /// Prenese vse datoteke; vrne ID-je novih ponudb.
  Future<Set<String>> refresh() async {
    if (demoMode || isRefreshing) return {};
    isRefreshing = true;
    notifyListeners();
    final before = offers.map((o) => o.id).toSet();
    final errors = <String>[];
    final dir = await _cacheDir();
    for (final name in feeds) {
      try {
        final body = await _download(name);
        _apply(name, body);
        await File('${dir.path}${Platform.pathSeparator}$name.json').writeAsString(body);
      } catch (e) {
        errors.add('$name: $e');
      }
    }
    _rebuild();
    lastError = errors.isEmpty ? null : errors.join('\n');
    if (errors.length < feeds.length) lastFetched = DateTime.now();
    isRefreshing = false;
    notifyListeners();
    return offers.map((o) => o.id).toSet().difference(before);
  }

  Future<String> _download(String name) async {
    Object err = 'ni povezave';
    for (final base in [primaryBase, fallbackBase]) {
      try {
        final r = await _client
            .get(Uri.parse('$base$name.json'), headers: {'Cache-Control': 'no-cache'})
            .timeout(const Duration(seconds: 30));
        if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) return utf8.decode(r.bodyBytes);
        err = 'HTTP ${r.statusCode}';
      } catch (e) {
        err = e;
      }
    }
    throw Exception(err);
  }

  void _apply(String name, String body) {
    final j = jsonDecode(body) as Map<String, dynamic>;
    switch (name) {
      case 'offers':
        offers = ((j['offers'] as List?) ?? const [])
            .map((e) => Offer.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
        generatedAt = DateTime.tryParse(j['generatedAt'] as String? ?? '');
      case 'coupons':
        coupons = ((j['coupons'] as List?) ?? const [])
            .map((e) => Coupon.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
      case 'meta':
        meta = Meta.fromJson(j);
      case 'guide':
        guide = Guide.fromJson(j);
      case 'history':
        history = parseHistory(j);
    }
  }

  void _rebuild() {
    _chains = {for (final c in meta?.chains ?? <Chain>[]) c.id: c};
    _categories = {for (final c in meta?.categories ?? <CategoryInfo>[]) c.id: c};
    categorySection = {for (final c in _categories.values) c.id: c.section};
    _offersById = {for (final o in offers) o.id: o};
  }

  // ---- poizvedbe

  List<SectionInfo> get sections =>
      meta?.sections ?? [SectionInfo('zivila', 'Živila in vsakdanje potrebščine'), SectionInfo('dom', 'Dom, vrt in DIY')];

  List<CategoryInfo> categoriesIn(String section) =>
      (meta?.categories ?? const []).where((c) => c.section == section).toList();

  Chain? chain(String id) => _chains[id];
  String chainName(String id) => _chains[id]?.name ?? id;
  CategoryInfo? category(String? id) => id == null ? null : _categories[id];
  Offer? offer(String id) => _offersById[id];

  List<Offer> visible(OfferFilter f, String search) => offers
      .where((o) => f.accepts(o, categorySection) && matchesSearch(search, o.name, o.brand, o.chain))
      .toList();

  int countCategory(String id) => offers.where((o) => o.category == id && !o.isExpired()).length;
  int countChain(String id) => offers.where((o) => o.chain == id && !o.isExpired()).length;

  List<Offer> comparable(Offer o) {
    final l = offers.where((x) {
      if (x.id == o.id || x.isExpired()) return false;
      if (o.ean != null && x.ean == o.ean) return true;
      if (o.kind != null && x.kind == o.kind && x.unit == o.unit) return true;
      return false;
    }).toList();
    l.sort((a, b) => (a.unitPrice ?? a.price).compareTo(b.unitPrice ?? b.price));
    return l;
  }

  List<PricePoint> historyFor(Offer o) => history[o.historyKey] ?? const [];

  List<Catalog> catalogs([String? chain]) =>
      (meta?.catalogs ?? const []).where((c) => chain == null || c.chain == chain).toList();
}

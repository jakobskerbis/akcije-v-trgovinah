import 'dart:convert';
import 'dart:io';

import 'package:akcije_si/logic/highlights.dart';
import 'package:akcije_si/logic/matching.dart';
import 'package:akcije_si/models/feed.dart';
import 'package:akcije_si/models/guide.dart';
import 'package:akcije_si/models/shared_doc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async => initializeDateFormatting('sl_SI'));

  group('ujemanje (enako kot iOS)', () {
    test('skloni in šumniki', () {
      expect(matchesTerm('piščančje prsi', 'Piščančja prsa Izbrana kakovost'), isTrue);
      expect(matchesTerm('piscancje prsi', 'NAŠE NAM PAŠE Piščančje prsi brez kože'), isTrue);
      expect(matchesTerm('losos', 'File lososa'), isTrue);
      expect(matchesTerm('mleko', 'Pomursko mleko 3,5% m.m.'), isTrue);
      expect(matchesTerm('piščančje prsi', 'Piščančja bedra'), isFalse);
      expect(matchesTerm('', 'karkoli'), isFalse);
    });
  });

  test('kategorija opazovanega živila izloči mleko za čiščenje', () {
    final pool = [
      (name: 'Alpsko mleko, 1 l', category: 'mlecni' as String?),
      (name: 'Pomursko mleko 3,5%', category: 'mlecni' as String?),
      (name: 'CIEN Mleko za čiščenje', category: 'drogerija' as String?),
    ];
    final cat = inferCategory('mleko', pool);
    expect(cat, 'mlecni');
    final w = WatchTerm('mleko', cat);
    expect(pool.where((o) => matchesWatch(w, o.name, o.category)).length, 2);
  });

  group('skupni dokument', () {
    test('zmaga novejši zapis, tudi z mikrosekundami iz Darta', () {
      final old = SharedWatch(
          id: 'a', term: 'staro', createdAt: '2026-10-01T10:00:00.000Z', updatedAt: '2026-10-01T10:00:00.000Z');
      final neu = SharedWatch(
          id: 'a', term: 'novo', createdAt: '2026-10-01T10:00:00.000Z', updatedAt: '2026-10-02T10:00:00.123456Z');
      expect(mergeById([old], [neu], (w) => w.id, (w) => w.updatedAt).single.term, 'novo');
      expect(mergeById([neu], [old], (w) => w.id, (w) => w.updatedAt).single.term, 'novo');
    });

    test('časovni žig v obliki, ki jo bere Swift', () {
      expect(sharedTime(DateTime.utc(2026, 10, 14, 8, 30, 5, 7)), '2026-10-14T08:30:05.007Z');
    });

    test('stari izbrisi se počistijo', () {
      final doc = SharedDoc(watch: [
        SharedWatch(id: 'x', term: 'x', createdAt: '2026-01-01T00:00:00.000Z', updatedAt: '2026-01-01T00:00:00.000Z', deleted: true),
        SharedWatch(id: 'y', term: 'y', createdAt: '2026-01-01T00:00:00.000Z', updatedAt: sharedNow(), deleted: true),
      ]);
      purge(doc);
      expect(doc.watch.map((w) => w.id), ['y']);
    });

    test('JSON iz Swift (manjkajoči ključi) se prebere', () {
      final d = SharedDoc.fromJson(jsonDecode(
              '{"schemaVersion":1,"updatedAt":"2026-10-14T08:00:00.000Z","watch":[{"id":"A","term":"kava","createdAt":"2026-10-14T08:00:00.000Z","updatedAt":"2026-10-14T08:00:00.000Z","deleted":false}],"shopping":[]}')
          as Map<String, dynamic>);
      expect(d.watch.single.term, 'kava');
      expect(d.watch.single.category, isNull);
    });
  });

  group('ponudbe', () {
    final o = Offer.fromJson({
      'id': '1', 'chain': 'lidl', 'name': 'Kivi zlati', 'price': 0.49, 'regularPrice': 0.69, 'discountPct': 28,
      'unitPrice': 0.49, 'unit': 'kos', 'bestUnitPrice': false, 'validFrom': '2026-10-15', 'validTo': '2026-10-25',
      'condition': {'type': 'app', 'description': 'Lidl Plus'}, 'sourceUrl': 'u', 'imageUrl': null, 'fetchedAt': 'x',
    });

    test('dekodiranje in dnevi do konca', () {
      expect(o.condition, ConditionType.app);
      expect(o.daysLeft(DateTime(2026, 10, 20)), 5);
      expect(o.isStarted(DateTime(2026, 10, 14)), isFalse);
      expect(formatPrice(0.49), contains('0,49'));
    });

    test('filter loči sekciji živila / dom', () {
      final sadje = Offer(id: '2', chain: 'lidl', name: 'Jabolka', price: 1, category: 'sadje', validTo: DateTime(2099));
      final map = {'sadje': 'zivila'};
      expect(OfferFilter(section: 'zivila').accepts(sadje, map), isTrue);
      expect(OfferFilter(section: 'dom').accepts(sadje, map), isFalse);
      final potekla = Offer(id: '3', chain: 'lidl', name: 'X', price: 1, category: 'sadje', validTo: DateTime(2020));
      expect(OfferFilter(section: 'zivila').accepts(potekla, map), isFalse);
    });

    test('demo podatki so veljavni', () {
      final j = jsonDecode(File('assets/demo/offers.json').readAsStringSync()) as Map<String, dynamic>;
      final offers = (j['offers'] as List).map((e) => Offer.fromJson((e as Map).cast<String, dynamic>())).toList();
      expect(offers.length, greaterThan(100));
      final m = Meta.fromJson(jsonDecode(File('assets/demo/meta.json').readAsStringSync()) as Map<String, dynamic>);
      expect(m.sections.map((s) => s.id), containsAll(['zivila', 'dom']));
      final g = Guide.fromJson(jsonDecode(File('assets/demo/guide.json').readAsStringSync()) as Map<String, dynamic>);
      expect(g.title, isNotEmpty);
    });
  });
}

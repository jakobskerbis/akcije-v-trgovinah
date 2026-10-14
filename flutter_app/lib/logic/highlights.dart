import 'package:intl/intl.dart';

import '../models/feed.dart';
import 'matching.dart';

enum HighlightReason { watch, discount, bestUnit }

enum SortOrder { discount, unitPrice, price, ending }

extension SortOrderLabel on SortOrder {
  String get label => switch (this) {
        SortOrder.discount => 'Popust',
        SortOrder.unitPrice => 'Cena na enoto',
        SortOrder.price => 'Cena',
        SortOrder.ending => 'Konec akcije',
      };
}

class OfferFilter {
  Set<String> chains = {};
  Set<String> categories = {};
  Set<ConditionType> conditions = {};
  bool onlyActive = false;
  String section;

  OfferFilter({this.section = 'zivila'});

  bool get isActive => chains.isNotEmpty || categories.isNotEmpty || conditions.isNotEmpty || onlyActive;

  bool accepts(Offer o, Map<String, String> categorySection) {
    final sec = categorySection[o.category];
    if (sec != null && sec != section) return false;
    if (chains.isNotEmpty && !chains.contains(o.chain)) return false;
    if (categories.isNotEmpty && !categories.contains(o.category)) return false;
    if (conditions.isNotEmpty && !conditions.contains(o.condition)) return false;
    if (onlyActive && !o.isStarted()) return false;
    if (o.isExpired()) return false;
    return true;
  }
}

Set<HighlightReason> reasonsFor(Offer o, int threshold, List<WatchTerm> watchTerms) {
  final r = <HighlightReason>{};
  if ((o.discountPct ?? 0) >= threshold) r.add(HighlightReason.discount);
  if (o.bestUnitPrice) r.add(HighlightReason.bestUnit);
  if (watchTerms.any((t) => matchesWatch(t, o.name, o.category))) r.add(HighlightReason.watch);
  return r;
}

List<Offer> sortOffers(Iterable<Offer> offers, SortOrder order) {
  final l = offers.toList();
  switch (order) {
    case SortOrder.discount:
      l.sort((a, b) {
        final c = (b.discountPct ?? -1).compareTo(a.discountPct ?? -1);
        return c != 0 ? c : a.price.compareTo(b.price);
      });
    case SortOrder.unitPrice:
      l.sort((a, b) => (a.unitPrice ?? double.infinity).compareTo(b.unitPrice ?? double.infinity));
    case SortOrder.price:
      l.sort((a, b) => a.price.compareTo(b.price));
    case SortOrder.ending:
      l.sort((a, b) => (a.daysLeft() ?? 1 << 30).compareTo(b.daysLeft() ?? 1 << 30));
  }
  return l;
}

final _euro = NumberFormat.currency(locale: 'sl_SI', symbol: '€', decimalDigits: 2);
final _short = DateFormat('d. M.', 'sl_SI');

String formatPrice(double v) => _euro.format(v);
String formatDay(DateTime d) => _short.format(d);

String? formatUnitPrice(Offer o) {
  if (o.unitPrice == null || o.unit == null) return null;
  return '${formatPrice(o.unitPrice!)}/${o.unit}';
}

String? formatDaysLeft(Offer o) {
  if (!o.isStarted() && o.validFrom != null) return 'od ${formatDay(o.validFrom!)}';
  final d = o.daysLeft();
  if (d == null) return o.chain == 'hofer' ? 'do razprodaje' : null;
  if (d < 0) return 'poteklo';
  if (d == 0) return 'še danes';
  if (d == 1) return 'še 1 dan';
  if (d == 2) return 'še 2 dneva';
  return 'še $d dni';
}

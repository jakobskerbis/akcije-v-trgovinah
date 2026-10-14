// Podatki z GitHub Pages (offers.json, coupons.json, meta.json, history.json).

enum ConditionType { none, loyaltyCard, app, coupon, multiBuy }

ConditionType conditionFrom(String? s) => switch (s) {
      'loyaltyCard' => ConditionType.loyaltyCard,
      'app' => ConditionType.app,
      'coupon' => ConditionType.coupon,
      'multiBuy' => ConditionType.multiBuy,
      _ => ConditionType.none,
    };

extension ConditionLabel on ConditionType {
  String get label => switch (this) {
        ConditionType.none => 'Brez pogoja',
        ConditionType.loyaltyCard => 'Kartica',
        ConditionType.app => 'Aplikacija',
        ConditionType.coupon => 'Kupon',
        ConditionType.multiBuy => 'Količinski',
      };
}

DateTime? parseDay(String? s) {
  if (s == null || s.length < 10) return null;
  return DateTime.tryParse(s.substring(0, 10));
}

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

class Offer {
  final String id;
  final String? productKey;
  final String chain;
  final String name;
  final String? brand;
  final String? category;
  final String? kind;
  final String? packSize;
  final double price;
  final double? regularPrice;
  final int? discountPct;
  final double? unitPrice;
  final String? unit;
  final bool bestUnitPrice;
  final DateTime? validFrom;
  final DateTime? validTo;
  final ConditionType condition;
  final String? conditionText;
  final String? ean;
  final String? sourceUrl;
  final String? imageUrl;
  final bool stale;

  Offer({
    required this.id,
    required this.chain,
    required this.name,
    required this.price,
    this.productKey,
    this.brand,
    this.category,
    this.kind,
    this.packSize,
    this.regularPrice,
    this.discountPct,
    this.unitPrice,
    this.unit,
    this.bestUnitPrice = false,
    this.validFrom,
    this.validTo,
    this.condition = ConditionType.none,
    this.conditionText,
    this.ean,
    this.sourceUrl,
    this.imageUrl,
    this.stale = false,
  });

  factory Offer.fromJson(Map<String, dynamic> j) {
    final cond = (j['condition'] as Map?)?.cast<String, dynamic>() ?? const {};
    return Offer(
      id: j['id'] as String,
      productKey: j['productKey'] as String?,
      chain: j['chain'] as String,
      name: j['name'] as String,
      brand: j['brand'] as String?,
      category: j['category'] as String?,
      kind: j['kind'] as String?,
      packSize: j['packSize'] as String?,
      price: (j['price'] as num).toDouble(),
      regularPrice: (j['regularPrice'] as num?)?.toDouble(),
      discountPct: (j['discountPct'] as num?)?.toInt(),
      unitPrice: (j['unitPrice'] as num?)?.toDouble(),
      unit: j['unit'] as String?,
      bestUnitPrice: j['bestUnitPrice'] == true,
      validFrom: parseDay(j['validFrom'] as String?),
      validTo: parseDay(j['validTo'] as String?),
      condition: conditionFrom(cond['type'] as String?),
      conditionText: cond['description'] as String?,
      ean: j['ean'] as String?,
      sourceUrl: j['sourceUrl'] as String?,
      imageUrl: j['imageUrl'] as String?,
      stale: j['stale'] == true,
    );
  }

  /// Dni do konca akcije (0 = danes zadnji dan), null če ni znano.
  int? daysLeft([DateTime? now]) {
    final end = validTo;
    if (end == null) return null;
    final today = now == null ? _today() : DateTime(now.year, now.month, now.day);
    return end.difference(today).inDays;
  }

  bool isStarted([DateTime? now]) {
    final s = validFrom;
    if (s == null) return true;
    final today = now == null ? _today() : DateTime(now.year, now.month, now.day);
    return !s.isAfter(today);
  }

  bool isExpired([DateTime? now]) {
    final d = daysLeft(now);
    return d != null && d < 0;
  }

  String get historyKey => '${productKey ?? id}|${condition.name}';
}

class Coupon {
  final String id;
  final String chain;
  final String title;
  final String? discount;
  final String? conditions;
  final DateTime? validFrom;
  final DateTime? validTo;
  final String howToRedeem;
  final bool? personal;
  final bool? needsActivation;
  final String? imageUrl;
  final String? backImageUrl;
  final String sourceUrl;

  Coupon.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        chain = j['chain'] as String,
        title = j['title'] as String,
        discount = j['discount'] as String?,
        conditions = j['conditions'] as String?,
        validFrom = parseDay(j['validFrom'] as String?),
        validTo = parseDay(j['validTo'] as String?),
        howToRedeem = (j['howToRedeem'] as String?) ?? 'card',
        personal = j['personal'] as bool?,
        needsActivation = j['needsActivation'] as bool?,
        imageUrl = j['imageUrl'] as String?,
        backImageUrl = j['backImageUrl'] as String?,
        sourceUrl = (j['sourceUrl'] as String?) ?? '';

  String get redeemLabel => switch (howToRedeem) {
        'app' => 'V aplikaciji',
        'card' => 'S kartico',
        'printed' => 'Tiskan kupon',
        _ => howToRedeem,
      };
}

class Chain {
  final String id, name, color;
  final String? website, catalogUrl, section;
  Chain.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String,
        color = j['color'] as String,
        website = j['website'] as String?,
        catalogUrl = j['catalogUrl'] as String?,
        section = j['section'] as String?;
}

class CategoryInfo {
  final String id, label, section, icon;
  final bool food;
  CategoryInfo.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        label = j['label'] as String,
        section = j['section'] as String,
        icon = (j['icon'] as String?) ?? 'tag',
        food = j['food'] == true;
}

class SectionInfo {
  final String id, label;
  SectionInfo(this.id, this.label);
  SectionInfo.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        label = j['label'] as String;
}

class SourceStatus {
  final String chain, source, url, status;
  final int count;
  final String? error;
  final List<String> notes;
  SourceStatus.fromJson(Map<String, dynamic> j)
      : chain = j['chain'] as String,
        source = j['source'] as String,
        url = j['url'] as String,
        status = j['status'] as String,
        count = (j['count'] as num?)?.toInt() ?? 0,
        error = j['error'] as String?,
        notes = ((j['notes'] as List?) ?? const []).cast<String>();
}

class Catalog {
  final String chain, title, url;
  final DateTime? validFrom, validTo;
  Catalog.fromJson(Map<String, dynamic> j)
      : chain = j['chain'] as String,
        title = j['title'] as String,
        url = j['url'] as String,
        validFrom = parseDay(j['validFrom'] as String?),
        validTo = parseDay(j['validTo'] as String?);
}

class Meta {
  final String? generatedAt;
  final int discountThresholdDefault;
  final List<SourceStatus> sources;
  final List<Chain> chains;
  final List<Catalog> catalogs;
  final List<SectionInfo> sections;
  final List<CategoryInfo> categories;

  Meta.fromJson(Map<String, dynamic> j)
      : generatedAt = j['generatedAt'] as String?,
        discountThresholdDefault = (j['discountThresholdDefault'] as num?)?.toInt() ?? 30,
        sources = _list(j['sources'], SourceStatus.fromJson),
        chains = _list(j['chains'], Chain.fromJson),
        catalogs = _list(j['catalogs'], Catalog.fromJson),
        sections = _list(j['sections'], SectionInfo.fromJson),
        categories = _list(j['categories'], CategoryInfo.fromJson);
}

List<T> _list<T>(Object? raw, T Function(Map<String, dynamic>) f) =>
    ((raw as List?) ?? const []).map((e) => f((e as Map).cast<String, dynamic>())).toList();

class PricePoint {
  final DateTime date;
  final double price;
  PricePoint(this.date, this.price);
}

Map<String, List<PricePoint>> parseHistory(Map<String, dynamic> j) {
  final out = <String, List<PricePoint>>{};
  j.forEach((k, v) {
    final pts = <PricePoint>[];
    for (final row in (v as List)) {
      final r = row as List;
      final d = parseDay(r[0] as String?);
      if (d != null) pts.add(PricePoint(d, (r[1] as num).toDouble()));
    }
    pts.sort((a, b) => a.date.compareTo(b.date));
    out[k] = pts;
  });
  return out;
}

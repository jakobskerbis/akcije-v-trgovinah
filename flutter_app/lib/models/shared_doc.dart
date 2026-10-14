// Oblika shared.json v zasebnem repozitoriju – enaka kot v iOS aplikaciji
// (ios/AkcijeSI/Sync/SharedDoc.swift). Časovni žigi: UTC z milisekundami.

String sharedNow() => sharedTime(DateTime.now());

String sharedTime(DateTime d) {
  final u = d.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  String three(int v) => v.toString().padLeft(3, '0');
  return '${u.year.toString().padLeft(4, '0')}-${two(u.month)}-${two(u.day)}'
      'T${two(u.hour)}:${two(u.minute)}:${two(u.second)}.${three(u.millisecond)}Z';
}

DateTime sharedDate(String s) => DateTime.tryParse(s)?.toUtc() ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

class SharedWatch {
  String id, term, createdAt, updatedAt;
  String? category, by;
  bool deleted;

  SharedWatch({
    required this.id,
    required this.term,
    required this.createdAt,
    required this.updatedAt,
    this.category,
    this.by,
    this.deleted = false,
  });

  factory SharedWatch.fromJson(Map<String, dynamic> j) => SharedWatch(
        id: j['id'] as String,
        term: j['term'] as String? ?? '',
        category: j['category'] as String?,
        createdAt: j['createdAt'] as String? ?? sharedNow(),
        updatedAt: j['updatedAt'] as String? ?? sharedNow(),
        deleted: j['deleted'] == true,
        by: j['by'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'term': term,
        'category': category,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'deleted': deleted,
        'by': by,
      };
}

class SharedShopping {
  String id, title, createdAt, updatedAt;
  String? offerId, productKey, chain, note, by;
  double? price;
  int quantity;
  bool checked, deleted;

  SharedShopping({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.offerId,
    this.productKey,
    this.chain,
    this.price,
    this.quantity = 1,
    this.checked = false,
    this.note,
    this.deleted = false,
    this.by,
  });

  factory SharedShopping.fromJson(Map<String, dynamic> j) => SharedShopping(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        offerId: j['offerId'] as String?,
        productKey: j['productKey'] as String?,
        chain: j['chain'] as String?,
        price: (j['price'] as num?)?.toDouble(),
        quantity: (j['quantity'] as num?)?.toInt() ?? 1,
        checked: j['checked'] == true,
        note: j['note'] as String?,
        createdAt: j['createdAt'] as String? ?? sharedNow(),
        updatedAt: j['updatedAt'] as String? ?? sharedNow(),
        deleted: j['deleted'] == true,
        by: j['by'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'offerId': offerId,
        'productKey': productKey,
        'chain': chain,
        'price': price,
        'quantity': quantity,
        'checked': checked,
        'note': note,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'deleted': deleted,
        'by': by,
      };
}

class SharedDoc {
  int schemaVersion;
  String updatedAt;
  List<SharedWatch> watch;
  List<SharedShopping> shopping;

  SharedDoc({this.schemaVersion = 1, String? updatedAt, List<SharedWatch>? watch, List<SharedShopping>? shopping})
      : updatedAt = updatedAt ?? sharedNow(),
        watch = watch ?? [],
        shopping = shopping ?? [];

  factory SharedDoc.fromJson(Map<String, dynamic> j) => SharedDoc(
        schemaVersion: (j['schemaVersion'] as num?)?.toInt() ?? 1,
        updatedAt: j['updatedAt'] as String?,
        watch: ((j['watch'] as List?) ?? const [])
            .map((e) => SharedWatch.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        shopping: ((j['shopping'] as List?) ?? const [])
            .map((e) => SharedShopping.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'updatedAt': updatedAt,
        'watch': watch.map((e) => e.toJson()).toList(),
        'shopping': shopping.map((e) => e.toJson()).toList(),
      };
}

/// Združi po id; zmaga novejši updatedAt (pri enakem oddaljeni zapis).
List<T> mergeById<T>(List<T> remote, List<T> local, String Function(T) id, String Function(T) updated) {
  final byId = <String, T>{for (final r in remote) id(r): r};
  for (final l in local) {
    final r = byId[id(l)];
    if (r == null || sharedDate(updated(l)).isAfter(sharedDate(updated(r)))) {
      byId[id(l)] = l;
    }
  }
  return byId.values.toList();
}

const tombstoneDays = 30;

void purge(SharedDoc doc, [DateTime? now]) {
  final cutoff = (now ?? DateTime.now()).toUtc().subtract(const Duration(days: tombstoneDays));
  doc.watch.removeWhere((w) => w.deleted && sharedDate(w.updatedAt).isBefore(cutoff));
  doc.shopping.removeWhere((s) => s.deleted && sharedDate(s.updatedAt).isBefore(cutoff));
  doc.watch.sort((a, b) => a.createdAt.compareTo(b.createdAt));
  doc.shopping.sort((a, b) => a.createdAt.compareTo(b.createdAt));
}

bool sameContent(SharedDoc a, SharedDoc b) {
  String w(SharedDoc d) => d.watch.map((e) => e.toJson().toString()).join('\n');
  String s(SharedDoc d) => d.shopping.map((e) => e.toJson().toString()).join('\n');
  return w(a) == w(b) && s(a) == s(b);
}

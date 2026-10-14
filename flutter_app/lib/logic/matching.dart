// Ujemanje opazovanih živil in iskanje – enako pravilo kot v iOS
// (ios/AkcijeSI/Logic/Matching.swift): besede primerjamo po predponah,
// ker ima slovenščina sklone ("piščančje prsi" / "piščančja prsa").

const _fold = {
  'č': 'c', 'ć': 'c', 'š': 's', 'ž': 'z', 'đ': 'd', 'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a',
  'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e', 'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i', 'ó': 'o', 'ò': 'o',
  'ö': 'o', 'ô': 'o', 'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u', 'ñ': 'n', 'ç': 'c',
};

String normalize(String s) {
  final lower = s.toLowerCase();
  final b = StringBuffer();
  for (final ch in lower.split('')) {
    b.write(_fold[ch] ?? ch);
  }
  return b.toString();
}

final _sep = RegExp(r'[^a-z0-9]+');

List<String> words(String s) => normalize(s).split(_sep).where((w) => w.isNotEmpty).toList();

String stem(String w) {
  final n = w.length;
  if (n <= 3) return w;
  if (n <= 5) return w.substring(0, n - 1);
  return w.substring(0, n - 2);
}

bool matchesTerm(String term, String name) {
  final tw = words(term);
  if (tw.isEmpty) return false;
  final nw = words(name);
  return tw.every((t) {
    final st = stem(t);
    return nw.any((n) => n.startsWith(st));
  });
}

/// Opazovano živilo s kategorijo ("mleko" v mlečnih izdelkih ne zadene "Mleko za čiščenje").
class WatchTerm {
  final String term;
  final String? category;
  const WatchTerm(this.term, [this.category]);
}

bool matchesWatch(WatchTerm w, String name, String? category) {
  if (w.category != null && category != w.category) return false;
  return matchesTerm(w.term, name);
}

/// Najpogostejša kategorija med trenutnimi zadetki, če obsega vsaj polovico.
String? inferCategory(String term, Iterable<({String name, String? category})> offers) {
  final counts = <String, int>{};
  var total = 0;
  for (final o in offers) {
    if (!matchesTerm(term, o.name)) continue;
    total++;
    if (o.category != null) counts[o.category!] = (counts[o.category!] ?? 0) + 1;
  }
  if (total == 0 || counts.isEmpty) return null;
  final best = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
  return best.value / total >= 0.5 ? best.key : null;
}

bool matchesSearch(String query, String name, String? brand, String chain) {
  final q = query.trim();
  if (q.isEmpty) return true;
  return matchesTerm(q, '$name ${brand ?? ''} $chain');
}

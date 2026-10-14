// guide.json – vodič po aplikacijah trgovcev in programih zvestobe.

class GuideSource {
  final String title, url, accessed;
  final String? date;
  GuideSource.fromJson(Map<String, dynamic> j)
      : title = j['title'] as String? ?? '',
        url = j['url'] as String? ?? '',
        date = j['date'] as String?,
        accessed = j['accessed'] as String? ?? '';
}

class GuideStatement {
  final String text;
  final bool advice;
  final List<GuideSource> sources;
  GuideStatement.fromJson(Map<String, dynamic> j)
      : text = j['text'] as String? ?? '',
        advice = j['advice'] == true,
        sources = _sources(j['sources']);
}

class GuideAnswer {
  final String answer, text;
  final List<GuideSource> sources;
  GuideAnswer.fromJson(Map<String, dynamic> j)
      : answer = j['answer'] as String? ?? 'neznano',
        text = j['text'] as String? ?? '',
        sources = _sources(j['sources']);

  String get label => switch (answer) {
        'da' => 'Da',
        'ne' => 'Ne',
        'delno' => 'Delno',
        _ => 'Ni podatka',
      };
}

class GuideApp {
  final String id, chain, recommendation, summary;
  final String? appName, program;
  final int installPriority;
  final List<GuideStatement> benefits, cardLinking, forCouple;
  final GuideAnswer personalCoupons, activationNeeded, storesInRegion;
  final String? ios, android, web;

  GuideApp.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        chain = j['chain'] as String? ?? 'other',
        recommendation = j['recommendation'] as String? ?? '',
        summary = j['summary'] as String? ?? '',
        appName = j['appName'] as String?,
        program = j['program'] as String?,
        installPriority = (j['installPriority'] as num?)?.toInt() ?? 99,
        benefits = _statements(j['benefits']),
        cardLinking = _statements(j['cardLinking']),
        forCouple = _statements(j['forCouple']),
        personalCoupons = GuideAnswer.fromJson(_map(j['personalCoupons'])),
        activationNeeded = GuideAnswer.fromJson(_map(j['activationNeeded'])),
        storesInRegion = GuideAnswer.fromJson(_map(j['storesInRegion'])),
        ios = _map(j['links'])['ios'] as String?,
        android = _map(j['links'])['android'] as String?,
        web = _map(j['links'])['web'] as String?;

  String get title => appName ?? program ?? id;
}

class LoyaltyProgram {
  final String id, name, chain, worthIt, why;
  final int rank;
  final GuideStatement cost;
  final List<GuideStatement> keyFacts;

  LoyaltyProgram.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String? ?? '',
        chain = j['chain'] as String? ?? 'other',
        worthIt = j['worthIt'] as String? ?? 'morda',
        why = j['why'] as String? ?? '',
        rank = (j['rank'] as num?)?.toInt() ?? 99,
        cost = GuideStatement.fromJson(_map(j['cost'])),
        keyFacts = _statements(j['keyFacts']);

  String get worthLabel => switch (worthIt) {
        'da' => 'Splača se',
        'morda' => 'Morda',
        _ => 'Ne splača se',
      };
}

class Guide {
  final String title, intro, disclaimer, updatedAt;
  final List<GuideApp> apps;
  final List<LoyaltyProgram> loyaltyPrograms;
  final List<GuideStatement> coupleTips;

  Guide.fromJson(Map<String, dynamic> j)
      : title = j['title'] as String? ?? 'Vodič',
        intro = j['intro'] as String? ?? '',
        disclaimer = j['disclaimer'] as String? ?? '',
        updatedAt = j['updatedAt'] as String? ?? '',
        apps = ((j['apps'] as List?) ?? const []).map((e) => GuideApp.fromJson(_map(e))).toList()
          ..sort((a, b) => a.installPriority.compareTo(b.installPriority)),
        loyaltyPrograms = ((j['loyaltyPrograms'] as List?) ?? const [])
            .map((e) => LoyaltyProgram.fromJson(_map(e)))
            .toList()
          ..sort((a, b) => a.rank.compareTo(b.rank)),
        coupleTips = _statements(j['coupleTips']);

  bool get isEmpty => apps.isEmpty && loyaltyPrograms.isEmpty;
}

Map<String, dynamic> _map(Object? o) => (o as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
List<GuideSource> _sources(Object? o) => ((o as List?) ?? const []).map((e) => GuideSource.fromJson(_map(e))).toList();
List<GuideStatement> _statements(Object? o) =>
    ((o as List?) ?? const []).map((e) => GuideStatement.fromJson(_map(e))).toList();

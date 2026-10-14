import 'package:flutter/material.dart';

import '../models/guide.dart';
import 'state.dart';
import 'widgets.dart';

class GuideView extends StatelessWidget {
  const GuideView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppListener(builder: (context, s) {
      final g = s.store.guide;
      if (g == null || g.isEmpty) {
        return const EmptyState(icon: Icons.menu_book_outlined, title: 'Vodič se nalaga', message: 'Vodič se prenese skupaj z akcijami.');
      }
      final tt = Theme.of(context).textTheme;
      return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        Padding(padding: const EdgeInsets.all(16), child: Text(g.intro)),
        if (g.loyaltyPrograms.isNotEmpty) ...[
          _h(context, 'Programi zvestobe – ali se splača včlaniti?'),
          for (final p in g.loyaltyPrograms)
            ListTile(
              leading: CircleAvatar(child: Text('${p.rank}')),
              title: Text(p.name),
              subtitle: Text(p.why, maxLines: 3, overflow: TextOverflow.ellipsis),
              trailing: _worth(context, p),
              onTap: () => _push(context, p.name, _LoyaltyDetail(p)),
            ),
        ],
        _h(context, 'Aplikacije trgovcev (vrstni red namestitve)'),
        for (final a in g.apps)
          ListTile(
            leading: CircleAvatar(child: Text('${a.installPriority}')),
            title: Row(children: [
              if (a.chain != 'other') ...[ChainTag(s.store, a.chain), const SizedBox(width: 8)],
              Flexible(child: Text(a.title)),
            ]),
            subtitle: Text('${a.recommendation} · ${a.summary}', maxLines: 3, overflow: TextOverflow.ellipsis),
            onTap: () => _push(context, a.title, _AppDetail(a)),
          ),
        if (g.coupleTips.isNotEmpty) ...[
          _h(context, 'Nasveti za par'),
          for (final t in g.coupleTips) Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), child: StatementView(t)),
        ],
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('${g.disclaimer}\nPosodobljeno: ${g.updatedAt}', style: tt.bodySmall),
        ),
      ]);
    });
  }

  Widget _worth(BuildContext context, LoyaltyProgram p) {
    final c = switch (p.worthIt) { 'da' => Colors.green, 'morda' => Colors.orange, _ => Colors.grey };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
      child: Text(p.worthLabel, style: TextStyle(color: c.shade700, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }

  void _push(BuildContext context, String title, Widget body) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: Text(title)), body: body)));
  }
}

Widget _h(BuildContext context, String t) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(t, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.primary)),
    );

class _AppDetail extends StatelessWidget {
  final GuideApp a;
  const _AppDetail(this.a);

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(a.summary),
      if (a.benefits.isNotEmpty) ...[_h(context, 'Kaj prinese'), for (final b in a.benefits) StatementView(b)],
      _h(context, 'Ali so kuponi osebni?'),
      AnswerView(a.personalCoupons),
      _h(context, 'Ali je kupone treba aktivirati?'),
      AnswerView(a.activationNeeded),
      if (a.cardLinking.isNotEmpty) ...[_h(context, 'Povezava kartic'), for (final b in a.cardLinking) StatementView(b)],
      if (a.forCouple.isNotEmpty) ...[_h(context, 'Za par'), for (final b in a.forCouple) StatementView(b)],
      _h(context, 'Trgovine v najini regiji'),
      AnswerView(a.storesInRegion),
      _h(context, 'Povezave'),
      if (a.android != null) TextButton(onPressed: () => openUrl(a.android), child: const Text('Google Play')),
      if (a.ios != null) TextButton(onPressed: () => openUrl(a.ios), child: const Text('App Store')),
      if (a.web != null) TextButton(onPressed: () => openUrl(a.web), child: const Text('Spletna stran')),
    ]);
  }
}

class _LoyaltyDetail extends StatelessWidget {
  final LoyaltyProgram p;
  const _LoyaltyDetail(this.p);

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(p.worthLabel, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      Text(p.why),
      _h(context, 'Stroški'),
      StatementView(p.cost),
      if (p.keyFacts.isNotEmpty) ...[_h(context, 'Ključna dejstva'), for (final f in p.keyFacts) StatementView(f)],
    ]);
  }
}

class StatementView extends StatelessWidget {
  final GuideStatement st;
  const StatementView(this.st, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (st.advice) ...[const Icon(Icons.lightbulb_outline, size: 18, color: Colors.amber), const SizedBox(width: 6)],
          Expanded(child: Text(st.text)),
        ]),
        SourcesView(st.sources),
      ]),
    );
  }
}

class AnswerView extends StatelessWidget {
  final GuideAnswer a;
  const AnswerView(this.a, {super.key});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(a.label, style: Theme.of(context).textTheme.titleSmall),
        Text(a.text),
        SourcesView(a.sources),
      ]);
}

class SourcesView extends StatelessWidget {
  final List<GuideSource> sources;
  const SourcesView(this.sources, {super.key});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final s in sources)
          InkWell(
            onTap: () => openUrl(s.url),
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('Vir: ${s.title}${s.date != null ? ', ${s.date}' : ''} · preverjeno ${s.accessed}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
            ),
          ),
      ]);
}

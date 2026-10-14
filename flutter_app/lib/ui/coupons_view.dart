import 'package:flutter/material.dart';

import '../logic/highlights.dart';
import '../models/feed.dart';
import 'state.dart';
import 'widgets.dart';

class CouponsView extends StatelessWidget {
  const CouponsView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppListener(builder: (context, s) {
      final byChain = <String, List<Coupon>>{};
      for (final c in s.store.coupons) {
        byChain.putIfAbsent(c.chain, () => []).add(c);
      }
      final chains = byChain.keys.toList()..sort();
      return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        if (chains.isEmpty) const ListTile(title: Text('Trenutno ni zajetih kuponov.')),
        for (final ch in chains) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(children: [ChainTag(s.store, ch), const SizedBox(width: 8), const Text('kuponi in ugodnosti')]),
          ),
          for (final c in byChain[ch]!) _CouponCard(coupon: c),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
          child: Text('Katalogi in letaki', style: Theme.of(context).textTheme.titleMedium),
        ),
        for (final cat in s.store.catalogs())
          ListTile(
            leading: ChainTag(s.store, cat.chain),
            title: Text(cat.title),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => openUrl(cat.url),
          ),
        for (final ch in s.store.meta?.chains ?? <Chain>[])
          if (ch.catalogUrl != null)
            ListTile(
              leading: ChainTag(s.store, ch.id),
              title: const Text('Aktualna ponudba'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => openUrl(ch.catalogUrl),
            ),
      ]);
    });
  }
}

class _CouponCard extends StatelessWidget {
  final Coupon coupon;
  const _CouponCard({required this.coupon});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(coupon.title, style: tt.titleMedium),
          if (coupon.imageUrl != null) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _zoom(context),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(coupon.imageUrl!, height: 180, fit: BoxFit.contain, errorBuilder: (_, _, _) => const SizedBox.shrink()),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 4, children: [
            _chip(context, Icons.credit_card, coupon.redeemLabel),
            if (coupon.personal == false) _chip(context, Icons.group_outlined, 'Za vse člane'),
            if (coupon.needsActivation == true) _chip(context, Icons.touch_app_outlined, 'Aktiviraj v aplikaciji'),
          ]),
          if (coupon.validFrom != null && coupon.validTo != null)
            Text('Velja ${formatDay(coupon.validFrom!)} – ${formatDay(coupon.validTo!)}', style: tt.bodySmall),
          if (coupon.conditions != null)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Pogoji'),
              children: [Text(coupon.conditions!, style: tt.bodySmall)],
            ),
          if (coupon.sourceUrl.isNotEmpty)
            TextButton.icon(onPressed: () => openUrl(coupon.sourceUrl), icon: const Icon(Icons.link, size: 16), label: const Text('Vir')),
        ]),
      ),
    );
  }

  Widget _chip(BuildContext context, IconData i, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(i, size: 14, color: Theme.of(context).hintColor),
        const SizedBox(width: 4),
        Text(t, style: Theme.of(context).textTheme.bodySmall),
      ]);

  /// Povečan kupon s črtno kodo za skeniranje na blagajni.
  void _zoom(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(title: Text(coupon.title)),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          for (final u in [coupon.imageUrl, coupon.backImageUrl].whereType<String>())
            Padding(padding: const EdgeInsets.only(bottom: 16), child: InteractiveViewer(child: Image.network(u))),
        ]),
      ),
    ));
  }
}

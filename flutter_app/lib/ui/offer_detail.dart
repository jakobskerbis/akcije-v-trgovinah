import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../logic/highlights.dart';
import '../models/feed.dart';
import 'state.dart';
import 'widgets.dart';

class OfferDetailPage extends StatelessWidget {
  final Offer offer;
  const OfferDetailPage({super.key, required this.offer});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(offer.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: OfferDetailBody(offer: offer),
    );
  }
}

class OfferDetailBody extends StatelessWidget {
  final Offer offer;
  final void Function(Offer)? onSelect;
  const OfferDetailBody({super.key, required this.offer, this.onSelect});

  String get _watchTerm => offer.name.split(' ').take(2).map((w) => w.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '')).join(' ');

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final tt = Theme.of(context).textTheme;
    final cat = s.store.category(offer.category);
    final history = s.store.historyFor(offer);
    final others = s.store.comparable(offer);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        OfferImage(offer.imageUrl, size: 120),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              ChainTag(s.store, offer.chain),
              if (cat != null)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(categoryIcon(cat.icon), size: 14),
                  const SizedBox(width: 4),
                  Text(cat.label, style: tt.bodySmall),
                ]),
            ]),
            const SizedBox(height: 6),
            Text(offer.name, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            if (offer.brand != null) Text(offer.brand!, style: tt.bodyMedium?.copyWith(color: Theme.of(context).hintColor)),
            if (offer.packSize != null) Text(offer.packSize!, style: tt.bodySmall),
            const SizedBox(height: 8),
            Wrap(spacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(formatPrice(offer.price), style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
              if ((offer.discountPct ?? 0) > 0) DiscountBadge(offer.discountPct!),
            ]),
            if (offer.regularPrice != null)
              Text('Redna cena ${formatPrice(offer.regularPrice!)}',
                  style: tt.bodyMedium?.copyWith(decoration: TextDecoration.lineThrough, color: Theme.of(context).hintColor)),
            if (formatUnitPrice(offer) != null)
              Row(children: [
                Icon(Icons.scale, size: 16, color: offer.bestUnitPrice ? Colors.green.shade700 : Theme.of(context).hintColor),
                const SizedBox(width: 4),
                Text(formatUnitPrice(offer)! + (offer.bestUnitPrice ? ' · najnižja med trgovinami' : ''),
                    style: TextStyle(color: offer.bestUnitPrice ? Colors.green.shade700 : null)),
              ]),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 4, children: [ConditionBadge(offer), DaysLeftText(offer)]),
          ]),
        ),
      ]),
      const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(
          onPressed: () async {
            HapticFeedback.mediumImpact();
            await s.lists.addOffer(offer);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dodano na nakupovalni seznam')));
            }
          },
          icon: const Icon(Icons.add_shopping_cart),
          label: const Text('Na seznam'),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            HapticFeedback.selectionClick();
            await s.lists.addWatch(_watchTerm, category: offer.category);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Opazuješ »$_watchTerm«')));
            }
          },
          icon: const Icon(Icons.visibility_outlined),
          label: Text('Opazuj »$_watchTerm«'),
        ),
        if (offer.sourceUrl != null)
          OutlinedButton.icon(onPressed: () => openUrl(offer.sourceUrl), icon: const Icon(Icons.open_in_new), label: const Text('Vir')),
      ]),
      const SizedBox(height: 24),
      Text('Zgodovina cene', style: tt.titleMedium),
      const SizedBox(height: 8),
      if (history.length < 2)
        Text(history.isEmpty
            ? 'Zgodovina se še zbira.'
            : 'Za zdaj en zapis: ${formatPrice(history.first.price)} (${formatDay(history.first.date)}).')
      else
        SizedBox(height: 180, child: _HistoryChart(points: history)),
      const SizedBox(height: 24),
      Text('Primerjava med trgovinami', style: tt.titleMedium),
      const SizedBox(height: 8),
      if (others.isEmpty)
        const Text('Ta teden ni primerljivih akcij v drugih trgovinah.')
      else
        for (final o in others.take(12))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: ChainTag(s.store, o.chain),
            title: Text(o.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(formatPrice(o.price), style: const TextStyle(fontWeight: FontWeight.bold)),
              if (formatUnitPrice(o) != null) Text(formatUnitPrice(o)!, style: tt.bodySmall),
            ]),
            onTap: () => onSelect != null
                ? onSelect!(o)
                : Navigator.of(context).push(MaterialPageRoute(builder: (_) => OfferDetailPage(offer: o))),
          ),
      const SizedBox(height: 16),
      if (offer.validFrom != null)
        Text(offer.validTo != null
            ? 'Velja od ${formatDay(offer.validFrom!)} do ${formatDay(offer.validTo!)}'
            : 'Velja od ${formatDay(offer.validFrom!)}', style: tt.bodySmall),
      if (offer.ean != null) Text('EAN: ${offer.ean}', style: tt.bodySmall),
      if (offer.stale) Text('Podatek iz prejšnjega zajema (vir trenutno ni dosegljiv).', style: tt.bodySmall?.copyWith(color: Colors.orange)),
      Text('Velja cena v trgovini. Podatki so informativni.', style: tt.bodySmall),
    ]);
  }
}

class _HistoryChart extends StatelessWidget {
  final List<PricePoint> points;
  const _HistoryChart({required this.points});

  @override
  Widget build(BuildContext context) {
    final first = points.first.date;
    final spots = [for (final p in points) FlSpot(p.date.difference(first).inDays.toDouble(), p.price)];
    final color = Theme.of(context).colorScheme.primary;
    return LineChart(LineChartData(
      lineBarsData: [
        LineChartBarData(spots: spots, isStepLineChart: true, color: color, barWidth: 3, dotData: const FlDotData(show: true)),
      ],
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 24,
            interval: (spots.last.x / 4).clamp(1, 1000).toDouble(),
            getTitlesWidget: (v, meta) => Text(formatDay(first.add(Duration(days: v.round()))), style: const TextStyle(fontSize: 10)),
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(showTitles: true, reservedSize: 44, getTitlesWidget: (v, meta) => Text(v.toStringAsFixed(2), style: const TextStyle(fontSize: 10))),
        ),
      ),
      gridData: const FlGridData(show: true, drawVerticalLine: false),
      borderData: FlBorderData(show: false),
    ));
  }
}

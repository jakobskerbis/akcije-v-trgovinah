import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/app_store.dart';
import '../logic/highlights.dart';
import '../models/feed.dart';

Color hexColor(String hex) {
  var s = hex.replaceAll('#', '');
  if (s.length == 3) s = s.split('').map((c) => '$c$c').join();
  return Color(int.tryParse('FF$s', radix: 16) ?? 0xFF888888);
}

Color chainColor(AppStore store, String chain) {
  final c = store.chain(chain);
  return c == null ? Colors.grey : hexColor(c.color);
}

/// SF Symbol imena iz meta.json -> Material ikone.
IconData categoryIcon(String sf) => switch (sf) {
      'fork.knife' => Icons.restaurant,
      'bird' => Icons.egg_alt_outlined,
      'fish' => Icons.set_meal_outlined,
      'triangle.lefthalf.filled' => Icons.change_history,
      'carton' => Icons.local_drink_outlined,
      'carrot' => Icons.eco_outlined,
      'apple.logo' => Icons.apple,
      'birthday.cake' => Icons.bakery_dining_outlined,
      'takeoutbag.and.cup.and.straw' => Icons.ramen_dining_outlined,
      'snowflake' => Icons.ac_unit,
      'waterbottle' => Icons.local_bar_outlined,
      'popcorn' => Icons.cookie_outlined,
      'basket' => Icons.shopping_basket_outlined,
      'drop' => Icons.water_drop_outlined,
      'bubbles.and.sparkles' => Icons.cleaning_services_outlined,
      'pawprint' => Icons.pets,
      'sofa' => Icons.weekend_outlined,
      'frying.pan' => Icons.soup_kitchen_outlined,
      'leaf' => Icons.yard_outlined,
      'hammer' => Icons.handyman_outlined,
      'powerplug' => Icons.power_outlined,
      'tshirt' => Icons.checkroom,
      'figure.play' => Icons.sports_soccer_outlined,
      'car' => Icons.directions_car_outlined,
      _ => Icons.sell_outlined,
    };

IconData conditionIcon(ConditionType t) => switch (t) {
      ConditionType.none => Icons.verified_outlined,
      ConditionType.loyaltyCard => Icons.credit_card,
      ConditionType.app => Icons.smartphone,
      ConditionType.coupon => Icons.confirmation_number_outlined,
      ConditionType.multiBuy => Icons.layers_outlined,
    };

Future<void> openUrl(String? url) async {
  if (url == null) return;
  final u = Uri.tryParse(url);
  if (u != null) await launchUrl(u, mode: LaunchMode.externalApplication);
}

class ChainTag extends StatelessWidget {
  final AppStore store;
  final String chain;
  const ChainTag(this.store, this.chain, {super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Trgovina ${store.chainName(chain)}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: chainColor(store, chain), borderRadius: BorderRadius.circular(20)),
        child: Text(store.chainName(chain),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class DiscountBadge extends StatelessWidget {
  final int pct;
  const DiscountBadge(this.pct, {super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Popust $pct odstotkov',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
            color: pct >= 40 ? Colors.red.shade600 : Colors.orange.shade700, borderRadius: BorderRadius.circular(6)),
        child: Text('−$pct %',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
      ),
    );
  }
}

class ConditionBadge extends StatelessWidget {
  final Offer offer;
  const ConditionBadge(this.offer, {super.key});

  @override
  Widget build(BuildContext context) {
    if (offer.condition == ConditionType.none && offer.conditionText == null) return const SizedBox.shrink();
    final text = offer.conditionText ?? offer.condition.label;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(conditionIcon(offer.condition), size: 12),
        const SizedBox(width: 3),
        Flexible(child: Text(text, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall)),
      ]),
    );
  }
}

class DaysLeftText extends StatelessWidget {
  final Offer offer;
  const DaysLeftText(this.offer, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = formatDaysLeft(offer);
    if (t == null) return const SizedBox.shrink();
    final urgent = (offer.daysLeft() ?? 99) <= 1 && offer.isStarted();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(offer.isStarted() ? Icons.schedule : Icons.event, size: 12, color: urgent ? Colors.red : Theme.of(context).hintColor),
      const SizedBox(width: 3),
      Text(t, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: urgent ? Colors.red : Theme.of(context).hintColor)),
    ]);
  }
}

class PriceBlock extends StatelessWidget {
  final Offer offer;
  final bool large;
  final CrossAxisAlignment align;
  const PriceBlock(this.offer, {super.key, this.large = true, this.align = CrossAxisAlignment.start});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final up = formatUnitPrice(offer);
    return Column(crossAxisAlignment: align, mainAxisSize: MainAxisSize.min, children: [
      Text(formatPrice(offer.price),
          style: (large ? tt.titleLarge : tt.titleMedium)?.copyWith(fontWeight: FontWeight.w800)),
      if (offer.regularPrice != null)
        Text(formatPrice(offer.regularPrice!),
            style: tt.bodySmall?.copyWith(decoration: TextDecoration.lineThrough, color: Theme.of(context).hintColor)),
      if (up != null) Text(up, style: tt.bodySmall?.copyWith(color: Theme.of(context).hintColor)),
    ]);
  }
}

class OfferImage extends StatelessWidget {
  final String? url;
  final double size;
  const OfferImage(this.url, {super.key, this.size = 60});

  @override
  Widget build(BuildContext context) {
    final ph = Icon(Icons.image_outlined, color: Theme.of(context).hintColor);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
        clipBehavior: Clip.antiAlias,
        child: url == null
            ? ph
            : Image.network(url!,
                fit: BoxFit.contain,
                cacheWidth: (size * 2).round(),
                errorBuilder: (_, _, _) => ph,
                loadingBuilder: (c, child, p) => p == null ? child : const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  const EmptyState({super.key, required this.icon, required this.title, this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: Theme.of(context).hintColor),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).hintColor)),
          ],
        ]),
      ),
    );
  }
}

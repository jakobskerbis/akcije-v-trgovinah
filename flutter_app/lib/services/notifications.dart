import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/app_store.dart';
import '../logic/highlights.dart';
import '../logic/matching.dart';
import '../models/feed.dart';

/// Lokalna obvestila (Android in Windows): opazovana živila in povzetek novih
/// izpostavljenih akcij. Enaka pravila kot Notifier.swift.
class Notifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static const _notifiedKey = 'notifiedOfferIds';

  static Future<void> init() async {
    if (_ready) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      windows: WindowsInitializationSettings(
        appName: 'Akcije SI',
        appUserModelId: 'JakobSkerbis.AkcijeSI.App.1',
        guid: '6d1d4c2a-9a34-4c5b-9f5e-2f7e8a1b3c40',
      ),
    );
    try {
      await _plugin.initialize(settings: settings);
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  static Future<void> requestPermission() async {
    await init();
    if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
  }

  static Future<void> _show(int id, String title, String body) async {
    if (!_ready) return;
    const details = NotificationDetails(
      android: AndroidNotificationDetails('akcije', 'Akcije',
          channelDescription: 'Opazovana živila in izpostavljene akcije',
          importance: Importance.defaultImportance),
    );
    try {
      await _plugin.show(id: id, title: title, body: body, notificationDetails: details);
    } catch (_) {}
  }

  static Future<void> notifyNew(AppStore store, List<String> watchTerms) async {
    await init();
    final p = await SharedPreferences.getInstance();
    final notifyWatch = p.getBool('notifyWatch') ?? true;
    final notifyHighlights = p.getBool('notifyHighlights') ?? true;
    final threshold = p.getInt('threshold') ?? store.meta?.discountThresholdDefault ?? 30;
    if (!notifyWatch && !notifyHighlights) return;

    final already = (p.getStringList(_notifiedKey) ?? const <String>[]).toSet();
    final firstRun = already.isEmpty;
    final active = store.offers.where((o) => !o.isExpired()).toList();
    final watchHits = <(Offer, String)>[];
    final highlightHits = <Offer>[];
    for (final o in active) {
      if (already.contains(o.id)) continue;
      String? term;
      if (notifyWatch) {
        for (final t in watchTerms) {
          if (matchesTerm(t, o.name)) {
            term = t;
            break;
          }
        }
      }
      if (term != null) {
        watchHits.add((o, term));
      } else if (notifyHighlights &&
          store.category(o.category)?.food == true &&
          ((o.discountPct ?? 0) >= threshold || o.bestUnitPrice)) {
        highlightHits.add(o);
      }
    }
    if (!firstRun) {
      var id = DateTime.now().millisecondsSinceEpoch ~/ 1000 % 100000;
      for (final (o, t) in watchHits.take(5)) {
        final pct = o.discountPct != null ? ' (−${o.discountPct} %)' : '';
        await _show(id++, '${store.chainName(o.chain)}: ${o.name}', '${formatPrice(o.price)}$pct · opazuješ »$t«');
      }
      if (watchHits.length > 5) {
        await _show(id++, 'Opazovana živila', 'Še ${watchHits.length - 5} novih zadetkov na tvojem seznamu.');
      }
      if (highlightHits.isNotEmpty) {
        highlightHits.sort((a, b) => (b.discountPct ?? 0).compareTo(a.discountPct ?? 0));
        final names = highlightHits.take(3).map((o) => '${o.name} −${o.discountPct ?? 0} %').join(', ');
        await _show(id++, '${highlightHits.length} novih izpostavljenih akcij', names);
      }
    }
    final activeIds = active.map((o) => o.id).toSet();
    await p.setStringList(_notifiedKey, already.union(activeIds).intersection(activeIds).toList());
  }
}

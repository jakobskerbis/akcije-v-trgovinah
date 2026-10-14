import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../data/app_store.dart';
import '../data/lists_store.dart';
import 'notifications.dart';

const _task = 'akcije-osvezitev';

/// Android: osveževanje v ozadju vsakih ~6 ur (WorkManager).
/// Windows nima tega mehanizma; tam se podatki osvežijo ob zagonu in vsako uro med delovanjem.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      final store = AppStore();
      await store.loadCached();
      await store.refresh();
      final lists = ListsStore();
      await lists.load();
      await lists.sync();
      await Notifications.notifyNew(store, lists.watchTerms);
    } catch (_) {
      return false;
    }
    return true;
  });
}

Future<void> scheduleBackgroundRefresh() async {
  if (!Platform.isAndroid) return;
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask(
    _task,
    _task,
    frequency: const Duration(hours: 6),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}

import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'data/app_store.dart';
import 'data/lists_store.dart';
import 'services/background.dart';
import 'services/notifications.dart';
import 'ui/home_shell.dart';
import 'ui/state.dart';

/// Demo način (vzorčni podatki iz assets/demo) za posnetke zaslona:
/// flutter run --dart-define=DEMO=true
const demoMode = bool.fromEnvironment('DEMO');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('sl_SI');
  final store = AppStore(demoMode: demoMode);
  final lists = ListsStore(demoMode: demoMode);
  final ui = UiState();
  await Future.wait([store.loadCached(), lists.load(), ui.load()]);
  if (demoMode) lists.seedDemo(store.offers.where((o) => store.category(o.category)?.food == true).toList());
  runApp(AkcijeApp(store: store, lists: lists, ui: ui));
}

class AkcijeApp extends StatefulWidget {
  final AppStore store;
  final ListsStore lists;
  final UiState ui;
  const AkcijeApp({super.key, required this.store, required this.lists, required this.ui});

  @override
  State<AkcijeApp> createState() => _AkcijeAppState();
}

class _AkcijeAppState extends State<AkcijeApp> {
  Timer? _syncTimer, _refreshTimer;
  StreamSubscription<Uri>? _links;
  late final AppLifecycleListener _lifecycle;
  bool _resumed = true;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onStateChange: (s) => _resumed = s == AppLifecycleState.resumed);
    if (!demoMode) unawaited(_start());
  }

  Future<void> _start() async {
    await Notifications.init();
    if (Platform.isAndroid) {
      await Notifications.requestPermission();
      try {
        await scheduleBackgroundRefresh();
      } catch (_) {}
    }
    try {
      final links = AppLinks();
      final initial = await links.getInitialLink();
      if (initial != null) await widget.lists.applyConfigUri(initial);
      _links = links.uriLinkStream.listen(widget.lists.applyConfigUri);
    } catch (_) {}
    final last = widget.store.lastFetched;
    if (last == null || DateTime.now().difference(last) > const Duration(hours: 1) || widget.store.offers.isEmpty) {
      await _refresh();
    } else {
      await widget.lists.sync();
    }
    // med delovanjem: partnerjeve spremembe vsakih 20 s, akcije vsako uro (Windows nima osveževanja v ozadju)
    _syncTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_resumed) widget.lists.sync();
    });
    _refreshTimer = Timer.periodic(const Duration(hours: 1), (_) => _refresh());
  }

  Future<void> _refresh() async {
    await widget.store.refresh();
    await widget.lists.sync();
    await Notifications.notifyNew(widget.store, widget.lists.watchTerms);
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _refreshTimer?.cancel();
    _links?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui = widget.ui;
    const seed = Color(0xFF107A4A);
    return AppScope(
      store: widget.store,
      lists: widget.lists,
      ui: ui,
      refresh: _refresh,
      child: MaterialApp(
        title: 'Akcije SI',
        debugShowCheckedModeBanner: false,
        theme: _theme(ColorScheme.fromSeed(seedColor: seed)),
        darkTheme: _theme(ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark)),
        themeMode: ThemeMode.system,
        locale: const Locale('sl', 'SI'),
        supportedLocales: const [Locale('sl', 'SI'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => CallbackShortcuts(
          bindings: {
            for (final sec in AppSection.values)
              SingleActivator(LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + sec.index), control: true):
                  () => ui.setSection(sec),
            const SingleActivator(LogicalKeyboardKey.keyF, control: true): ui.focusSearch,
            const SingleActivator(LogicalKeyboardKey.keyR, control: true): _refresh,
          },
          child: Focus(autofocus: true, child: child!),
        ),
        home: const HomeShell(),
      ),
    );
  }
}

ThemeData _theme(ColorScheme scheme) => ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      navigationBarTheme: const NavigationBarThemeData(
        labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11, overflow: TextOverflow.ellipsis)),
      ),
    );

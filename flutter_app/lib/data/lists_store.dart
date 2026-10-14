import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../logic/matching.dart';
import '../models/feed.dart';
import '../models/shared_doc.dart';

/// Opazovana živila in nakupovalni seznam: lokalno (JSON datoteka) in
/// skupno prek zasebnega GitHub repozitorija (shared.json), kot v iOS aplikaciji.
class ListsStore extends ChangeNotifier {
  static const path = 'shared.json';
  static const _uuid = Uuid();
  final bool demoMode;
  final http.Client _client;
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  ListsStore({this.demoMode = false, http.Client? client}) : _client = client ?? http.Client();

  SharedDoc doc = SharedDoc();
  String owner = 'jakobskerbis';
  String repo = 'akcije-skupno';
  String token = '';
  String displayName = '';
  bool isSyncing = false;
  DateTime? lastSync;
  String? lastError;
  bool _pending = false;

  bool get isConfigured => owner.isNotEmpty && repo.isNotEmpty && token.isNotEmpty;

  List<SharedWatch> get watch => doc.watch.where((w) => !w.deleted).toList();
  List<SharedShopping> get shopping => doc.shopping.where((s) => !s.deleted).toList();
  List<WatchTerm> get watchTerms => watch.map((w) => WatchTerm(w.term, w.category)).toList();

  Future<File> _file() async {
    final base = await getApplicationSupportDirectory();
    return File('${base.path}${Platform.pathSeparator}lists.json');
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    owner = p.getString('syncOwner') ?? owner;
    repo = p.getString('syncRepo') ?? repo;
    displayName = p.getString('displayName') ?? '';
    if (!demoMode) {
      try {
        token = await _secure.read(key: 'githubToken') ?? '';
      } catch (_) {
        token = '';
      }
      final f = await _file();
      if (f.existsSync()) {
        try {
          doc = SharedDoc.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
        } catch (_) {}
      }
    }
    notifyListeners();
  }

  Future<void> saveSettings({String? newOwner, String? newRepo, String? newToken, String? newName}) async {
    owner = (newOwner ?? owner).trim();
    repo = (newRepo ?? repo).trim();
    token = (newToken ?? token).trim();
    displayName = (newName ?? displayName).trim();
    final p = await SharedPreferences.getInstance();
    await p.setString('syncOwner', owner);
    await p.setString('syncRepo', repo);
    await p.setString('displayName', displayName);
    try {
      await _secure.write(key: 'githubToken', value: token);
    } catch (_) {}
    notifyListeners();
  }

  /// akcijesi://sync?owner=..&repo=..&token=..
  Future<bool> applyConfigUri(Uri uri) async {
    if (uri.scheme != 'akcijesi' || uri.host != 'sync') return false;
    final q = uri.queryParameters;
    if (q['token'] == null || q['owner'] == null || q['repo'] == null) return false;
    await saveSettings(newOwner: q['owner'], newRepo: q['repo'], newToken: q['token']);
    unawaited(sync());
    return true;
  }

  Uri? get configUri => isConfigured
      ? Uri(scheme: 'akcijesi', host: 'sync', queryParameters: {'owner': owner, 'repo': repo, 'token': token})
      : null;

  Future<void> _persist() async {
    if (demoMode) return;
    final f = await _file();
    await f.writeAsString(jsonEncode(doc.toJson()));
  }

  String? get _by => displayName.isEmpty ? null : displayName;

  // ---- spremembe

  Future<void> addOffer(Offer o) async {
    final now = sharedNow();
    doc.shopping.add(SharedShopping(
      id: _uuid.v4().toUpperCase(),
      title: o.name,
      offerId: o.id,
      productKey: o.productKey,
      chain: o.chain,
      price: o.price,
      createdAt: now,
      updatedAt: now,
      by: _by,
    ));
    await _changed();
  }

  Future<void> addItem(String title) async {
    final t = title.trim();
    if (t.isEmpty) return;
    final now = sharedNow();
    doc.shopping.add(SharedShopping(id: _uuid.v4().toUpperCase(), title: t, createdAt: now, updatedAt: now, by: _by));
    await _changed();
  }

  Future<void> toggle(SharedShopping s) async {
    s.checked = !s.checked;
    s.updatedAt = sharedNow();
    await _changed();
  }

  Future<void> deleteItem(SharedShopping s) async {
    s.deleted = true;
    s.updatedAt = sharedNow();
    await _changed();
  }

  Future<void> clearChecked() async {
    final now = sharedNow();
    for (final s in doc.shopping.where((s) => s.checked && !s.deleted)) {
      s.deleted = true;
      s.updatedAt = now;
    }
    await _changed();
  }

  Future<void> addWatch(String term, {String? category}) async {
    final t = term.trim();
    if (t.isEmpty) return;
    final now = sharedNow();
    doc.watch.add(SharedWatch(
        id: _uuid.v4().toUpperCase(), term: t, category: category, createdAt: now, updatedAt: now, by: _by));
    await _changed();
  }

  Future<void> deleteWatch(SharedWatch w) async {
    w.deleted = true;
    w.updatedAt = sharedNow();
    await _changed();
  }

  Future<void> _changed() async {
    notifyListeners();
    await _persist();
    unawaited(sync());
  }

  // ---- sinhronizacija

  Uri get _contents => Uri.parse('https://api.github.com/repos/$owner/$repo/contents/$path');

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'AkcijeSI-Flutter',
      };

  Future<void> sync() async {
    if (!isConfigured || demoMode) return;
    if (isSyncing) {
      _pending = true;
      return;
    }
    isSyncing = true;
    notifyListeners();
    do {
      _pending = false;
      try {
        await _syncOnce();
        lastSync = DateTime.now();
        lastError = null;
      } catch (e) {
        lastError = e is SyncException ? e.message : e.toString();
      }
    } while (_pending);
    isSyncing = false;
    notifyListeners();
  }

  Future<void> _syncOnce() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final (remote, sha) = await _fetch();
      final merged = SharedDoc(
        watch: mergeById(remote.watch, doc.watch, (w) => w.id, (w) => w.updatedAt),
        shopping: mergeById(remote.shopping, doc.shopping, (s) => s.id, (s) => s.updatedAt),
      );
      purge(merged);
      purge(remote);
      doc = merged;
      await _persist();
      notifyListeners();
      if (sha != null && sameContent(merged, remote)) return;
      merged.updatedAt = sharedNow();
      if (await _put(merged, sha)) return;
    }
    throw SyncException('Sinhronizacija ni uspela zaradi sočasnih sprememb. Poskusi znova.');
  }

  Future<(SharedDoc, String?)> _fetch() async {
    final r = await _client.get(_contents, headers: _headers).timeout(const Duration(seconds: 30));
    if (r.statusCode == 404) return (SharedDoc(), null);
    if (r.statusCode != 200) throw SyncException.http(r.statusCode);
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final sha = j['sha'] as String?;
    final content = (j['content'] as String? ?? '').replaceAll('\n', '');
    if (content.isEmpty) return (SharedDoc(), sha);
    try {
      final decoded = utf8.decode(base64.decode(content));
      return (SharedDoc.fromJson(jsonDecode(decoded) as Map<String, dynamic>), sha);
    } catch (_) {
      return (SharedDoc(), sha);
    }
  }

  Future<bool> _put(SharedDoc d, String? sha) async {
    final json = const JsonEncoder.withIndent('  ').convert(d.toJson());
    final body = <String, dynamic>{
      'message': 'Posodobitev seznamov (${displayName.isEmpty ? 'Android/Windows' : displayName})',
      'content': base64.encode(utf8.encode(json)),
    };
    if (sha != null) body['sha'] = sha;
    final r = await _client
        .put(_contents, headers: {..._headers, 'Content-Type': 'application/json'}, body: jsonEncode(body))
        .timeout(const Duration(seconds: 30));
    if (r.statusCode == 200 || r.statusCode == 201) return true;
    if (r.statusCode == 409 || r.statusCode == 422) return false;
    throw SyncException.http(r.statusCode);
  }

  /// Za demo način in posnetke zaslona.
  void seedDemo(List<Offer> offers) {
    final now = sharedNow();
    final pool = offers.map((o) => (name: o.name, category: o.category));
    for (final (t, by) in [('piščančje prsi', 'Jakob'), ('mleko', 'Partnerka'), ('losos', 'Partnerka'), ('kava', 'Jakob')]) {
      doc.watch.add(SharedWatch(
          id: _uuid.v4(), term: t, category: inferCategory(t, pool), createdAt: now, updatedAt: now, by: by));
    }
    var i = 0;
    for (final o in offers.where((o) => (o.discountPct ?? 0) >= 30).take(4)) {
      doc.shopping.add(SharedShopping(
          id: _uuid.v4(),
          title: o.name,
          offerId: o.id,
          chain: o.chain,
          price: o.price,
          checked: i == 3,
          createdAt: now,
          updatedAt: now,
          by: i.isEven ? 'Jakob' : 'Partnerka'));
      i++;
    }
    notifyListeners();
  }
}

class SyncException implements Exception {
  final String message;
  SyncException(this.message);

  factory SyncException.http(int code) => SyncException(switch (code) {
        401 => 'Žeton ni veljaven (401). Preveri ga v nastavitvah.',
        403 => 'Dostop zavrnjen (403). Žeton potrebuje pravico Contents: Read and write.',
        404 => 'Repozitorij ne obstaja ali žeton nima dostopa (404).',
        _ => 'GitHub je vrnil napako $code.',
      });

  @override
  String toString() => message;
}

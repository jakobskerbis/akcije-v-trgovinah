import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/notifications.dart';
import 'state.dart';

void openSettings(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _name, _owner, _repo, _token, _paste;
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    final l = AppScope.of(context).lists;
    _name = TextEditingController(text: l.displayName);
    _owner = TextEditingController(text: l.owner);
    _repo = TextEditingController(text: l.repo);
    _token = TextEditingController(text: l.token);
    _paste = TextEditingController();
    _init = true;
  }

  @override
  void dispose() {
    for (final c in [_name, _owner, _repo, _token, _paste]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final l = AppScope.of(context).lists;
    await l.saveSettings(newName: _name.text, newOwner: _owner.text, newRepo: _repo.text, newToken: _token.text);
    await l.sync();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nastavitve')),
      body: AppListener(builder: (context, s) {
        final tt = Theme.of(context).textTheme;
        return ListView(padding: const EdgeInsets.all(16), children: [
          Text('Izpostavljene akcije', style: tt.titleMedium),
          Row(children: [
            Expanded(child: Text('Prag popusta: ${s.ui.threshold} %')),
            IconButton(
                tooltip: 'Manj',
                onPressed: s.ui.threshold > 10 ? () => s.ui.setThreshold(s.ui.threshold - 5) : null,
                icon: const Icon(Icons.remove_circle_outline)),
            IconButton(
                tooltip: 'Več',
                onPressed: s.ui.threshold < 70 ? () => s.ui.setThreshold(s.ui.threshold + 5) : null,
                icon: const Icon(Icons.add_circle_outline)),
          ]),
          const Divider(),
          Text('Obvestila', style: tt.titleMedium),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: s.ui.notifyWatch,
              onChanged: (v) => s.ui.setNotify(watch: v),
              title: const Text('Opazovana živila')),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: s.ui.notifyHighlights,
              onChanged: (v) => s.ui.setNotify(highlights: v),
              title: const Text('Nove izpostavljene akcije (povzetek)')),
          TextButton(onPressed: Notifications.requestPermission, child: const Text('Dovoli obvestila')),
          const Divider(),
          Text('Skupna raba seznamov', style: tt.titleMedium),
          const SizedBox(height: 4),
          const Text('Seznama se shranjujeta v zasebni GitHub repozitorij. Žeton ustvari na github.com → Settings → '
              'Developer settings → Fine-grained tokens, z dostopom samo do tega repozitorija in pravico '
              '»Contents: Read and write«. Navodila so v README.'),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Moje ime (npr. Jakob)')),
          TextField(controller: _owner, decoration: const InputDecoration(labelText: 'Lastnik repozitorija')),
          TextField(controller: _repo, decoration: const InputDecoration(labelText: 'Repozitorij')),
          TextField(
              controller: _token, obscureText: true, decoration: const InputDecoration(labelText: 'GitHub žeton (fine-grained)')),
          const SizedBox(height: 8),
          Row(children: [
            FilledButton(onPressed: _save, child: const Text('Shrani in sinhroniziraj')),
            const SizedBox(width: 12),
            if (s.lists.isSyncing) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
          if (s.lists.lastSync != null) Text('Zadnja sinhronizacija: ${s.lists.lastSync}', style: tt.bodySmall),
          if (s.lists.lastError != null) Text(s.lists.lastError!, style: tt.bodySmall?.copyWith(color: Colors.orange)),
          const SizedBox(height: 16),
          Text('Prenos nastavitev na drugo napravo', style: tt.titleSmall),
          if (s.lists.configUri != null)
            Center(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: QrImageView(data: s.lists.configUri.toString(), size: 220),
              ),
            ),
          const Text('QR koda vsebuje žeton – ne deli je z nikomer drugim. Na Androidu jo skeniraj s kamero.'),
          TextField(
            controller: _paste,
            decoration: const InputDecoration(labelText: 'ali prilepi povezavo akcijesi://sync?…'),
            onSubmitted: (v) async {
              final u = Uri.tryParse(v.trim());
              if (u != null && await s.lists.applyConfigUri(u)) {
                _owner.text = s.lists.owner;
                _repo.text = s.lists.repo;
                _token.text = s.lists.token;
                _paste.clear();
              }
            },
          ),
          const Divider(height: 32),
          Text('Podatki', style: tt.titleMedium),
          Text('Ponudb: ${s.store.offers.length}'),
          if (s.store.generatedAt != null) Text('Zajem na strežniku: ${s.store.generatedAt!.toLocal()}'),
          if (s.store.lastFetched != null) Text('Preneseno: ${s.store.lastFetched}'),
          for (final src in s.store.meta?.sources ?? const [])
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(src.status == 'ok' ? Icons.check_circle : Icons.warning_amber,
                  color: src.status == 'ok' ? Colors.green : Colors.orange),
              title: Text(s.store.chainName(src.chain)),
              trailing: Text(src.status == 'ok' ? '${src.count}' : (src.error ?? 'napaka')),
            ),
          if (s.store.lastError != null) Text(s.store.lastError!, style: tt.bodySmall?.copyWith(color: Colors.orange)),
          const SizedBox(height: 16),
          Text('Akcije SI je zasebna aplikacija za osebno rabo. Podatki so last trgovcev in so informativni; velja cena v trgovini.',
              style: tt.bodySmall),
        ]);
      }),
    );
  }
}

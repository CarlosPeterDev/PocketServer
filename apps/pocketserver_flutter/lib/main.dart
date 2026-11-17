import 'package:material_ui/material_ui.dart';
import 'package:pocketserver_contracts/pocketserver_contracts.dart';

import 'backups_page.dart';
import 'files_page.dart';
import 'native_storage.dart';

void main() => runApp(PocketServerApp(host: HostDiagnostics.current()));

class PocketServerApp extends StatelessWidget {
  const PocketServerApp({
    super.key,
    required this.host,
    this.readStorage = readAvailableStorage,
  });

  final HostDiagnostics host;
  final Future<int> Function() readStorage;

  @override
  Widget build(BuildContext context) {
    final platform = switch (host.platform) {
      HostPlatform.android => 'Android',
      HostPlatform.windows => 'Windows',
      HostPlatform.unsupported => 'Unsupported host',
    };

    return MaterialApp(
      title: 'PocketServer',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('PocketServer')),
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Host diagnostics',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  ListTile(
                    title: const Text('Platform'),
                    subtitle: Text(platform),
                  ),
                  ListTile(
                    title: const Text('OS version'),
                    subtitle: SelectableText(host.operatingSystemVersion),
                  ),
                  ListTile(
                    title: const Text('Logical processors'),
                    subtitle: Text('${host.logicalProcessors}'),
                  ),
                  if (host.platform != HostPlatform.unsupported)
                    _StorageTile(readStorage: readStorage),
                  if (host.platform != HostPlatform.unsupported) ...[
                    for (final view in LibraryView.values)
                      _AppCard(
                        title: view.title,
                        icon: view.icon,
                        page: FilesPage(view: view),
                      ),
                    const _AppCard(
                      title: 'Backups',
                      icon: Icons.backup_outlined,
                      page: BackupsPage(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppCard extends StatelessWidget {
  const _AppCard({required this.title, required this.icon, required this.page});
  final String title;
  final IconData icon;
  final Widget page;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right),
        onTap: () =>
            Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => page)),
      ),
    );
  }
}

class _StorageTile extends StatefulWidget {
  const _StorageTile({required this.readStorage});

  final Future<int> Function() readStorage;

  @override
  State<_StorageTile> createState() => _StorageTileState();
}

class _StorageTileState extends State<_StorageTile> {
  late Future<int> _storage = widget.readStorage();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: _storage,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        final value = switch (snapshot.connectionState) {
          ConnectionState.done when bytes != null =>
            '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GiB',
          ConnectionState.done => 'Unable to read available space',
          _ => 'Reading available space…',
        };
        return ListTile(
          title: const Text('Available app storage'),
          subtitle: Text(value),
          trailing: IconButton(
            tooltip: 'Refresh storage',
            icon: const Icon(Icons.refresh),
            onPressed: snapshot.connectionState == ConnectionState.done
                ? () => setState(() => _storage = widget.readStorage())
                : null,
          ),
        );
      },
    );
  }
}

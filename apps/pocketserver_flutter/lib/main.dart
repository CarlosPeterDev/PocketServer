import 'package:material_ui/material_ui.dart';
import 'package:pocketserver_contracts/pocketserver_contracts.dart';

import 'dashboard_page.dart';
import 'dashboard_server.dart';
import 'files_page.dart';
import 'native_storage.dart';

void main() => runApp(PocketServerApp(host: HostDiagnostics.current()));

class PocketServerApp extends StatefulWidget {
  const PocketServerApp({
    super.key,
    required this.host,
    this.readStorage = readAvailableStorage,
  });

  final HostDiagnostics host;
  final Future<int> Function() readStorage;

  @override
  State<PocketServerApp> createState() => _PocketServerAppState();
}

class _PocketServerAppState extends State<PocketServerApp> {
  final _dashboard = ValueNotifier<DashboardServer?>(null);

  @override
  void dispose() {
    _dashboard.value?.close();
    _dashboard.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
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
                    _StorageTile(readStorage: widget.readStorage),
                  if (host.platform != HostPlatform.unsupported) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Apps',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    GridView.extent(
                      maxCrossAxisExtent: 160,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        ValueListenableBuilder<DashboardServer?>(
                          valueListenable: _dashboard,
                          builder: (context, server, child) => _AppCard(
                            title: server == null ? 'Web dashboard' : 'Server running',
                            icon: Icons.dns_outlined,
                            page: DashboardPage(session: _dashboard),
                          ),
                        ),
                        for (final view in LibraryView.values)
                          _AppCard(
                            title: view.title,
                            icon: view.icon,
                            page: FilesPage(view: view),
                          ),
                      ],
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
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => page),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              backgroundColor: colors.primaryContainer,
              foregroundColor: colors.onPrimaryContainer,
              child: Icon(icon),
            ),
            const SizedBox(height: 8),
            Text(title, textAlign: TextAlign.center),
          ],
        ),
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

import 'package:flutter/material.dart';
import 'package:pocketserver_contracts/pocketserver_contracts.dart';

void main() => runApp(PocketServerApp(host: HostDiagnostics.current()));

class PocketServerApp extends StatelessWidget {
  const PocketServerApp({super.key, required this.host});

  final HostDiagnostics host;

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
      home: Scaffold(
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
